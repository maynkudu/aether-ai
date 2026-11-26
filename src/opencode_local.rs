//! Read only OpenCode's model and failure metadata. Prompts and credentials stay in its database.
use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use std::{
    collections::BTreeMap,
    path::PathBuf,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const MAX_RETRY_MS: u64 = 45 * 86_400_000;

#[derive(Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Observation {
    pub last_success_at: Option<u64>,
    pub limit_observed_at: Option<u64>,
    pub retry_at: Option<u64>,
}

pub(crate) type Observations = BTreeMap<(String, String), Observation>;

fn database_path() -> PathBuf {
    std::env::var_os("AETHER_OPENCODE_DB")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::var_os("XDG_DATA_HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| super::home().join(".local/share"))
                .join("opencode/opencode.db")
        })
}

fn open(path: PathBuf) -> rusqlite::Result<Connection> {
    let db = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    db.busy_timeout(Duration::from_millis(250))?;
    db.pragma_update(None, "query_only", true)?;
    Ok(db)
}

// CASE keeps malformed optional JSON from invalidating otherwise usable rows.
const SELECT_OBSERVATIONS: &str = "
WITH messages AS (
    SELECT CASE WHEN json_valid(data) THEN data ELSE '{}' END AS data, time_updated
    FROM session_message WHERE type = 'assistant'
)
SELECT json_extract(data, '$.model.providerID'),
       json_extract(data, '$.model.id'),
       CASE WHEN json_type(data, '$.time.completed') = 'integer'
            THEN json_extract(data, '$.time.completed') END,
       json_extract(data, '$.error.type'),
       CASE WHEN json_type(data, '$.error.retryAfterMs') = 'integer'
            THEN json_extract(data, '$.error.retryAfterMs') END,
       json_type(data, '$.error') IS NULL OR json_type(data, '$.error') = 'null'
FROM messages
WHERE json_extract(data, '$.model.providerID') IN ('opencode', 'opencode-go')
  AND json_type(data, '$.model.id') = 'text'
  AND (json_type(data, '$.error.type') IS NULL OR json_type(data, '$.error.type') = 'text')
  AND json_type(data, '$.time.completed') = 'integer'
ORDER BY time_updated DESC
LIMIT 8192
";

fn read(db: &Connection, now_ms: u64) -> rusqlite::Result<Observations> {
    let mut statement = db.prepare(SELECT_OBSERVATIONS)?;
    let mut rows = statement.query([])?;
    let mut result = Observations::new();
    while let Some(row) = rows.next()? {
        let (provider, model): (String, String) = (row.get(0)?, row.get(1)?);
        if model.is_empty() || model.len() > 256 {
            continue;
        }
        let Some(completed) = row
            .get::<_, Option<i64>>(2)?
            .and_then(|n| u64::try_from(n).ok())
        else {
            continue;
        };
        if completed > now_ms || now_ms - completed > MAX_RETRY_MS {
            continue;
        }
        let error: Option<String> = row.get(3)?;
        let succeeded: bool = row.get(5)?;
        if !succeeded && error.as_deref() != Some("provider.free-limit") {
            continue;
        }
        let observation = result.entry((provider, model)).or_default();
        if succeeded {
            observation.last_success_at =
                Some(observation.last_success_at.unwrap_or(0).max(completed));
        } else if observation
            .limit_observed_at
            .is_none_or(|old| completed > old)
        {
            observation.limit_observed_at = Some(completed);
            observation.retry_at = row
                .get::<_, Option<i64>>(4)?
                .and_then(|n| u64::try_from(n).ok())
                .filter(|delay| *delay <= MAX_RETRY_MS)
                .and_then(|delay| completed.checked_add(delay));
        }
    }
    Ok(result)
}

pub(crate) async fn observations() -> Option<Observations> {
    tokio::task::spawn_blocking(|| {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?;
        let now_ms = u64::try_from(now.as_millis()).ok()?;
        read(&open(database_path()).ok()?, now_ms).ok()
    })
    .await
    .ok()
    .flatten()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn projects_metadata_and_keeps_failure_clock_and_later_success() {
        let db = Connection::open_in_memory().unwrap();
        db.execute_batch(
            "CREATE TABLE session_message(type TEXT, data TEXT, time_updated INTEGER)",
        )
        .unwrap();
        for (model, completed, error) in [
            (
                "a",
                1000,
                json!({"type":"provider.free-limit","retryAfterMs":4000,"response":{"body":"private-body"}}),
            ),
            ("a", 2000, serde_json::Value::Null),
            (
                "b",
                3000,
                json!({"type":"provider.free-limit","retryAfterMs":true}),
            ),
            (
                "c",
                4000,
                json!({"type":"provider.free-limit","retryAfterMs":-1}),
            ),
            ("d", 5000, json!({"type":"provider.auth"})),
            (
                "future",
                10000,
                json!({"type":"provider.free-limit","retryAfterMs":1}),
            ),
        ] {
            let data = json!({"model":{"providerID":"opencode","id":model},"time":{"created":1,"completed":completed},"content":["private-prompt"],"error":error});
            db.execute(
                "INSERT INTO session_message VALUES ('assistant',?1,?2)",
                (data.to_string(), completed),
            )
            .unwrap();
        }
        db.execute(
            "INSERT INTO session_message VALUES ('assistant','broken json',9000)",
            [],
        )
        .unwrap();
        let rows = read(&db, 6000).unwrap();
        let first = &rows[&("opencode".into(), "a".into())];
        assert_eq!(first.limit_observed_at, Some(1000));
        assert_eq!(first.retry_at, Some(5000));
        assert_eq!(first.last_success_at, Some(2000));
        assert!(rows[&("opencode".into(), "b".into())].retry_at.is_none());
        assert!(rows[&("opencode".into(), "c".into())].retry_at.is_none());
        assert_eq!(rows.len(), 3);
        assert!(!serde_json::to_string(first).unwrap().contains("private"));
    }

    #[test]
    fn missing_database_is_never_created() {
        let path =
            std::env::temp_dir().join(format!("aether-missing-opencode-{}.db", std::process::id()));
        assert!(!path.exists());
        assert!(open(path.clone()).is_err());
        assert!(!path.exists());
    }
}
