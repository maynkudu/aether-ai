use aether_core::{analytics,discover,history,refresh_and_record,usage};
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
            println!("{}",analytics::query(days));
        },
        Some("--version")|Some("version") => println!("{}",env!("CARGO_PKG_VERSION")),
        Some("accounts") => for(p,n)in discover(){println!("{n}\t{}",p.display());},
        Some("usage")|Some("status") => println!("{}",usage()),
        _ => eprintln!("aether [daemon|refresh|accounts|usage|status|history|analytics|version]")
    }
}
