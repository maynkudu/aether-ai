use aether_core::{analytics,history,refresh_and_record,usage};
use std::time::Duration;
#[tokio::main]
async fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("daemon") => loop { refresh_and_record().await; tokio::time::sleep(Duration::from_secs(180)).await; },
        Some("refresh") => println!("{}",refresh_and_record().await),
        Some("history") => {
            let days=std::env::args().nth(2).and_then(|s|s.parse::<u64>().ok()).unwrap_or(7).clamp(1,90);
            println!("{}",history::query(days));
        },
        Some("analytics") => {
            let days=std::env::args().nth(2).and_then(|s|s.parse::<u64>().ok()).unwrap_or(7).clamp(1,90);
            println!("{}",analytics::query(days).await);
        },
        Some("--version")|Some("version") => println!("{}",env!("CARGO_PKG_VERSION")),
        Some("accounts") => for account in aether_core::providers::accounts().await { println!("{} · {}\t{}",account["provider"].as_str().unwrap_or_default(),account["name"].as_str().unwrap_or_default(),account["id"].as_str().unwrap_or_default()); },
        Some("usage")|Some("status") => println!("{}",usage().await),
        _ => eprintln!("aether [daemon|refresh|accounts|usage|status|history|analytics|version]")
    }
}
