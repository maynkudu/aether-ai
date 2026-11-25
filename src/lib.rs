pub mod history;
use serde_json::{json, Value};
use std::{path::{Path,PathBuf}, collections::BTreeMap, time::{Duration,SystemTime,UNIX_EPOCH}};
use tokio::{io::{AsyncBufReadExt,AsyncWriteExt,BufReader},process::Command};
// Platform storage is deliberately independent of frontend configuration.
pub fn home()->PathBuf {
    if cfg!(windows) {
        std::env::var_os("USERPROFILE").or_else(||std::env::var_os("HOME")).map(PathBuf::from).unwrap_or_else(std::env::temp_dir)
    } else {
        std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(std::env::temp_dir)
    }
}
fn local_data()->PathBuf {
    std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(||home().join("AppData/Local"))
}
pub fn cache()->PathBuf {
    std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|| {
        if cfg!(windows) { local_data() }
        else if cfg!(target_os="macos") { home().join("Library/Caches") }
        else { home().join(".cache") }
    }).join("aether/usage.json")
}
pub fn state_dir()->PathBuf {
    std::env::var_os("XDG_STATE_HOME").map(PathBuf::from).unwrap_or_else(|| {
        if cfg!(windows) { local_data() }
        else if cfg!(target_os="macos") { home().join("Library/Application Support") }
        else { home().join(".local/state") }
    }).join("aether")
}
pub fn private_dir(path:&Path)->std::io::Result<()> {
    let mut builder=std::fs::DirBuilder::new();
    builder.recursive(true);
    #[cfg(unix)] { use std::os::unix::fs::DirBuilderExt; builder.mode(0o700); }
    builder.create(path)
}
pub fn private_options()->std::fs::OpenOptions {
    let mut opts=std::fs::OpenOptions::new();
    #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; opts.mode(0o600); }
    opts
}
// Native GUI launches (especially Finder) may have a minimal PATH.
pub fn codex_bin()->PathBuf {
    if let Some(p)=std::env::var_os("AETHER_CODEX_BIN") { return PathBuf::from(p); }
    let mut dirs:Vec<PathBuf>=std::env::var_os("PATH").map(|p|std::env::split_paths(&p).collect()).unwrap_or_default();
    if cfg!(windows) {
        if let Some(p)=std::env::var_os("APPDATA") { dirs.push(PathBuf::from(p).join("npm")); }
        dirs.push(local_data().join("Programs").join("nodejs"));
    } else {
        dirs.extend([home().join(".local/bin"),home().join(".cargo/bin"),PathBuf::from("/opt/homebrew/bin"),PathBuf::from("/usr/local/bin")]);
    }
    let names:&[&str]=if cfg!(windows) { &["codex.exe","codex.cmd"] } else { &["codex"] };
    for dir in dirs { for name in names { let p=dir.join(name); if p.is_file(){return p} } }
    PathBuf::from(if cfg!(windows){"codex.exe"}else{"codex"})
}
pub fn now()->u64 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() }
pub fn read(p:&Path)->Option<Value>{serde_json::from_slice(&std::fs::read(p).ok()?).ok()}
fn expand(s:&str)->PathBuf { if let Some(p)=s.strip_prefix("~/"){home().join(p)}else{PathBuf::from(s)} }
pub fn discover()->BTreeMap<PathBuf,String>{
 let mut out=BTreeMap::new(); let default=std::env::var_os("CODEX_HOME").map(PathBuf::from).unwrap_or_else(||home().join(".codex"));
 if default.join("auth.json").exists(){out.insert(default.clone(),"Default".into());}
 let config=std::env::var_os("AETHER_T3_SETTINGS").map(PathBuf::from);
 let mut candidates=vec![home().join(".t3/userdata/settings.json"),home().join(".t3code/userdata/settings.json"),home().join(".config/t3code/userdata/settings.json")];
 if cfg!(target_os="macos") { candidates.push(home().join("Library/Application Support/t3code/userdata/settings.json")); }
 if cfg!(windows) { if let Some(p)=std::env::var_os("APPDATA") { candidates.push(PathBuf::from(p).join("t3code/userdata/settings.json")); } }
 for p in config.into_iter().chain(candidates){if let Some(v)=read(&p){if let Some(inst)=v.get("providerInstances").and_then(Value::as_object){for (id,a) in inst {if a.get("enabled").and_then(Value::as_bool)==Some(false)||a.get("driver").and_then(Value::as_str)!=Some("codex"){continue} let c=a.get("config").unwrap_or(a); let path=["shadowHomePath","homePath"].iter().find_map(|k|c.get(k).or_else(||a.get(k)).and_then(Value::as_str).filter(|s|!s.is_empty())).map(expand).unwrap_or_else(||default.clone()); let label=a.get("displayName").or_else(||a.get("name")).and_then(Value::as_str).unwrap_or(id); out.insert(path,label.into());}}}}
 if let Ok(paths)=std::env::var("AETHER_CODEX_HOMES"){for p in std::env::split_paths(&paths){let name=p.file_name().unwrap_or_default().to_string_lossy().into_owned();out.insert(p,name);}}
 out.into_iter().map(|(p,n)|(p.canonicalize().unwrap_or(p),n)).collect()
}
async fn probe(path:PathBuf)->Result<Value,String>{
 let mut command=Command::new(codex_bin());
 command.arg("app-server").env("CODEX_HOME",path).stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::null()).kill_on_drop(true);
 #[cfg(windows)] command.creation_flags(0x08000000);
 let mut child=command.spawn().map_err(|_|"Cannot start Codex".to_string())?;
 let mut input=child.stdin.take().ok_or("No stdin")?; let mut lines=BufReader::new(child.stdout.take().ok_or("No stdout")?).lines();
 async fn send(w:&mut tokio::process::ChildStdin,v:Value)->Result<(),String>{w.write_all(format!("{}\n",v).as_bytes()).await.map_err(|_|"RPC write failed".into())}
 async fn recv(r:&mut tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,id:u64)->Result<Value,String>{while let Some(l)=r.next_line().await.map_err(|_|"RPC read failed")?{if let Ok(v)=serde_json::from_str::<Value>(&l){if v.get("id").and_then(Value::as_u64)==Some(id){return v.get("result").cloned().ok_or_else(||"RPC request rejected".into())}}}Err("Codex closed connection".into())}
 send(&mut input,json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"aether","version":env!("CARGO_PKG_VERSION")}}})).await?;recv(&mut lines,1).await?;
 send(&mut input,json!({"method":"initialized"})).await?;
 send(&mut input,json!({"id":2,"method":"account/rateLimits/read","params":{}})).await?;let result=recv(&mut lines,2).await?;let _=child.kill().await;Ok(result)
}
pub async fn refresh()->Value{let old=read(&cache()).unwrap_or(json!({}));let mut tasks=tokio::task::JoinSet::new();let sem=std::sync::Arc::new(tokio::sync::Semaphore::new(3));for (p,n) in discover(){let sem=sem.clone();tasks.spawn(async move{let _permit=sem.acquire().await.unwrap();let result=tokio::time::timeout(Duration::from_secs(20),probe(p.clone())).await; (p,n,result)});}let mut rows=vec![];while let Some(Ok((p,n,r)))=tasks.join_next().await{let id=p.to_string_lossy();let mut row=json!({"id":id,"name":n,"provider":"Codex","status":"unavailable","windows":[]});match r{Ok(Ok(v))=>{let mut windows=vec![];let limits=v.get("rateLimits").unwrap_or(&v);for key in ["primary","secondary"]{if let Some(w)=limits.get(key){if let Some(used)=w.get("usedPercent").and_then(Value::as_f64){windows.push(json!({"remaining":(100.0-used).clamp(0.0,100.0),"minutes":w.get("windowDurationMins"),"reset":w.get("resetsAt")}));}}}row["status"]=json!(if windows.is_empty(){"unavailable"}else{"ok"});row["windows"]=json!(windows);row["updated"]=json!(now());},_=>{if let Some(prev)=old.get("accounts").and_then(Value::as_array).and_then(|a|a.iter().find(|x|x.get("id")==row.get("id"))){row["windows"]=prev["windows"].clone();row["updated"]=prev["updated"].clone();row["status"]=json!("stale");}}}rows.push(row);}rows.sort_by_key(|v|v["id"].to_string());json!({"updated":now(),"accounts":rows})}
pub fn save(v:&Value)->std::io::Result<()> {
    use std::io::Write;
    let p=cache();
    private_dir(p.parent().unwrap())?;
    let tmp=p.with_extension(format!("{}.{}.tmp",std::process::id(),SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos()));
    let result=(|| {
        let mut f=private_options().write(true).create_new(true).open(&tmp)?;
        f.write_all(v.to_string().as_bytes())?;
        f.sync_all()?;
        drop(f);
        std::fs::rename(&tmp,&p)
    })();
    if result.is_err(){let _=std::fs::remove_file(&tmp);}
    result
}
pub fn usage()->Value {
    read(&cache()).unwrap_or(json!({"accounts":[],"updated":null}))
}
pub async fn refresh_and_record()->Value {
    let v=refresh().await;
    if let Err(e)=history::record(&v){eprintln!("History write: {e}")}
    if let Err(e)=save(&v){eprintln!("Cache write: {e}")}
    v
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn state_paths_are_absolute() {
        assert!(cache().is_absolute());
        assert!(state_dir().is_absolute());
        assert_eq!(cache().file_name().unwrap(),"usage.json");
    }
}
