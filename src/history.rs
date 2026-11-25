//! Append daily quota snapshots. Never reads or stores prompts, keys, or tokens.
use serde_json::{json, Value};
use std::{fs,io::{self,BufRead,BufReader,Write},os::unix::fs::{DirBuilderExt,OpenOptionsExt},path::PathBuf};
fn directory()->PathBuf { std::env::var_os("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(||super::home().join(".local/state")).join("aether/history") }
pub fn record(cache:&Value)->io::Result<()>{
    let dir=directory();
    fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    let time=super::now();
    let day=time/86400;
    let mut file=fs::OpenOptions::new().create(true).append(true).mode(0o600).open(dir.join(format!("{day}.jsonl")))?;
    let mut samples=Vec::new();
    if let Some(accounts)=cache["accounts"].as_array(){
        for a in accounts {
            if a["status"].as_str()!=Some("ok"){continue}
            if let Some(windows)=a["windows"].as_array(){
                for w in windows {
                    if let (Some(minutes),Some(remaining))=(w["minutes"].as_u64(),w["remaining"].as_f64()){
                        samples.push(json!({"time":time,"id":a["id"],"name":a["name"],"provider":a["provider"],"minutes":minutes,"remaining":remaining.clamp(0.0,100.0)}));
                    }
                }
            }
        }
    }
    // One append per snapshot, even when multiple accounts are present.
    if !samples.is_empty(){let mut line=serde_json::to_vec(&samples).map_err(io::Error::other)?;line.push(b'\n');file.write_all(&line)?;}
    for entry in fs::read_dir(&dir)?.flatten(){
        let p=entry.path();
        if p.extension().and_then(|x|x.to_str())==Some("jsonl"){
            if let Some(d)=p.file_stem().and_then(|x|x.to_str()).and_then(|x|x.parse::<u64>().ok()){
                if d+92<day {let _=fs::remove_file(p);}
            }
        }
    }
    Ok(())
}
pub fn query(days:u64)->Value{
    let now=super::now();let start=now.saturating_sub(days*86400);
    // Bound the UI payload to at most one sample per 15-minute bucket for
    // each account/window. For 30/90-day ranges, use hourly buckets.
    let step=if days<=7{900}else{3600};
    let mut samples=std::collections::BTreeMap::new();
    for day in start/86400..=now/86400 {
        if let Ok(file)=fs::File::open(directory().join(format!("{day}.jsonl"))){
            for line in BufReader::new(file).lines().map_while(Result::ok){
                if let Ok(batch)=serde_json::from_str::<Vec<Value>>(&line){
                    for p in batch {
                        let t=p["time"].as_u64().unwrap_or(0);
                        if t<start||t>now{continue}
                        let Some(id)=p["id"].as_str()else{continue};
                        let Some(window)=p["minutes"].as_u64()else{continue};
                        let key=(t/step,id.to_owned(),window);
                        if samples.get(&key).and_then(|v:&Value|v["time"].as_u64()).unwrap_or(0)<=t {samples.insert(key,p);}
                    }
                }
            }
        }
    }
    json!({"source":"local-quota-snapshots","samples":samples.into_values().collect::<Vec<_>>()})
}
