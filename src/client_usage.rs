//! Read Pi and Claude Code usage metadata without retaining message content.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs,
    io::{BufRead, BufReader, Read},
    path::{Path, PathBuf},
};

const MAX_USAGE_LINE: u64 = 4 * 1024 * 1024;

#[derive(Clone, Copy)]
enum ClientKind {
    Pi,
    Claude,
}

impl ClientKind {
    fn name(self) -> &'static str {
        match self {
            Self::Pi => "Pi",
            Self::Claude => "Claude Code",
        }
    }
}

#[derive(Deserialize)]
#[serde(untagged)]
enum UsageTime {
    Text(String),
    Number(u64),
}

impl UsageTime {
    fn seconds(&self) -> Option<u64> {
        match self {
            Self::Text(value) => super::analytics::parse_timestamp(value),
            Self::Number(value) => Some(if *value > 100_000_000_000 {
                value / 1000
            } else {
                *value
            }),
        }
    }
}

#[derive(Default, Deserialize)]
#[serde(default, rename_all = "camelCase")]
struct LocalTokens {
    #[serde(alias = "input_tokens")]
    input: u64,
    #[serde(alias = "output_tokens")]
    output: u64,
    #[serde(alias = "cache_read_input_tokens")]
    cache_read: u64,
    #[serde(alias = "cache_creation_input_tokens")]
    cache_write: u64,
    reasoning: u64,
    cost: Option<LocalCost>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalCost {
    total: f64,
    total_from_provider: Option<bool>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalMessage {
    id: Option<String>,
    response_id: Option<String>,
    role: Option<String>,
    provider: Option<String>,
    timestamp: Option<UsageTime>,
    usage: Option<LocalTokens>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalRecord {
    #[serde(rename = "type")]
    kind: String,
    id: Option<String>,
    uuid: Option<String>,
    timestamp: Option<UsageTime>,
    message: Option<LocalMessage>,
    #[serde(rename = "costUSD", alias = "costUsd")]
    cost_usd: Option<f64>,
}

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
struct UsageTotals {
    input_tokens: u64,
    output_tokens: u64,
    cached_input_tokens: u64,
    cache_write_input_tokens: u64,
    reasoning_tokens: u64,
    total_tokens: u64,
    steps: u64,
    cost_usd: Option<f64>,
    cost_complete: bool,
    tokens_complete: bool,
}

#[derive(Clone)]
struct UsageEntry {
    account: String,
    provider: String,
    time: u64,
    input: u64,
    output: u64,
    cached: u64,
    cache_write: u64,
    reasoning: u64,
    cost: Option<f64>,
    estimated: bool,
    output_complete: bool,
}

fn safe_id(value: Option<String>) -> Option<String> {
    value.filter(|value| !value.is_empty() && value.len() <= 512)
}

fn parse_usage_entry(
    record: LocalRecord,
    kind: ClientKind,
    account: &str,
    session: &str,
    fallback: &str,
) -> Option<(String, UsageEntry)> {
    let message = record.message?;
    let assistant = match kind {
        ClientKind::Pi => record.kind == "message" && message.role.as_deref() == Some("assistant"),
        ClientKind::Claude => record.kind == "assistant",
    };
    if !assistant {
        return None;
    }
    let time = record.timestamp.or(message.timestamp)?.seconds()?;
    let usage = message.usage?;
    let provider = match kind {
        ClientKind::Pi => safe_id(message.provider)?,
        ClientKind::Claude => "anthropic".into(),
    };
    if super::providers::removed_provider(&provider) {
        return None;
    }
    let input = usage
        .input
        .checked_add(usage.cache_read)?
        .checked_add(usage.cache_write)?;
    input.checked_add(usage.output)?;
    let recorded_cost = record.cost_usd.or(usage.cost.as_ref().map(|c| c.total));
    let cost = recorded_cost.filter(|c| c.is_finite() && *c >= 0.0);
    let estimated = usage
        .cost
        .as_ref()
        .is_none_or(|cost| cost.total_from_provider != Some(true));
    let id = match kind {
        ClientKind::Pi => safe_id(message.response_id)
            .or_else(|| safe_id(record.id).map(|id| format!("{session}:{id}"))),
        ClientKind::Claude => safe_id(message.id),
    }
    .or_else(|| safe_id(record.uuid))
    .unwrap_or_else(|| fallback.into());
    Some((
        format!("{account}:{provider}:{id}"),
        UsageEntry {
            account: account.into(),
            provider,
            time,
            input,
            output: if matches!(kind, ClientKind::Pi) {
                usage.output
            } else {
                0
            },
            cached: usage.cache_read,
            cache_write: usage.cache_write,
            // Pi output and Claude output already include reasoning tokens.
            reasoning: if matches!(kind, ClientKind::Pi) {
                usage.reasoning.min(usage.output)
            } else {
                0
            },
            cost,
            estimated,
            // Claude streamed assistant output can be a message_start placeholder.
            // Only input/cache totals are claimed without an authoritative result.
            output_complete: matches!(kind, ClientKind::Pi),
        },
    ))
}

fn merge_usage_snapshot(previous: &mut UsageEntry, latest: UsageEntry) {
    previous.time = previous.time.max(latest.time);
    previous.input = previous.input.max(latest.input);
    previous.output = previous.output.max(latest.output);
    previous.cached = previous.cached.max(latest.cached);
    previous.cache_write = previous.cache_write.max(latest.cache_write);
    previous.reasoning = previous.reasoning.max(latest.reasoning);
    previous.cost = match (previous.cost, latest.cost) {
        (Some(a), Some(b)) => Some(a.max(b)),
        (a, b) => a.or(b),
    };
    previous.estimated |= latest.estimated;
    previous.output_complete &= latest.output_complete;
}

fn usage_files(root: &Path, paths: &mut Vec<PathBuf>, partial: &mut bool) {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) => {
            *partial |= error.kind() != std::io::ErrorKind::NotFound;
            return;
        }
    };
    for entry in entries {
        let Ok(entry) = entry else {
            *partial = true;
            continue;
        };
        let Ok(kind) = entry.file_type() else {
            *partial = true;
            continue;
        };
        if kind.is_dir() {
            usage_files(&entry.path(), paths, partial);
        } else if kind.is_file() && entry.path().extension().is_some_and(|s| s == "jsonl") {
            paths.push(entry.path());
        }
    }
}

fn read_usage_file(
    path: &Path,
    kind: ClientKind,
    account: &str,
    records: &mut BTreeMap<String, UsageEntry>,
    partial: &mut bool,
) {
    let Ok(file) = fs::File::open(path) else {
        *partial = true;
        return;
    };
    let mut reader = BufReader::new(file);
    let mut line = Vec::new();
    let mut line_index = 0;
    let mut session = path.to_string_lossy().into_owned();
    loop {
        line.clear();
        let count = reader
            .by_ref()
            .take(MAX_USAGE_LINE + 1)
            .read_until(b'\n', &mut line);
        match count {
            Ok(0) => break,
            Err(_) => {
                *partial = true;
                break;
            }
            _ => {}
        }
        line_index += 1;
        if line.len() as u64 > MAX_USAGE_LINE {
            *partial = true;
            if !line.ends_with(b"\n") && reader.skip_until(b'\n').is_err() {
                break;
            }
            continue;
        }
        let Ok(record) = serde_json::from_slice::<LocalRecord>(&line) else {
            continue;
        };
        if record.kind == "session" {
            if let Some(id) = safe_id(record.id) {
                session = id;
            }
            continue;
        }
        let fallback = format!("{session}:{line_index}");
        if let Some((key, value)) = parse_usage_entry(record, kind, account, &session, &fallback) {
            records
                .entry(key)
                .and_modify(|old| merge_usage_snapshot(old, value.clone()))
                .or_insert(value);
        }
    }
}

fn aggregate_usage<'a>(
    entries: impl Iterator<Item = &'a UsageEntry>,
    partial: bool,
) -> UsageTotals {
    let mut totals = UsageTotals {
        cost_complete: !partial,
        tokens_complete: !partial,
        ..UsageTotals::default()
    };
    for entry in entries {
        totals.input_tokens = totals.input_tokens.saturating_add(entry.input);
        totals.output_tokens = totals.output_tokens.saturating_add(entry.output);
        totals.cached_input_tokens = totals.cached_input_tokens.saturating_add(entry.cached);
        totals.cache_write_input_tokens = totals
            .cache_write_input_tokens
            .saturating_add(entry.cache_write);
        totals.reasoning_tokens = totals.reasoning_tokens.saturating_add(entry.reasoning);
        totals.total_tokens = totals
            .total_tokens
            .saturating_add(entry.input.saturating_add(entry.output));
        totals.steps = totals.steps.saturating_add(1);
        totals.tokens_complete &= entry.output_complete;
        if let Some(cost) = entry.cost {
            totals.cost_usd = Some(totals.cost_usd.unwrap_or(0.0) + cost).filter(|n| n.is_finite());
            totals.cost_complete &= totals.cost_usd.is_some();
        } else {
            totals.cost_complete = false;
        }
    }
    if totals.steps == 0 {
        totals.cost_usd = Some(0.0);
    }
    totals
}

fn query_client_usage(kind: ClientKind, roots: &[(String, PathBuf)], days: u64, now: u64) -> Value {
    let from = now.saturating_sub(days.clamp(1, 90) * 86400);
    let mut records = BTreeMap::new();
    let mut partial = false;
    let mut files = Vec::new();
    for (account, root) in roots {
        files.clear();
        usage_files(root, &mut files, &mut partial);
        files.sort();
        for path in &files {
            read_usage_file(path, kind, account, &mut records, &mut partial);
        }
    }
    let any_records = !records.is_empty();
    let recorded_accounts: std::collections::BTreeSet<_> =
        records.values().map(|r| r.account.clone()).collect();
    records.retain(|_, r| r.time >= from && r.time <= now);
    let entries: Vec<_> = records.values().collect();
    let providers: std::collections::BTreeSet<_> = entries.iter().map(|r| &r.provider).collect();
    let accounts: std::collections::BTreeSet<_> =
        roots.iter().map(|(account, _)| account).collect();
    json!({"provider":kind.name(),"status":if any_records {"ok"} else if partial {"unavailable"} else {"empty"},
        "scope":"device","days":days.clamp(1,90),"updated":now,"partial":partial,"estimated":entries.iter().any(|r|r.estimated),
        "totals":aggregate_usage(entries.iter().copied(),partial),
        "providers":providers.iter().map(|provider|json!({"providerID":provider,"totals":aggregate_usage(entries.iter().copied().filter(|r|&r.provider==*provider),partial)})).collect::<Vec<_>>(),
        "accounts":accounts.iter().map(|account|json!({"id":account,"status":if recorded_accounts.contains(*account){"ok"}else{"empty"},"totals":aggregate_usage(entries.iter().copied().filter(|r|&r.account==*account),partial)})).collect::<Vec<_>>()})
}

/// Return local client usage for a rolling day range; never query inference or credentials.
pub(crate) fn collect_client_usage(days: u64, now: u64) -> Vec<Value> {
    let claude = std::env::var_os("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| super::home().join(".claude"));
    let mut homes = vec![claude];
    if let Some(paths) = std::env::var_os("AETHER_CLAUDE_HOMES") {
        homes.extend(std::env::split_paths(&paths));
    }
    homes.sort();
    homes.dedup();
    let roots: Vec<_> = homes
        .into_iter()
        .map(|home| (format!("claude:{}", home.display()), home.join("projects")))
        .collect();
    let pi = std::env::var_os("PI_CODING_AGENT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| super::home().join(".pi/agent"));
    vec![
        query_client_usage(ClientKind::Claude, &roots, days, now),
        query_client_usage(
            ClientKind::Pi,
            &[(format!("pi:{}", pi.display()), pi.join("sessions"))],
            days,
            now,
        ),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pi_includes_cache_without_counting_reasoning_twice() {
        let record: LocalRecord=serde_json::from_value(json!({"type":"message","id":"one","timestamp":2000000000000_u64,"message":{"role":"assistant","provider":"custom","responseId":"response-1","content":["private prompt"],"usage":{"input":10,"output":8,"reasoning":3,"cacheRead":20,"cacheWrite":2,"cost":{"total":0,"totalFromProvider":false}}}})).unwrap();
        let (_, entry) =
            parse_usage_entry(record, ClientKind::Pi, "pi:test", "session", "fallback").unwrap();
        let totals = serde_json::to_value(aggregate_usage(std::iter::once(&entry), false)).unwrap();
        assert_eq!(totals["inputTokens"], 32);
        assert_eq!(totals["totalTokens"], 40);
        assert_eq!(totals["reasoningTokens"], 3);
        assert_eq!(totals["costUsd"], 0.0);
        assert!(!totals.to_string().contains("private"));
    }

    #[test]
    fn claude_streaming_snapshots_count_once_and_unknown_cost_stays_unknown() {
        let root = std::env::temp_dir().join(format!("aether-client-usage-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let path = root.join("session.jsonl");
        let records=[1,9].map(|output|json!({"type":"assistant","timestamp":"2026-11-27T00:00:00Z","requestId":"request","message":{"id":"message","role":"assistant","content":"private","usage":{"input_tokens":10,"output_tokens":output,"cache_read_input_tokens":20,"cache_creation_input_tokens":2}}}).to_string()).join("\n");
        fs::write(&path, records).unwrap();
        let result = query_client_usage(
            ClientKind::Claude,
            &[("claude:test".into(), root.clone())],
            7,
            1795737600,
        );
        assert_eq!(result["totals"]["steps"], 1);
        assert_eq!(result["totals"]["totalTokens"], 32);
        assert_eq!(result["totals"]["tokensComplete"], false);
        assert!(result["totals"]["costUsd"].is_null());
        assert_eq!(result["totals"]["costComplete"], false);
        assert!(!result.to_string().contains("private"));
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn pi_replayed_responses_and_removed_providers_do_not_inflate_usage() {
        let root = std::env::temp_dir().join(format!("aether-pi-usage-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let make = |provider: &str, output: u64, time: u64| {
            json!({"type":"message","id":"entry","timestamp":time,"message":{"role":"assistant","provider":provider,"responseId":"same-response","usage":{"input":10,"output":output,"cost":{"total":0.5,"totalFromProvider":true}}}}).to_string()
        };
        fs::write(root.join("one.jsonl"), make("custom", 5, 2000000000)).unwrap();
        fs::write(
            root.join("two.jsonl"),
            [
                make("custom", 8, 2000000000),
                make("freegg", 99, 2000000000),
                make("agentrouter", 99, 2000000000),
                make("other", 99, 2001000000),
            ]
            .join("\n"),
        )
        .unwrap();
        let result = query_client_usage(
            ClientKind::Pi,
            &[("pi:test".into(), root.clone())],
            7,
            2000000010,
        );
        assert_eq!(result["totals"]["steps"], 1);
        assert_eq!(result["totals"]["totalTokens"], 18);
        assert_eq!(result["totals"]["costUsd"], 0.5);
        assert_eq!(result["totals"]["tokensComplete"], true);
        assert_eq!(result["providers"].as_array().unwrap().len(), 1);
        fs::remove_dir_all(root).unwrap();
    }
}
