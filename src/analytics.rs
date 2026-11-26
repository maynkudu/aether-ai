//! Read token-count events from local Codex session logs without retaining prompt content.
use serde::Deserialize;
use serde_json::{json, Value};
use std::{collections::BTreeMap, fs, io::{BufRead, BufReader}, path::{Path, PathBuf}};

#[derive(Default, Deserialize)]
struct SessionLine {
    timestamp: Option<String>,
    #[serde(rename = "type")]
    kind: Option<String>,
    payload: Option<Payload>,
}

#[derive(Default, Deserialize)]
struct Payload {
    #[serde(rename = "type")]
    kind: Option<String>,
    model: Option<String>,
    model_slug: Option<String>,
    info: Option<UsageInfo>,
}

#[derive(Default, Deserialize)]
struct UsageInfo {
    last_token_usage: Option<TokenUsage>,
}

#[derive(Default, Deserialize)]
#[serde(default)]
struct TokenUsage {
    input_tokens: u64,
    cached_input_tokens: u64,
    cache_write_input_tokens: u64,
    output_tokens: u64,
    reasoning_output_tokens: u64,
    total_tokens: u64,
}

#[derive(Default)]
struct Bucket {
    time: u64,
    id: String,
    name: String,
    auth_kind: String,
    input_tokens: u64,
    cached_input_tokens: u64,
    output_tokens: u64,
    reasoning_tokens: u64,
    total_tokens: u64,
    request_count: u64,
    estimated_cost_usd: Option<f64>,
}

fn model_rates(model: &str) -> Option<(f64, f64, f64)> {
    // Standard OpenAI API rates per million tokens. Keep estimates opt-in by
    // model name so unknown models never produce a misleading dollar figure.
    match model {
        "gpt-6.2-sol" | "gpt-6.1-sol" | "gpt-6-sol" => Some((2.0, 0.10, 10.0)),
        "gpt-6-astra" => Some((10.0, 1.0, 50.0)),
        "gpt-6.1-terra" => Some((1.0, 0.05, 5.0)),
        "gpt-6-luna" => Some((0.10, 0.01, 0.50)),
        "gpt-5.6-sol" => Some((4.0, 0.40, 20.0)),
        "gpt-5.3-codex" | "gpt-5.2-codex" => Some((1.75, 0.175, 14.0)),
        "gpt-5-codex" => Some((1.25, 0.125, 10.0)),
        _ => None,
    }
}

fn estimate_cost(model: &str, usage: &TokenUsage) -> Option<f64> {
    if usage.cache_write_input_tokens > 0 {
        return None;
    }
    let (input_rate, cached_rate, output_rate) = model_rates(model)?;
    let uncached = usage.input_tokens.saturating_sub(usage.cached_input_tokens);
    let cached = usage.cached_input_tokens.min(usage.input_tokens);
    Some((uncached as f64 * input_rate + cached as f64 * cached_rate + usage.output_tokens as f64 * output_rate) / 1_000_000.0)
}

fn parse_timestamp(value: &str) -> Option<u64> {
    let (date, time) = value.split_once('T')?;
    let mut date_parts = date.split('-');
    let year = date_parts.next()?.parse::<i64>().ok()?;
    let month = date_parts.next()?.parse::<i64>().ok()?;
    let day = date_parts.next()?.parse::<i64>().ok()?;
    if date_parts.next().is_some() || !(1..=12).contains(&month) || !(1..=31).contains(&day) { return None; }

    let clock_end = time.find(|c| matches!(c, 'Z' | '+' | '-')).unwrap_or(time.len());
    let clock = &time[..clock_end];
    let mut time_parts = clock.split(':');
    let hour = time_parts.next()?.parse::<i64>().ok()?;
    let minute = time_parts.next()?.parse::<i64>().ok()?;
    let second_text = time_parts.next()?.split('.').next()?;
    if time_parts.next().is_some() || !(0..=23).contains(&hour) || !(0..=59).contains(&minute) { return None; }
    let zone_at = (clock_end < time.len()).then_some(clock_end);
    let second = second_text.parse::<i64>().ok()?;
    if !(0..=59).contains(&second) { return None; }
    let offset = if let Some(i) = zone_at {
        let zone = &time[i..];
        if zone == "Z" { 0 } else {
            let sign = if zone.starts_with('-') { -1 } else { 1 };
            let mut parts = zone[1..].split(':');
            let hours = parts.next()?.parse::<i64>().ok()?;
            let minutes = parts.next()?.parse::<i64>().ok()?;
            if parts.next().is_some() || hours > 23 || minutes > 59 { return None; }
            sign * (hours * 3600 + minutes * 60)
        }
    } else { 0 };

    let adjusted_year = year - i64::from(month <= 2);
    let era = if adjusted_year >= 0 { adjusted_year } else { adjusted_year - 399 } / 400;
    let year_of_era = adjusted_year - era * 400;
    let adjusted_month = month + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * adjusted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146097 + day_of_era - 719468;
    u64::try_from(days * 86400 + hour * 3600 + minute * 60 + second - offset).ok()
}

fn collect_files(directory: &Path, files: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else { return; };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else { continue; };
        if kind.is_dir() {
            collect_files(&path, files);
        } else if kind.is_file() && path.extension().and_then(|s| s.to_str()) == Some("jsonl") {
            files.push(path);
        }
    }
}

fn record_line(line: &str, current_model: &mut String) -> Option<(u64, TokenUsage)> {
    let parsed: SessionLine = serde_json::from_str(line).ok()?;
    let payload = parsed.payload?;
    if parsed.kind.as_deref() == Some("turn_context") || payload.kind.as_deref() == Some("turn_context") {
        if let Some(model) = payload.model.or(payload.model_slug) { *current_model = model; }
        return None;
    }
    if payload.kind.as_deref() != Some("token_count") { return None; }
    let time = parse_timestamp(parsed.timestamp.as_deref()?)?;
    let usage = payload.info?.last_token_usage?;
    if usage.input_tokens + usage.output_tokens == 0 && usage.total_tokens == 0 { return None; }
    Some((time, usage))
}

fn add_usage(bucket: &mut Bucket, usage: &TokenUsage, model: &str) {
    bucket.input_tokens += usage.input_tokens;
    bucket.cached_input_tokens += usage.cached_input_tokens.min(usage.input_tokens);
    bucket.output_tokens += usage.output_tokens;
    bucket.reasoning_tokens += usage.reasoning_output_tokens.min(usage.output_tokens);
    bucket.total_tokens += if usage.total_tokens > 0 { usage.total_tokens } else { usage.input_tokens + usage.output_tokens };
    bucket.request_count += 1;
    bucket.estimated_cost_usd = match (bucket.estimated_cost_usd, estimate_cost(model, usage)) {
        (Some(current), Some(cost)) => Some(current + cost),
        _ => None,
    };
}

pub fn query(days: u64) -> Value {
    let now = super::now();
    let homes: Vec<_> = super::discover().into_iter().map(|(path, name)| {
        let auth_kind = super::auth_kind(&path).to_owned();
        (path, name, auth_kind)
    }).collect();
    query_homes(&homes, days, now)
}

fn query_homes(homes: &[(PathBuf, String, String)], days: u64, now: u64) -> Value {
    let start = now.saturating_sub(days.clamp(1, 90) * 86400);
    // Match the chart's scale to the selected window: hourly for 24h and daily
    // for longer ranges, so a busy hour or day doesn't dominate the line.
    let step = if days <= 1 { 3600 } else { 86400 };
    let mut buckets: BTreeMap<(u64, String), Bucket> = BTreeMap::new();
    for (home, account_name, auth_kind) in homes {
        let mut files = Vec::new();
        collect_files(&home.join("sessions"), &mut files);
        for path in files {
            // Session filenames are immutable after a run; metadata avoids opening old logs.
            if let Ok(modified) = fs::metadata(&path).and_then(|m| m.modified()) {
                if let Ok(age) = modified.duration_since(std::time::UNIX_EPOCH) {
                    if age.as_secs() < start { continue; }
                }
            }
            let file_id = path.file_name().and_then(|s| s.to_str()).unwrap_or("session").to_owned();
            let account_id = home.to_string_lossy().into_owned();
            let id = format!("{account_id}:{file_id}");
            let Ok(file) = fs::File::open(path) else { continue; };
            let mut model = String::new();
            for line in BufReader::new(file).lines().map_while(Result::ok) {
                let Some((time, usage)) = record_line(&line, &mut model) else { continue; };
                if time < start || time > now { continue; }
                let bucket_time = time / step * step;
                let bucket = buckets.entry((bucket_time, id.clone())).or_insert_with(|| Bucket {
                    time: bucket_time,
                    id: account_id.clone(),
                    name: account_name.clone(),
                    auth_kind: auth_kind.clone(),
                    estimated_cost_usd: Some(0.0),
                    ..Bucket::default()
                });
                add_usage(bucket, &usage, &model);
            }
        }
    }
    let samples: Vec<Value> = buckets.into_values().map(|b| json!({
        "time": b.time, "id": b.id, "name": b.name, "provider": "Codex", "authKind": b.auth_kind,
        "inputTokens": b.input_tokens, "cachedInputTokens": b.cached_input_tokens,
        "outputTokens": b.output_tokens, "reasoningTokens": b.reasoning_tokens,
        "totalTokens": b.total_tokens, "requestCount": b.request_count,
        "estimatedCostUsd": b.estimated_cost_usd
    })).collect();
    json!({"source":"codex-session-logs","days":days.clamp(1, 90),"samples":samples})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_utc_and_offset_timestamps() {
        assert_eq!(parse_timestamp("2026-11-26T09:01:20.178Z"), Some(1_795_683_680));
        assert_eq!(parse_timestamp("2026-11-26T14:31:20+05:30"), Some(1_795_683_680));
    }

    #[test]
    fn reads_only_token_usage_fields_and_prices_known_models() {
        let line = r#"{"timestamp":"2026-11-26T09:01:20Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":50,"total_tokens":1200}},"prompt":"private text"}}"#;
        let mut model = "gpt-5.3-codex".to_owned();
        let (time, usage) = record_line(line, &mut model).unwrap();
        assert_eq!(time, 1_795_683_680);
        assert_eq!(usage.input_tokens, 1000);
        assert_eq!(usage.cached_input_tokens, 800);
        assert_eq!(usage.output_tokens, 200);
        assert!((estimate_cost(&model, &usage).unwrap() - 0.003_29).abs() < 1e-12);
        assert!(estimate_cost("unpriced-model", &usage).is_none());
        assert_eq!(model_rates("gpt-6.1-sol"), Some((2.0, 0.10, 10.0)));
    }

    #[test]
    fn accumulates_cost_only_when_every_event_is_priced() {
        let mut bucket = Bucket { estimated_cost_usd: Some(0.0), ..Bucket::default() };
        let usage = TokenUsage { input_tokens: 1000, cached_input_tokens: 0, output_tokens: 200, ..TokenUsage::default() };
        add_usage(&mut bucket, &usage, "gpt-5.3-codex");
        assert_eq!(bucket.request_count, 1);
        assert!(bucket.estimated_cost_usd.unwrap() > 0.0);
        add_usage(&mut bucket, &usage, "unpriced-model");
        assert!(bucket.estimated_cost_usd.is_none());
    }

    #[test]
    fn daily_view_combines_activity_and_24_hour_view_uses_hourly_buckets() {
        let home = std::env::temp_dir().join(format!("aether-analytics-{}", super::super::now()));
        let sessions = home.join("sessions/2026/11/26");
        fs::create_dir_all(&sessions).unwrap();
        let path = sessions.join("rollout.jsonl");
        let context = r#"{"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#;
        let first = r#"{"timestamp":"2026-11-24T09:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}}"#;
        let second = r#"{"timestamp":"2026-11-24T09:45:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"output_tokens":20,"total_tokens":220}}}}"#;
        let third = r#"{"timestamp":"2026-11-25T10:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"output_tokens":30,"total_tokens":330}}}}"#;
        fs::write(&path, format!("{context}\n{first}\n{second}\n{third}\n")).unwrap();
        let homes = [(home.clone(), "Fixture".to_owned(), "chatgpt".to_owned())];
        let now = parse_timestamp("2026-11-26T09:01:20Z").unwrap();
        assert!(record_line(context, &mut String::new()).is_none());
        assert!(record_line(first, &mut "gpt-6.1-sol".to_owned()).is_some());

        let daily = query_homes(&homes, 30, now)["samples"].as_array().unwrap().clone();
        assert_eq!(daily.len(), 2);
        assert_eq!(daily[0]["requestCount"], 2);
        assert_eq!(daily[0]["totalTokens"], 330);
        assert!(daily[0]["estimatedCostUsd"].as_f64().unwrap() > 0.0);

        let hourly = query_homes(&homes, 1, now)["samples"].as_array().unwrap().clone();
        assert_eq!(hourly.len(), 1);
        assert_eq!(hourly[0]["requestCount"], 1);
        assert_eq!(hourly[0]["totalTokens"], 330);
        fs::remove_dir_all(home).unwrap();
    }
}
