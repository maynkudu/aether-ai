//! OpenCode's own Go allowance, Console budgets and enabled free-model catalogue.
use serde::Deserialize;
use serde_json::{json, Value};
use std::time::Duration;

fn timestamp(value: &Value, milliseconds: bool) -> Option<u64> {
    if let Some(text) = value.as_str() {
        return super::analytics::parse_timestamp(text);
    }
    value
        .as_u64()
        .map(|time| if milliseconds { time / 1000 } else { time })
}

pub(crate) fn go_windows(value: &Value, local: bool) -> Vec<Value> {
    let source = if local {
        value
    } else {
        value.get("usage").unwrap_or(&Value::Null)
    };
    [
        ("rolling", Some(300), "5-hour session"),
        ("weekly", Some(10080), "Weekly"),
        ("monthly", None, "Monthly"),
    ]
    .iter()
    .filter_map(|(key, minutes, label)| {
        let meter = source.get(key)?;
        let used = meter
            .get("percent")?
            .as_f64()
            .filter(|n| n.is_finite() && (0.0..=100.0).contains(n))?;
        let reset = timestamp(meter.get("resetsAt")?, local)?;
        let mut window =
            json!({"minutes":minutes,"remaining":100.0-used,"reset":reset,"label":label});
        if minutes.is_none() {
            window["period"] = json!("monthly");
        }
        Some(window)
    })
    .collect()
}

fn budget_windows(value: &Value) -> Vec<Value> {
    value.as_array().into_iter().flatten().take(32).filter_map(|budget| {
        let limit=budget.get("limit")?.as_f64().filter(|n|n.is_finite() && *n>=0.0)?;
        let spent=budget.get("spent")?.as_f64().filter(|n|n.is_finite() && *n>=0.0)?;
        let reset=timestamp(budget.get("resetsAt")?,true)?;
        let id=budget.get("id")?.as_str()?;
        let name=budget.get("models").and_then(Value::as_array).filter(|a|a.len()==1)
            .and_then(|a|a[0].get("name")).and_then(Value::as_str).unwrap_or("Monthly budget");
        let remaining = if limit == 0.0 { 0.0 } else { ((limit-spent)/limit*100.0).clamp(0.0,100.0) };
        Some(json!({"minutes":null,"period":format!("budget:{id}"),"label":name,"remaining":remaining,
            "reset":reset,"limitUsd":limit,"spentUsd":spent,"remainingUsd":(limit-spent).max(0.0),"shared":budget.get("shared").and_then(Value::as_bool).unwrap_or(false)}))
    }).collect()
}

fn console_account(value: &Value) -> Option<Value> {
    let workspace = value.get("workspace")?;
    let id = workspace.get("id")?.as_str()?;
    let name = workspace
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("Console workspace");
    let mut windows = value
        .get("go")
        .map(|v| go_windows(v, true))
        .unwrap_or_default();
    windows.extend(budget_windows(value.get("budgets").unwrap_or(&Value::Null)));
    Some(
        json!({"id":format!("opencode:local:workspace:{id}"),"name":name,"provider":"OpenCode","authKind":"console",
        "quotaScope":"workspace","status":if windows.is_empty(){"no_allowance"}else{"ok"},"windows":windows,"updated":super::now()}),
    )
}

fn free_account(value: &Value) -> Option<Value> {
    let entries = value.as_array()?;
    let mut models: Vec<Value> = entries
        .iter()
        .filter(|model| {
            matches!(
                model.get("providerID").and_then(Value::as_str),
                Some("opencode" | "opencode-go")
            ) && model.get("enabled").and_then(Value::as_bool) == Some(true)
                && model.get("status").and_then(Value::as_str) == Some("active")
                && model
                    .get("cost")
                    .and_then(Value::as_array)
                    .is_some_and(|tiers| {
                        !tiers.is_empty()
                            && tiers.iter().all(|tier| {
                                tier.get("input").and_then(Value::as_f64) == Some(0.0)
                                    && tier.get("output").and_then(Value::as_f64) == Some(0.0)
                            })
                    })
        })
        .filter_map(|model| {
            Some(json!({"id":model.get("id")?.as_str()?,"name":model.get("name")?.as_str()?,
                "providerID":model.get("providerID")?.as_str()?,"modelID":model.get("modelID").or_else(||model.get("id"))?.as_str()?}))
        })
        .collect();
    models.sort_by_key(|model| model["id"].as_str().unwrap_or_default().to_owned());
    models.dedup_by(|a, b| a["id"] == b["id"]);
    models.truncate(64);
    Some(
        json!({"id":"opencode:local:free","name":"Default free models","provider":"OpenCode","authKind":"free",
        "status":if models.is_empty(){"free_unavailable"}else{"free_available"},"windows":[],"freeModels":models,"quotaScope":"catalogue","updated":super::now()}),
    )
}

async fn command(operation: &str) -> Option<Value> {
    tokio::time::timeout(
        Duration::from_secs(18),
        super::providers::opencode_command(&["api", operation]),
    )
    .await
    .ok()
    .flatten()
}

#[derive(Deserialize)]
struct CacheTokens {
    read: u64,
    write: u64,
}

#[derive(Deserialize)]
struct Tokens {
    input: u64,
    output: u64,
    reasoning: u64,
    cache: CacheTokens,
}

impl Tokens {
    fn metrics(&self, steps: u64, cost: Option<f64>) -> Option<Value> {
        let input = self
            .input
            .checked_add(self.cache.read)?
            .checked_add(self.cache.write)?;
        let output = self.output.checked_add(self.reasoning)?;
        Some(
            json!({"inputTokens":input,"cachedInputTokens":self.cache.read,"cacheWriteInputTokens":self.cache.write,
            "outputTokens":output,"reasoningTokens":self.reasoning,"totalTokens":input.checked_add(output)?,
            "steps":steps,"costUsd":cost.filter(|n|n.is_finite() && *n>=0.0)}),
        )
    }
}

#[derive(Deserialize)]
struct ModelRef {
    id: String,
    #[serde(rename = "providerID")]
    provider: String,
}

#[derive(Deserialize)]
struct ModelUsage {
    model: ModelRef,
    steps: u64,
    tokens: Tokens,
    cost: Option<f64>,
}

#[derive(Deserialize)]
struct Statistics {
    steps: u64,
    tokens: Tokens,
    cost: Option<f64>,
    models: Vec<ModelUsage>,
}

fn normalize_statistics(value: Value, days: u64, from: u64, to: u64) -> Option<Value> {
    let data: Statistics =
        serde_json::from_value(value.get("data").unwrap_or(&value).clone()).ok()?;
    let totals = data.tokens.metrics(data.steps, data.cost)?;
    let mut grouped = std::collections::BTreeMap::<(String, String), Value>::new();
    for model in data.models {
        let metrics = model.tokens.metrics(model.steps, model.cost)?;
        let key = (model.model.provider, model.model.id);
        if let Some(previous) = grouped.get_mut(&key) {
            for field in [
                "inputTokens",
                "cachedInputTokens",
                "cacheWriteInputTokens",
                "outputTokens",
                "reasoningTokens",
                "totalTokens",
                "steps",
            ] {
                previous[field] = json!(previous[field]
                    .as_u64()?
                    .checked_add(metrics[field].as_u64()?)?);
            }
            previous["costUsd"] = previous["costUsd"]
                .as_f64()
                .zip(metrics["costUsd"].as_f64())
                .map(|(a, b)| json!(a + b))
                .unwrap_or(Value::Null);
        } else {
            grouped.insert(key, metrics);
        }
    }
    let truncated = grouped.len() > 256;
    let models: Vec<Value> = grouped
        .into_iter()
        .take(256)
        .map(|((provider, model), mut metrics)| {
            metrics["providerID"] = json!(provider);
            metrics["modelID"] = json!(model);
            metrics
        })
        .collect();
    Some(
        json!({"status":"ok","scope":"device","source":"opencode-local-statistics","days":days,
        "from":from,"to":to,"updated":super::now(),"totals":totals,"models":models,"modelsTruncated":truncated}),
    )
}

pub(crate) async fn statistics(days: u64) -> Value {
    if !super::providers::opencode_present() {
        return json!({"status":"not_detected"});
    }
    let days = days.clamp(1, 90);
    let to = super::now() * 1000;
    let from = to.saturating_sub(days * 86_400_000);
    let from_arg = format!("from={from}");
    let to_arg = format!("to={to}");
    let response = tokio::time::timeout(
        Duration::from_secs(18),
        super::providers::opencode_command(&[
            "api",
            "experimental.session.stats",
            "--param",
            &from_arg,
            "--param",
            &to_arg,
            "--param",
            "tools=none",
        ]),
    )
    .await
    .ok()
    .flatten();
    response
        .and_then(|value| normalize_statistics(value, days, from, to))
        .unwrap_or_else(|| json!({"status":"unavailable","days":days}))
}

fn attach_statistics(row: &mut Value, statistics: &Value, previous: &Value) {
    let Some(models) = row["freeModels"].as_array_mut() else {
        return;
    };
    if statistics["status"] != "ok" {
        row["activityStatus"] = json!(if previous.get("activity").is_some() {
            "stale"
        } else {
            "unavailable"
        });
        if let Some(old) = previous.get("activity") {
            row["activity"] = old.clone();
        }
        return;
    }
    let mut steps = 0_u64;
    let mut tokens = 0_u64;
    let mut cost = Some(0.0);
    for model in models {
        let Some(usage) = statistics["models"].as_array().and_then(|rows| {
            rows.iter().find(|r| {
                r["modelID"] == model["modelID"] && r["providerID"] == model["providerID"]
            })
        }) else {
            continue;
        };
        steps = steps.saturating_add(usage["steps"].as_u64().unwrap_or(0));
        tokens = tokens.saturating_add(usage["totalTokens"].as_u64().unwrap_or(0));
        cost = cost.zip(usage["costUsd"].as_f64()).map(|(a, b)| a + b);
        model["activity"] = usage.clone();
    }
    row["activityStatus"] = json!(if statistics["modelsTruncated"] == true {
        "partial"
    } else {
        "ok"
    });
    row["activity"] = json!({"days":7,"steps":steps,"totalTokens":tokens,"costUsd":cost,"updated":statistics["updated"]});
}

pub(crate) fn attach_observations(
    row: &mut Value,
    observations: &Option<super::opencode_local::Observations>,
) {
    let Some(observations) = observations else {
        row["observationsStatus"] = json!("unavailable");
        return;
    };
    if let Some(models) = row["freeModels"].as_array_mut() {
        for model in models {
            let key = (
                model["providerID"]
                    .as_str()
                    .unwrap_or("opencode")
                    .to_owned(),
                model["modelID"]
                    .as_str()
                    .or_else(|| model["id"].as_str())
                    .unwrap_or_default()
                    .to_owned(),
            );
            model["observation"] = observations
                .get(&key)
                .map(|o| serde_json::to_value(o).unwrap_or(Value::Null))
                .unwrap_or(Value::Null);
        }
    }
    row["observationsStatus"] = json!("ok");
}

pub(crate) async fn update_observations(cache: &mut Value) {
    let Some(accounts) = cache["accounts"].as_array_mut() else {
        return;
    };
    if !accounts.iter().any(|row| row["authKind"] == "free") {
        return;
    }
    let observations = super::opencode_local::observations().await;
    for row in accounts.iter_mut().filter(|row| row["authKind"] == "free") {
        attach_observations(row, &observations);
    }
}

fn stale(previous: &Value, prefix: &str) -> Vec<Value> {
    previous
        .get("accounts")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|row| {
            row.get("id")
                .and_then(Value::as_str)
                .is_some_and(|id| id.starts_with(prefix))
        })
        .map(|row| {
            let mut row = row.clone();
            row["status"] = json!("stale");
            row
        })
        .collect()
}

pub(crate) async fn local_accounts(previous: &Value) -> Vec<Value> {
    if !super::providers::opencode_present() {
        return vec![];
    }
    let (limits, catalogue, statistics, observations) = tokio::join!(
        command("experimental.usage.limits"),
        command("model.list"),
        statistics(7),
        super::opencode_local::observations()
    );
    let mut rows = match limits {
        Some(response) => console_account(response.get("data").unwrap_or(&response))
            .into_iter()
            .collect(),
        None => stale(previous, "opencode:local:workspace:"),
    };
    match catalogue {
        Some(response) => {
            if let Some(mut row) = free_account(response.get("data").unwrap_or(&response)) {
                let previous = previous["accounts"]
                    .as_array()
                    .and_then(|rows| rows.iter().find(|r| r["id"] == row["id"]))
                    .unwrap_or(&Value::Null);
                attach_statistics(&mut row, &statistics, previous);
                attach_observations(&mut row, &observations);
                rows.push(row);
            }
        }
        None => rows.extend(stale(previous, "opencode:local:free")),
    }
    rows
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn statistics_normalize_token_categories_and_combine_model_variants() {
        let tokens = json!({"input":10,"output":3,"reasoning":2,"cache":{"read":5,"write":2}});
        let model = json!({"model":{"id":"free-one","providerID":"opencode","variant":"high"},"steps":2,"tokens":tokens,"cost":0,"prompt":"private"});
        let stats = normalize_statistics(
            json!({"data":{"steps":4,"tokens":tokens,"cost":0,"models":[model.clone(),model]}}),
            7,
            1,
            2,
        )
        .unwrap();
        assert_eq!(stats["totals"]["totalTokens"], 22);
        assert_eq!(stats["models"].as_array().unwrap().len(), 1);
        assert_eq!(stats["models"][0]["totalTokens"], 44);
        assert_eq!(stats["models"][0]["inputTokens"], 34);
        assert_eq!(stats["models"][0]["outputTokens"], 10);
        assert_eq!(stats["models"][0]["reasoningTokens"], 4);
        assert_eq!(stats["models"][0]["costUsd"], 0.0);
        assert!(!stats.to_string().contains("private"));
        assert!(normalize_statistics(json!({"error":"unavailable"}), 7, 1, 2).is_none());
    }
    #[test]
    fn go_has_real_monthly_period_and_exact_resets() {
        let input = json!({"usage":{"rolling":{"percent":30,"resetsAt":"2026-11-27T01:00:00Z"},"weekly":{"percent":100,"resetsAt":"2026-11-30T00:00:00Z"},"monthly":{"percent":50,"resetsAt":"2026-12-01T00:00:00Z"}}});
        let windows = go_windows(&input, false);
        assert_eq!(windows.len(), 3);
        assert_eq!(windows[0]["remaining"], 70.0);
        assert_eq!(windows[1]["remaining"], 0.0);
        assert_eq!(windows[2]["period"], "monthly");
        assert!(windows[2]["minutes"].is_null());
        assert!(go_windows(
            &json!({"usage":{"monthly":{"percent":-10,"resetsAt":null}}}),
            false
        )
        .is_empty());
    }
    #[test]
    fn console_budgets_keep_money_and_shared_scope() {
        let row=console_account(&json!({"workspace":{"id":"w1","name":"Team"},"budgets":[{"id":"b1","limit":10,"spent":4,"resetsAt":1800000000000_u64,"shared":true,"models":[]}]})).unwrap();
        assert_eq!(row["windows"][0]["remaining"], 60.0);
        assert_eq!(row["windows"][0]["remainingUsd"], 6.0);
        assert_eq!(row["windows"][0]["reset"], 1800000000);
        assert_eq!(row["windows"][0]["shared"], true);
        assert!(console_account(&Value::Null).is_none());
    }
    #[test]
    fn free_catalogue_is_availability_and_never_a_quota_percentage() {
        let mut model = json!({"id":"free-one","name":"Free One","providerID":"opencode","enabled":true,"status":"active","cost":[{"input":0,"output":0}]});
        let free = free_account(&json!([model.clone(), model.clone()])).unwrap();
        assert_eq!(free["freeModels"].as_array().unwrap().len(), 1);
        assert_eq!(free["windows"], json!([]));
        model["cost"] = json!([{"input":0,"output":2}]);
        assert_eq!(
            free_account(&json!([model])).unwrap()["status"],
            "free_unavailable"
        );
        assert!(free_account(&Value::Null).is_none());
    }
}
