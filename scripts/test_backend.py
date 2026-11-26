#!/usr/bin/env python3
"""Credential-free integration tests for local client discovery and quota history."""
import json, os, pathlib, sqlite3, subprocess, sys, tempfile, time, unittest
BIN = pathlib.Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else pathlib.Path("target/release/aether").resolve()

class Backend(unittest.TestCase):
    def test_opencode_allowances_budgets_free_catalogue_and_stale_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)
            home=p/"home"
            home.mkdir()
            fake=p/("opencode.exe" if os.name=="nt" else "opencode")
            source=p/"fake-opencode.rs"
            source.write_text(r'''
fn main(){
    let args=std::env::args().skip(1).collect::<Vec<_>>();
    if args==["auth","export"] { println!("[]"); return; }
    if args.len()<2 || args[0]!="api" { std::process::exit(1); }
    let name=match args[1].as_str(){"experimental.usage.limits"=>"limits", "model.list"=>"models", "experimental.session.stats"=>"stats", _=>std::process::exit(1)};
    let folder=std::env::var("AETHER_TEST_RESPONSES").unwrap();
    let response=std::fs::read_to_string(format!("{folder}/{name}.json")).unwrap();
    if response=="unavailable" { std::process::exit(1); }
    println!("{response}");
}
''')
            subprocess.run(["rustc",str(source),"-o",str(fake)],check=True,timeout=90)
            env=dict(os.environ,HOME=str(home),USERPROFILE=str(home),CODEX_HOME=str(p/"codex"),CLAUDE_CONFIG_DIR=str(p/"claude"),PI_CODING_AGENT_DIR=str(p/"pi"),XDG_CACHE_HOME=str(p/"cache"),XDG_STATE_HOME=str(p/"state"),XDG_DATA_HOME=str(p/"data"),APPDATA=str(p/"appdata"),LOCALAPPDATA=str(p/"local"),AETHER_OPENCODE_BIN=str(fake),AETHER_TEST_RESPONSES=str(p))
            for key in ["AETHER_T3_SETTINGS","AETHER_CODEX_HOMES","AETHER_CLAUDE_HOMES","AETHER_OPENCODE_AUTH","AETHER_OPENCODE_DB","OPENAI_API_KEY","CODEX_API_KEY"]:
                env.pop(key,None)
            def cli(*args):
                result=subprocess.run([str(BIN),*args],env=env,capture_output=True,text=True,timeout=35,check=True)
                self.assertNotIn("secret",result.stdout+result.stderr)
                return json.loads(result.stdout)
            limits={"workspace":{"id":"test-workspace","name":"Team"},"go":{period:{"percent":percent,"resetsAt":2000000000000} for period,percent in [("rolling",25),("weekly",40),("monthly",60)]},"budgets":[{"id":"team","limit":10,"spent":4,"resetsAt":2000000000000,"shared":True,"models":[]},{"id":"disabled","limit":0,"spent":0,"resetsAt":2000000000000,"models":[{"name":"Blocked model"}]}]}
            def write(name,data): (p/(name+".json")).write_text(json.dumps({"data":data}))
            free={"id":"free-one","name":"Free One","providerID":"opencode","enabled":True,"status":"active","cost":[{"input":0,"output":0}],"secret":"must-not-leak"}
            write("limits",limits)
            write("models",[free,free,dict(free,id="paid",cost=[{"input":0,"output":2}]),dict(free,id="disabled",enabled=False),dict(free,id="other",providerID="custom")])
            tokens={"input":10,"output":3,"reasoning":2,"cache":{"read":5,"write":2}}
            model={"model":{"id":"free-one","providerID":"opencode","variant":"high"},"steps":2,"tokens":tokens,"cost":0}
            write("stats",{"steps":6,"tokens":tokens,"cost":0.25,"models":[model,dict(model,model=dict(model["model"],variant="low")),dict(model,model={"id":"paid","providerID":"openai"},cost=0.25)]})
            db_path=p/"data/opencode/opencode.db"
            db_path.parent.mkdir(parents=True)
            completed=int(time.time()*1000)-5000
            with sqlite3.connect(db_path) as db:
                db.execute("CREATE TABLE session_message(type TEXT, data TEXT, time_updated INTEGER)")
                def insert(completed,error):
                    message={"model":{"providerID":"opencode","id":"free-one"},"time":{"created":1,"completed":completed},"error":error,"content":["secret prompt"]}
                    db.execute("INSERT INTO session_message VALUES ('assistant',?,?)",(json.dumps(message),completed))
                insert(completed,{"type":"provider.free-limit","retryAfterMs":3600000,"response":{"body":"secret response"}})
            before_db=db_path.read_bytes()
            data=cli("refresh")
            self.assertEqual(db_path.read_bytes(),before_db,"Quota discovery must not write to OpenCode's database")
            self.assertEqual(len(data["accounts"]),2)
            workspace,catalogue=data["accounts"]
            self.assertEqual(workspace["status"],"ok")
            self.assertEqual([w["remaining"] for w in workspace["windows"]],[75.0,60.0,40.0,60.0,0.0])
            self.assertEqual(workspace["windows"][2]["period"],"monthly")
            self.assertEqual(workspace["windows"][3]["remainingUsd"],6.0)
            self.assertTrue(workspace["windows"][3]["shared"])
            self.assertEqual(len(catalogue["freeModels"]),1)
            free_model=catalogue["freeModels"][0]
            self.assertEqual((free_model["id"],free_model["name"],free_model["providerID"],free_model["modelID"]),("free-one","Free One","opencode","free-one"))
            self.assertEqual(free_model["observation"],{"limitObservedAt":completed,"retryAt":completed+3600000,"lastSuccessAt":None})
            self.assertEqual((catalogue["activity"]["steps"],catalogue["activity"]["totalTokens"],catalogue["activity"]["costUsd"]),(4,44,0))
            self.assertEqual(catalogue["activityStatus"],"ok")
            self.assertEqual(catalogue["windows"],[])
            analytics=cli("analytics","7")
            self.assertEqual(analytics["samples"],[])
            stats=analytics["openCode"]
            self.assertEqual((stats["status"],stats["scope"],stats["days"]),("ok","device",7))
            self.assertEqual(stats["to"]-stats["from"],7*86400000)
            self.assertEqual((stats["totals"]["totalTokens"],stats["totals"]["costUsd"]),(22,0.25))
            self.assertEqual(len(stats["models"]),2,"Variants of the same model must be combined")
            self.assertEqual(next(m for m in stats["models"] if m["providerID"]=="opencode")["inputTokens"],34)
            with sqlite3.connect(db_path) as db:
                insert(completed+1000,None)
            env["AETHER_OPENCODE_BIN"]=str(p/"does-not-exist")
            fresh=cli("usage")
            self.assertEqual(fresh["updated"],data["updated"],"Reading local observations must not pretend provider quotas were refreshed")
            self.assertEqual(fresh["accounts"][1]["freeModels"][0]["observation"]["lastSuccessAt"],completed+1000)
            env["AETHER_OPENCODE_BIN"]=str(fake)
            (p/"stats.json").write_text("unavailable")
            cached=cli("refresh")["accounts"][1]
            self.assertEqual(cached["activity"],catalogue["activity"])
            self.assertEqual(cached["activityStatus"],"stale")
            samples=cli("history","1")["samples"]
            self.assertEqual(len(samples),5)
            self.assertEqual({s["period"] for s in samples if s["minutes"] is None},{"monthly","budget:team","budget:disabled"})
            for name in ["limits","models"]: (p/(name+".json")).write_text("unavailable")
            stale=cli("refresh")["accounts"]
            self.assertTrue(all(row["status"]=="stale" for row in stale))
            self.assertEqual(stale[0]["windows"],workspace["windows"])
            self.assertEqual(stale[1]["freeModels"],cached["freeModels"])
            self.assertEqual(len(cli("history","1")["samples"]),5)
            write("limits",None)
            write("models",[])
            signed_out=cli("refresh")["accounts"]
            self.assertEqual(len(signed_out),1)
            self.assertEqual(signed_out[0]["status"],"free_unavailable")
            self.assertEqual(signed_out[0]["windows"],[])

    def test_quota_history_and_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)
            home, bins, account = p/"home", p/"bin", p/"fake-account"
            for folder in (home,bins,account):
                folder.mkdir()
            fake=bins/("codex.exe" if os.name=="nt" else "codex")
            fixture=p/"fake.rs"
            fixture.write_text(r'''
use std::io::{self,BufRead,Write};
fn main(){
    for line in io::stdin().lock().lines().map_while(Result::ok) {
        if line.contains("\"method\":\"initialize\"") && line.contains("\"id\":1") {
            println!("{}",r#"{"id":1,"result":{}}"#);
        } else if line.contains("\"method\":\"account/rateLimits/read\"") && line.contains("\"id\":2") {
            println!("{}",r#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":2000000000}}}}"#);
        }
        io::stdout().flush().unwrap();
    }
}
''',encoding="utf-8")
            subprocess.run(["rustc",str(fixture),"-o",str(fake)],check=True,timeout=90)
            env=dict(os.environ,HOME=str(home),XDG_CACHE_HOME=str(p/"cache"),XDG_STATE_HOME=str(p/"state"),AETHER_CODEX_HOMES=str(account),PATH=str(bins)+os.pathsep+os.environ["PATH"])
            env.update(USERPROFILE=str(home),APPDATA=str(p/"appdata"),LOCALAPPDATA=str(p/"local"),AETHER_CODEX_BIN=str(fake),CODEX_HOME=str(home/".codex"))
            for key in ["AETHER_T3_SETTINGS","AETHER_CLAUDE_HOMES","AETHER_OPENCODE_BIN","AETHER_OPENCODE_AUTH","AETHER_OPENCODE_DB","OPENAI_API_KEY","CODEX_API_KEY"]:
                env.pop(key,None)
            env.update(XDG_DATA_HOME=str(p/"data"),CLAUDE_CONFIG_DIR=str(home/".claude"),PI_CODING_AGENT_DIR=str(home/".pi/agent"))
            def cli(*args):
                return subprocess.check_output([str(BIN),*args],env=env,text=True,timeout=35)
            self.assertIn("fake-account",cli("accounts"))
            data=json.loads(cli("refresh"))
            row=data["accounts"][0]
            self.assertEqual(row["status"],"ok")
            self.assertEqual([w["remaining"] for w in row["windows"]],[82.0,64.0])
            self.assertEqual(json.loads(cli("usage")),data)
            samples=json.loads(cli("history","1"))["samples"]
            self.assertEqual(sorted(s["minutes"] for s in samples),[300,10080])
            if os.name!="nt":
                self.assertEqual((p/"cache/aether/usage.json").stat().st_mode & 0o777,0o600)
            # An explicitly missing executable reproduces provider unavailability.
            env["AETHER_CODEX_BIN"]=str(bins/"does-not-exist")
            stale=json.loads(cli("refresh"))["accounts"][0]
            self.assertEqual(stale["status"],"stale")
            self.assertEqual(stale["windows"],row["windows"])
            self.assertEqual(json.loads(cli("usage"))["accounts"][0]["status"],"stale")

    def test_claude_pi_and_opencode_v1_v2_without_secret_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)
            home,claude,pi=p/"home",p/"claude",p/"pi"
            for folder in [home,claude,pi]: folder.mkdir()
            credential=claude/".credentials.json"
            credential.write_text(json.dumps({"claudeAiOauth":{"accessToken":"fake-claude-secret","refreshToken":"fake-refresh-secret","expiresAt":1}}))
            (pi/"auth.json").write_text(json.dumps({
                "openai-codex":{"type":"oauth","access":"fake-pi-secret","accountId":"test-account","expires":1},
                "custom":{"type":"api_key","key":"!do-not-execute-fake-secret"},
                "agentrouter-openai":{"type":"api_key","key":"fake-removed-secret"},
                "freegg":{"type":"api_key","key":"fake-removed-secret"}
            }))
            legacy=p/"opencode-auth-fixture.json"
            legacy.write_text(json.dumps({"openai":{"type":"api","key":"fake-opencode-secret"}}))
            env=dict(os.environ,HOME=str(home),USERPROFILE=str(home),CODEX_HOME=str(p/"codex"),CLAUDE_CONFIG_DIR=str(claude),PI_CODING_AGENT_DIR=str(pi),XDG_CACHE_HOME=str(p/"cache"),XDG_STATE_HOME=str(p/"state"),XDG_DATA_HOME=str(p/"data"),APPDATA=str(p/"appdata"),LOCALAPPDATA=str(p/"local"),AETHER_OPENCODE_AUTH=str(legacy))
            for key in ["AETHER_T3_SETTINGS","AETHER_CODEX_HOMES","AETHER_CLAUDE_HOMES","AETHER_OPENCODE_BIN","AETHER_OPENCODE_DB","OPENAI_API_KEY","CODEX_API_KEY"]:
                env.pop(key,None)
            def cli(*args):
                result=subprocess.run([str(BIN),*args],env=env,capture_output=True,text=True,timeout=35,check=True)
                self.assertNotIn("secret",result.stdout+result.stderr)
                return result.stdout
            def check_clients():
                data=json.loads(cli("refresh"))
                rows=data["accounts"]
                self.assertEqual({r["provider"] for r in rows},{"Claude Code","Pi","OpenCode"})
                self.assertEqual(len(rows),4)
                self.assertEqual({r["status"] for r in rows},{"login_required","api_key"})
                self.assertTrue(all(r["windows"]==[] for r in rows))
                self.assertNotIn("agentrouter",json.dumps(data).lower())
                self.assertNotIn("freegg",json.dumps(data).lower())
                self.assertIn("OpenCode",cli("accounts"))
                self.assertEqual(json.loads(cli("usage")),data)
                self.assertEqual(json.loads(cli("history","1"))["samples"],[])
                return data
            check_clients()
            # Real process boundary with OpenCode v2's multiple-account export schema.
            fake=p/("opencode.exe" if os.name=="nt" else "opencode")
            source=p/"fake-opencode.rs"
            source.write_text(r'''
fn main(){
    assert_eq!(std::env::args().skip(1).collect::<Vec<_>>(),vec!["auth","export"]);
    println!("{}",r#"[{"id":"cred-test","integrationID":"openai","label":"Test","active":true,"value":{"type":"key","key":"fake-opencode-secret"}}]"#);
}
''')
            subprocess.run(["rustc",str(source),"-o",str(fake)],check=True,timeout=90)
            del env["AETHER_OPENCODE_AUTH"]
            env["AETHER_OPENCODE_BIN"]=str(fake)
            check_clients()
            self.assertIn("fake-claude-secret",credential.read_text(),"The owning client must retain control of its credentials")
            # MCP login data must not be misidentified as a Claude model account.
            credential.write_text('{"mcpOAuth":{"some-server":{"accessToken":"fake-mcp-secret"}}}')
            self.assertNotIn("Claude Code",cli("accounts"))
            (claude/"settings.json").write_text('{"env":{"ANTHROPIC_AUTH_TOKEN":"fake-gateway-secret"}}')
            claude_rows=[r for r in json.loads(cli("refresh"))["accounts"] if r["provider"]=="Claude Code"]
            self.assertEqual(len(claude_rows),1)
            self.assertEqual(claude_rows[0]["authKind"],"api_key")

if __name__=="__main__":
    unittest.main()
