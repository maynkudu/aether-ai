//! Discover client credentials locally; persist only account metadata and quota readings.
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use reqwest::{header, Client, StatusCode};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    process::Stdio,
    time::Duration,
};
use tokio::{io::AsyncReadExt, process::Command};

const MAX_CREDENTIAL_BYTES: u64 = 2 * 1024 * 1024;
const MAX_RESPONSE_BYTES: usize = 256 * 1024;

// No Debug/Serialize: tokens must never reach logs, cache, history or CLI output.
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum QuotaSource {
    Codex(PathBuf),
    Anthropic { access: String },
    ChatGpt { access: String, account_id: String },
    OpenCodeGo { key: String },
    ApiKey,
    Unsupported,
    LoginRequired,
}

struct Account {
    id: String,
    name: String,
    client: &'static str,
    auth_kind: &'static str,
    usage_provider: String,
    source: QuotaSource,
}

impl Account {
    fn summary(&self) -> Value {
        json!({"id":self.id,"name":self.name,"provider":self.client,"authKind":self.auth_kind,
            "status":"unavailable","windows":[],"quotaScope":"account","usageProvider":self.usage_provider})
    }
}

fn directory(variable: &str, fallback: PathBuf) -> PathBuf {
    std::env::var_os(variable)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or(fallback)
}

fn credential_json(path: &Path) -> Option<Value> {
    let file = std::fs::File::open(path).ok()?;
    if file.metadata().ok()?.len() > MAX_CREDENTIAL_BYTES {
        return None;
    }
    serde_json::from_reader(std::io::Read::take(file, MAX_CREDENTIAL_BYTES + 1)).ok()
}

fn nonempty(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)?
        .as_str()
        .filter(|s| !s.trim().is_empty())
        .map(str::to_owned)
}

/// Keep removed providers out of account discovery and local usage totals.
pub(crate) fn removed_provider(provider: &str) -> bool {
    let name: String = provider
        .chars()
        .filter(char::is_ascii_alphanumeric)
        .flat_map(char::to_lowercase)
        .collect();
    name.starts_with("agentrouter") || name.starts_with("freegg")
}

fn jwt_account_id(access: &str) -> Option<String> {
    // Decode identity metadata only. The provider still authenticates the token.
    let payload = URL_SAFE_NO_PAD.decode(access.split('.').nth(1)?).ok()?;
    let claims: Value = serde_json::from_slice(&payload).ok()?;
    nonempty(
        claims.get("https://api.openai.com/auth")?,
        "chatgpt_account_id",
    )
}

fn oauth_source(provider: &str, credential: &Value, now: u64) -> QuotaSource {
    let Some(access) =
        nonempty(credential, "access").or_else(|| nonempty(credential, "accessToken"))
    else {
        return QuotaSource::LoginRequired;
    };
    if credential
        .get("expires")
        .or_else(|| credential.get("expiresAt"))
        .and_then(Value::as_u64)
        .is_some_and(|expiry| expiry <= now.saturating_mul(1000))
    {
        return QuotaSource::LoginRequired;
    }
    match provider {
        "anthropic" | "claude" => QuotaSource::Anthropic { access },
        "openai" | "openai-codex" => {
            let id = nonempty(credential, "accountId")
                .or_else(|| {
                    credential
                        .get("metadata")
                        .and_then(|m| nonempty(m, "accountId"))
                })
                .or_else(|| jwt_account_id(&access));
            match id {
                Some(account_id) => QuotaSource::ChatGpt { access, account_id },
                None => QuotaSource::LoginRequired,
            }
        }
        _ => QuotaSource::Unsupported,
    }
}

fn client_account(
    client: &'static str,
    id: String,
    name: String,
    provider: &str,
    credential: &Value,
) -> Option<Account> {
    if removed_provider(provider) {
        return None;
    }
    let kind = credential.get("type").and_then(Value::as_str)?;
    let (auth_kind, source) = match kind {
        "api_key" | "api" | "key" => {
            let source = if matches!(provider, "opencode-go" | "opencode" | "opencode-zen") {
                nonempty(credential, "key")
                    .filter(|k| {
                        !k.starts_with('!') && !k.starts_with("{env:") && !k.starts_with("${")
                    })
                    .map(|key| QuotaSource::OpenCodeGo { key })
                    .unwrap_or(QuotaSource::ApiKey)
            } else {
                QuotaSource::ApiKey
            };
            ("api_key", source)
        }
        "oauth" => ("oauth", oauth_source(provider, credential, super::now())),
        "external" => ("external", QuotaSource::Unsupported),
        _ => return None,
    };
    Some(Account {
        id,
        name,
        client,
        auth_kind,
        usage_provider: provider.into(),
        source,
    })
}

fn read_pi(directory: &Path, rows: &mut Vec<Account>) {
    let path = directory.join("auth.json");
    let Some(credentials) = credential_json(&path) else {
        return;
    };
    let Some(entries) = credentials.as_object() else {
        return;
    };
    for (provider, credential) in entries {
        if let Some(row) = client_account(
            "Pi",
            format!("pi:{}#{provider}", directory.display()),
            provider.clone(),
            provider,
            credential,
        ) {
            rows.push(row);
        }
    }
}

fn read_claude(directory: &Path, label: &str, rows: &mut Vec<Account>) {
    let credentials = credential_json(&directory.join(".credentials.json"));
    let id = format!("claude:{}", directory.display());
    if let Some(oauth) = credentials.as_ref().and_then(|v| v.get("claudeAiOauth")) {
        rows.push(Account {
            id,
            name: label.into(),
            client: "Claude Code",
            auth_kind: "oauth",
            usage_provider: "anthropic".into(),
            source: oauth_source("anthropic", oauth, super::now()),
        });
    } else {
        let settings = credential_json(&directory.join("settings.json"));
        let env = settings.as_ref().and_then(|v| v.get("env"));
        if env.is_some_and(|v| {
            ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
                .iter()
                .any(|key| nonempty(v, key).is_some())
        }) {
            rows.push(Account {
                id,
                name: label.into(),
                client: "Claude Code",
                auth_kind: "api_key",
                usage_provider: "anthropic".into(),
                source: QuotaSource::ApiKey,
            });
        }
    }
}

fn read_opencode(credentials: &Value, namespace: &Path, rows: &mut Vec<Account>) {
    if let Some(entries) = credentials.as_array() {
        // OpenCode v2 credential export includes every saved account, not just the active one.
        for entry in entries {
            let (Some(id), Some(provider), Some(value)) = (
                nonempty(entry, "id"),
                nonempty(entry, "integrationID"),
                entry.get("value"),
            ) else {
                continue;
            };
            let label = nonempty(entry, "label").unwrap_or_else(|| provider.clone());
            if removed_provider(&label) {
                continue;
            }
            if let Some(row) = client_account(
                "OpenCode",
                format!("opencode:{}#{id}", namespace.display()),
                format!("{provider} · {label}"),
                &provider,
                value,
            ) {
                rows.push(row);
            }
        }
    } else if let Some(entries) = credentials.as_object() {
        // OpenCode v1 auth.json uses provider IDs as keys.
        for (provider, value) in entries {
            if let Some(row) = client_account(
                "OpenCode",
                format!("opencode:{}#{provider}", namespace.display()),
                provider.clone(),
                provider,
                value,
            ) {
                rows.push(row);
            }
        }
    }
}

fn opencode_bin() -> PathBuf {
    if let Some(path) = std::env::var_os("AETHER_OPENCODE_BIN") {
        return path.into();
    }
    let name = if cfg!(windows) {
        "opencode.exe"
    } else {
        "opencode"
    };
    let dirs = std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).collect::<Vec<_>>())
        .unwrap_or_default();
    dirs.into_iter()
        .chain([
            super::home().join(".opencode/bin"),
            super::home().join(".local/bin"),
        ])
        .map(|dir| dir.join(name))
        .find(|p| p.is_file())
        .unwrap_or_else(|| name.into())
}

pub(crate) async fn opencode_command(arguments: &[&str]) -> Option<Value> {
    let mut command = Command::new(opencode_bin());
    command
        .args(arguments)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    let mut child = command.spawn().ok()?;
    let mut bytes = Vec::new();
    child
        .stdout
        .take()?
        .take(MAX_CREDENTIAL_BYTES + 1)
        .read_to_end(&mut bytes)
        .await
        .ok()?;
    if bytes.len() as u64 > MAX_CREDENTIAL_BYTES {
        return None;
    }
    if !child.wait().await.ok()?.success() {
        return None;
    }
    serde_json::from_slice(&bytes).ok()
}

async fn opencode_credentials() -> Option<Value> {
    opencode_command(&["auth", "export"]).await
}

pub(crate) fn opencode_present() -> bool {
    let data = directory("XDG_DATA_HOME", super::home().join(".local/share")).join("opencode");
    data.join("opencode.db").is_file()
        || data.join("auth.json").is_file()
        || std::env::var_os("AETHER_OPENCODE_BIN").is_some()
}

async fn discover() -> Vec<Account> {
    let mut rows = Vec::new();
    for (path, name) in super::discover() {
        let auth_kind = super::auth_kind(&path);
        let source = if auth_kind == "api_key" {
            QuotaSource::ApiKey
        } else {
            QuotaSource::Codex(path.clone())
        };
        rows.push(Account {
            id: path.to_string_lossy().into_owned(),
            name,
            client: "Codex",
            auth_kind,
            usage_provider: "openai-codex".into(),
            source,
        });
    }
    let claude_dir = directory("CLAUDE_CONFIG_DIR", super::home().join(".claude"));
    read_claude(&claude_dir, "Default", &mut rows);
    if let Ok(paths) = std::env::var("AETHER_CLAUDE_HOMES") {
        for path in std::env::split_paths(&paths).filter(|p| p != &claude_dir) {
            let label = path.file_name().unwrap_or_default().to_string_lossy();
            read_claude(&path, &label, &mut rows);
        }
    }
    read_pi(
        &directory("PI_CODING_AGENT_DIR", super::home().join(".pi/agent")),
        &mut rows,
    );
    let data = directory("XDG_DATA_HOME", super::home().join(".local/share")).join("opencode");
    let explicit = std::env::var_os("AETHER_OPENCODE_AUTH").map(PathBuf::from);
    let credentials = if let Some(path) = &explicit {
        credential_json(path)
    } else if data.join("opencode.db").is_file()
        || data.join("auth.json").is_file()
        || std::env::var_os("AETHER_OPENCODE_BIN").is_some()
    {
        tokio::time::timeout(Duration::from_secs(8), opencode_credentials())
            .await
            .ok()
            .flatten()
            .or_else(|| credential_json(&data.join("auth.json")))
    } else {
        None
    };
    if let Some(credentials) = credentials {
        read_opencode(
            &credentials,
            explicit.as_deref().unwrap_or(&data),
            &mut rows,
        );
    }
    rows.sort_by(|a, b| a.id.cmp(&b.id));
    rows.dedup_by(|a, b| a.id == b.id);
    rows
}

pub async fn accounts() -> Vec<Value> {
    discover().await.iter().map(Account::summary).collect()
}

fn window(used: &Value, minutes: u64, reset: Option<u64>) -> Option<Value> {
    let percent = used.as_f64().filter(|p| p.is_finite())?;
    Some(json!({"minutes":minutes,"remaining":(100.0-percent).clamp(0.0,100.0),"reset":reset}))
}

fn codex_windows(value: &Value) -> Vec<Value> {
    let limits = value.get("rateLimits").unwrap_or(value);
    ["primary", "secondary"]
        .iter()
        .filter_map(|key| {
            let w = limits.get(key)?;
            window(
                w.get("usedPercent")?,
                w.get("windowDurationMins")?.as_u64()?,
                w.get("resetsAt").and_then(Value::as_u64),
            )
        })
        .collect()
}

fn anthropic_windows(value: &Value) -> Vec<Value> {
    [("five_hour", 300), ("seven_day", 10080)]
        .iter()
        .filter_map(|(key, minutes)| {
            let w = value.get(key)?;
            let reset = w
                .get("resets_at")
                .and_then(Value::as_str)
                .and_then(super::analytics::parse_timestamp);
            window(w.get("utilization")?, *minutes, reset)
        })
        .collect()
}

fn chatgpt_windows(value: &Value) -> Vec<Value> {
    let Some(limits) = value.get("rate_limit") else {
        return vec![];
    };
    ["primary_window", "secondary_window"]
        .iter()
        .filter_map(|key| {
            let w = limits.get(key)?;
            let seconds = w.get("limit_window_seconds")?.as_u64()?;
            if seconds == 0 || seconds % 60 != 0 {
                return None;
            }
            window(
                w.get("used_percent")?,
                seconds / 60,
                w.get("reset_at").and_then(Value::as_u64),
            )
        })
        .collect()
}

#[derive(Clone, Debug)]
enum ProbeError {
    Unavailable,
    LoginRequired,
    RateLimited(u64),
    Forbidden,
}

async fn http_usage(
    client: &Client,
    url: &str,
    access: &str,
    account_id: Option<&str>,
    anthropic: bool,
) -> Result<Value, ProbeError> {
    let mut token = header::HeaderValue::from_str(&format!("Bearer {access}"))
        .map_err(|_| ProbeError::Unavailable)?;
    token.set_sensitive(true);
    let mut request = client
        .get(url)
        .header(header::AUTHORIZATION, token)
        .header(header::ACCEPT, "application/json");
    if anthropic {
        request = request.header("anthropic-beta", "oauth-2025-04-20");
    }
    if let Some(id) = account_id {
        request = request.header("chatgpt-account-id", id);
    }
    let mut response = request.send().await.map_err(|_| ProbeError::Unavailable)?;
    if response.status() == StatusCode::UNAUTHORIZED {
        return Err(ProbeError::LoginRequired);
    }
    if response.status() == StatusCode::FORBIDDEN {
        return Err(ProbeError::Forbidden);
    }
    if response.status() == StatusCode::TOO_MANY_REQUESTS {
        let delay = response
            .headers()
            .get(header::RETRY_AFTER)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(300)
            .clamp(180, 86400);
        return Err(ProbeError::RateLimited(super::now().saturating_add(delay)));
    }
    if !response.status().is_success() {
        return Err(ProbeError::Unavailable);
    }
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| ProbeError::Unavailable)?
    {
        if bytes.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err(ProbeError::Unavailable);
        }
        bytes.extend_from_slice(&chunk);
    }
    serde_json::from_slice(&bytes).map_err(|_| ProbeError::Unavailable)
}

async fn probe(source: &QuotaSource, client: &Client) -> Result<Vec<Value>, ProbeError> {
    match source {
        QuotaSource::Codex(path) => super::probe(path.clone())
            .await
            .map(|v| codex_windows(&v))
            .map_err(|_| ProbeError::Unavailable),
        QuotaSource::Anthropic { access } => http_usage(
            client,
            "https://api.anthropic.com/api/oauth/usage",
            access,
            None,
            true,
        )
        .await
        .map(|v| anthropic_windows(&v)),
        QuotaSource::ChatGpt { access, account_id } => http_usage(
            client,
            "https://chatgpt.com/backend-api/wham/usage",
            access,
            Some(account_id),
            false,
        )
        .await
        .map(|v| chatgpt_windows(&v)),
        QuotaSource::OpenCodeGo { key } => http_usage(
            client,
            "https://opencode.ai/inference/go/v1/usage",
            key,
            None,
            false,
        )
        .await
        .map(|v| super::opencode::go_windows(&v, false)),
        _ => Ok(vec![]),
    }
}

fn apply_reading(account: &Account, reading: Result<Vec<Value>, ProbeError>, old: &Value) -> Value {
    let mut row = account.summary();
    let status = match &account.source {
        QuotaSource::ApiKey => "api_key",
        QuotaSource::Unsupported => "unsupported",
        QuotaSource::LoginRequired => "login_required",
        _ => match reading {
            Ok(windows) if !windows.is_empty() => {
                row["windows"] = json!(windows);
                "ok"
            }
            Ok(_) => "unavailable",
            Err(ProbeError::LoginRequired) => "login_required",
            Err(ProbeError::Forbidden) => {
                if matches!(account.source, QuotaSource::OpenCodeGo { .. }) {
                    "no_allowance"
                } else {
                    "forbidden"
                }
            }
            Err(error) => {
                if let ProbeError::RateLimited(retry_at) = error {
                    row["retryAfter"] = json!(retry_at);
                }
                if let Some(prev) = old
                    .get("accounts")
                    .and_then(Value::as_array)
                    .and_then(|a| a.iter().find(|a| a.get("id") == Some(&row["id"])))
                    .filter(|a| {
                        a.get("windows")
                            .and_then(Value::as_array)
                            .is_some_and(|w| !w.is_empty())
                    })
                {
                    row["windows"] = prev["windows"].clone();
                    row["updated"] = prev["updated"].clone();
                    "stale"
                } else if row.get("retryAfter").is_some() {
                    "rate_limited"
                } else {
                    "unavailable"
                }
            }
        },
    };
    row["status"] = json!(status);
    if status != "stale" {
        row["updated"] = json!(super::now());
    }
    row
}

pub async fn refresh() -> Value {
    let old = super::read(&super::cache()).unwrap_or(json!({}));
    let mut groups: BTreeMap<QuotaSource, Vec<Account>> = BTreeMap::new();
    for account in discover().await {
        groups
            .entry(account.source.clone())
            .or_default()
            .push(account);
    }
    let client = match Client::builder()
        .timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .user_agent("aether-ai/0.2.0")
        .build()
    {
        Ok(client) => client,
        Err(_) => {
            return json!({"updated":super::now(),"accounts":groups.values().flatten().map(|a|apply_reading(a,Err(ProbeError::Unavailable),&old)).collect::<Vec<_>>()})
        }
    };
    let mut tasks = tokio::task::JoinSet::new();
    let semaphore = std::sync::Arc::new(tokio::sync::Semaphore::new(3));
    for (source, accounts) in groups {
        let client = client.clone();
        let semaphore = semaphore.clone();
        let retry_at = old
            .get("accounts")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|r| {
                accounts
                    .iter()
                    .any(|a| r.get("id").and_then(Value::as_str) == Some(&a.id))
            })
            .filter_map(|r| r.get("retryAfter").and_then(Value::as_u64))
            .max()
            .unwrap_or(0);
        tasks.spawn(async move {
            let _permit = semaphore.acquire().await.unwrap();
            let result = if retry_at > super::now() {
                Err(ProbeError::RateLimited(retry_at))
            } else {
                tokio::time::timeout(Duration::from_secs(20), probe(&source, &client))
                    .await
                    .unwrap_or(Err(ProbeError::Unavailable))
            };
            (accounts, result)
        });
    }
    let mut rows = Vec::new();
    while let Some(result) = tasks.join_next().await {
        if let Ok((accounts, result)) = result {
            rows.extend(
                accounts
                    .iter()
                    .map(|a| apply_reading(a, result.clone(), &old)),
            );
        }
    }
    rows.sort_by_key(|row| row["id"].as_str().unwrap_or_default().to_owned());
    rows.extend(super::opencode::local_accounts(&old).await);
    json!({"updated":super::now(),"accounts":rows})
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };

    #[test]
    fn client_credentials_are_not_quota_readings_or_serialized_secrets() {
        let credential = json!({"type":"oauth","access":"private-access","refresh":"private-refresh","accountId":"account-1"});
        let account = client_account(
            "Pi",
            "id".into(),
            "OpenAI".into(),
            "openai-codex",
            &credential,
        )
        .unwrap();
        assert!(matches!(account.source, QuotaSource::ChatGpt { .. }));
        let text = account.summary().to_string();
        assert!(!text.contains("private-"));
        assert_eq!(account.summary()["windows"], json!([]));
        for provider in [
            "AgentRouter",
            "agentrouter-openai",
            "agentrouter-clode",
            "free.gg",
        ] {
            assert!(
                client_account("Pi", "id".into(), "label".into(), provider, &credential).is_none()
            );
        }
        let key = client_account(
            "Pi",
            "id".into(),
            "Custom".into(),
            "custom",
            &json!({"type":"api_key","key":"!never execute this"}),
        )
        .unwrap();
        assert!(matches!(key.source, QuotaSource::ApiKey));
        let unsupported =
            client_account("Pi", "id".into(), "Other".into(), "other", &credential).unwrap();
        assert!(matches!(unsupported.source, QuotaSource::Unsupported));
    }

    #[test]
    fn expired_oauth_requires_the_client_to_sign_in_without_refreshing_its_files() {
        let expired = json!({"access":"secret","expires":1000});
        assert!(matches!(
            oauth_source("anthropic", &expired, 2),
            QuotaSource::LoginRequired
        ));
        let missing = json!({"type":"oauth","refresh":"secret"});
        assert!(matches!(
            oauth_source("anthropic", &missing, 2),
            QuotaSource::LoginRequired
        ));
        let claims = URL_SAFE_NO_PAD
            .encode(br#"{"https://api.openai.com/auth":{"chatgpt_account_id":"account-2"}}"#);
        let credential = json!({"access":format!("header.{claims}.signature"),"expires":5000});
        assert!(
            matches!(oauth_source("openai",&credential,2),QuotaSource::ChatGpt { account_id,.. } if account_id=="account-2")
        );
    }

    #[test]
    fn opencode_supports_v1_and_multiple_v2_accounts() {
        let mut rows = Vec::new();
        read_opencode(
            &json!({"openai":{"type":"oauth","access":"secret","accountId":"account-1"},"agentrouter":{"type":"api","key":"secret"}}),
            Path::new("/test"),
            &mut rows,
        );
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].client, "OpenCode");
        assert!(matches!(rows[0].source, QuotaSource::ChatGpt { .. }));
        rows.clear();
        read_opencode(
            &json!([
                {"id":"one","integrationID":"openai","label":"Work","active":true,"value":{"type":"oauth","access":"secret","metadata":{"accountId":"one"}}},
                {"id":"two","integrationID":"openai","label":"Personal","active":false,"value":{"type":"oauth","access":"secret","metadata":{"accountId":"two"}}},
                {"id":"three","integrationID":"custom","label":"API","active":true,"value":{"type":"key","key":"secret"}},
                {"id":"four","integrationID":"freegg","value":{"type":"key","key":"secret"}}
            ]),
            Path::new("/test"),
            &mut rows,
        );
        assert_eq!(rows.len(), 3);
        assert_ne!(rows[0].id, rows[1].id);
        assert!(rows[0].name.contains("Work"));
        assert!(rows[1].name.contains("Personal"));
        assert!(matches!(rows[2].source, QuotaSource::ApiKey));
        assert!(rows
            .iter()
            .all(|a| !a.summary().to_string().contains("secret")));
    }

    #[test]
    fn quota_windows_preserve_zero_and_never_invent_a_missing_week() {
        let rows = anthropic_windows(
            &json!({"five_hour":{"utilization":100,"resets_at":"2026-11-26T09:01:20Z"},"seven_day":{"utilization":0,"resets_at":null}}),
        );
        assert_eq!(rows[0]["remaining"], 0.0);
        assert_eq!(rows[0]["reset"], 1_795_683_680_u64);
        assert_eq!(rows[1]["remaining"], 100.0);
        let partial =
            anthropic_windows(&json!({"five_hour":{"utilization":14.5},"seven_day":null}));
        assert_eq!(partial.len(), 1);
        assert_eq!(partial[0]["remaining"], 85.5);
        assert!(anthropic_windows(&json!({"five_hour":{"utilization":"unknown"}})).is_empty());
        let chatgpt = chatgpt_windows(
            &json!({"rate_limit":{"primary_window":{"used_percent":16,"limit_window_seconds":18000,"reset_at":2000000000},"secondary_window":{"used_percent":74,"limit_window_seconds":604800}}}),
        );
        assert_eq!(
            chatgpt
                .iter()
                .map(|w| w["minutes"].as_u64().unwrap())
                .collect::<Vec<_>>(),
            vec![300, 10080]
        );
        assert_eq!(chatgpt[0]["remaining"], 84.0);
        assert_eq!(chatgpt[1]["remaining"], 26.0);
        assert!(chatgpt_windows(&json!({"rate_limit":null})).is_empty());
    }

    #[test]
    fn network_failure_keeps_readings_stale_but_login_and_api_key_do_not() {
        let mut account = Account {
            id: "id".into(),
            name: "Test".into(),
            client: "Claude Code",
            auth_kind: "oauth",
            usage_provider: "anthropic".into(),
            source: QuotaSource::Anthropic {
                access: "secret".into(),
            },
        };
        let old = json!({"accounts":[{"id":"id","windows":[{"minutes":300,"remaining":12}],"updated":123}]});
        let stale = apply_reading(&account, Err(ProbeError::RateLimited(2000000000)), &old);
        assert_eq!(stale["status"], "stale");
        assert_eq!(stale["updated"], 123);
        assert_eq!(stale["retryAfter"], 2000000000);
        assert_eq!(stale["windows"][0]["remaining"], 12);
        let login = apply_reading(&account, Err(ProbeError::LoginRequired), &old);
        assert_eq!(login["status"], "login_required");
        assert_eq!(login["windows"], json!([]));
        account.source = QuotaSource::ApiKey;
        let key = apply_reading(&account, Ok(vec![]), &old);
        assert_eq!(key["status"], "api_key");
        assert_eq!(key["windows"], json!([]));
        account.source = QuotaSource::OpenCodeGo {
            key: "private-test-key".into(),
        };
        let no_plan = apply_reading(&account, Err(ProbeError::Forbidden), &old);
        assert_eq!(no_plan["status"], "no_allowance");
        assert!(!no_plan.to_string().contains("private-test-key"));
    }

    async fn server(response: String) -> (String, tokio::task::JoinHandle<String>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let task = tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut request = Vec::new();
            let mut buffer = [0u8; 1024];
            while !request.windows(4).any(|s| s == b"\r\n\r\n") {
                let count = socket.read(&mut buffer).await.unwrap();
                if count == 0 {
                    break;
                }
                request.extend_from_slice(&buffer[..count]);
            }
            let _ = socket.write_all(response.as_bytes()).await;
            String::from_utf8(request).unwrap().to_lowercase()
        });
        (format!("http://{address}/usage"), task)
    }

    fn test_client() -> Client {
        Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .no_proxy()
            .timeout(Duration::from_secs(2))
            .build()
            .unwrap()
    }

    #[tokio::test]
    async fn real_http_request_uses_headers_and_parses_quota_json() {
        let body = r#"{"five_hour":{"utilization":20}}"#;
        let (url,request) = server(format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len())).await;
        let result = http_usage(
            &test_client(),
            &url,
            "test-secret",
            Some("test-account"),
            true,
        )
        .await;
        assert!(result.is_ok());
        assert_eq!(anthropic_windows(&result.unwrap())[0]["remaining"], 80.0);
        let headers = request.await.unwrap();
        assert!(headers.starts_with("get /usage http/1.1"));
        assert!(headers.contains("authorization: bearer test-secret"));
        assert!(headers.contains("chatgpt-account-id: test-account"));
        assert!(headers.contains("anthropic-beta: oauth-2025-04-20"));
    }

    #[tokio::test]
    async fn http_auth_rate_limit_redirect_and_response_size_fail_closed() {
        let responses = [
            ("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".into(), "forbidden"),
            ("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n".into(),"login"),
            ("HTTP/1.1 429 Too Many Requests\r\nRetry-After: 1800\r\nContent-Length: 0\r\n\r\n".into(),"rate"),
            ("HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/steal\r\nContent-Length: 0\r\n\r\n".into(),"redirect"),
            (format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}",MAX_RESPONSE_BYTES+1,"x".repeat(MAX_RESPONSE_BYTES+1)),"size"),
        ];
        for (response, case) in responses {
            let (url, task) = server(response).await;
            let result = http_usage(&test_client(), &url, "fake-secret", None, false).await;
            match case {
                "forbidden" => assert!(matches!(result, Err(ProbeError::Forbidden))),
                "login" => assert!(matches!(result, Err(ProbeError::LoginRequired))),
                "rate" => assert!(
                    matches!(result,Err(ProbeError::RateLimited(t)) if t>=super::super::now()+1700)
                ),
                _ => assert!(matches!(result, Err(ProbeError::Unavailable))),
            }
            task.await.unwrap();
        }
    }
}
