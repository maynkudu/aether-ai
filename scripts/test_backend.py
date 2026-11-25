#!/usr/bin/env python3
"""Credential-free integration test using a fake Codex app-server."""
import json, os, pathlib, subprocess, sys, tempfile, unittest
BIN = pathlib.Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else pathlib.Path("target/release/aether").resolve()

class Backend(unittest.TestCase):
    def test_quota_history_and_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)
            home, bins, account = p/"home", p/"bin", p/"fake-account"
            for folder in (home,bins,account):
                folder.mkdir()
            fake=bins/("codex.exe" if os.name=="nt" else "codex")
            shim="""#!/usr/bin/env python3
import json,sys
for line in sys.stdin:
    m=json.loads(line)
    if m.get("id")==1:
        print(json.dumps({"id":1,"result":{}}),flush=True)
    elif m.get("id")==2:
        print(json.dumps({"id":2,"result":{"rateLimits":{"primary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":2000000000}}}}),flush=True)
"""
            if os.name=="nt":
                fixture=p/"fake.rs"
                fixture.write_text(r'''
use std::io::{self,BufRead,Write};
fn main(){
    for line in io::stdin().lock().lines().map_while(Result::ok) {
        if line.contains("\"id\":1") {
            println!("{}",r#"{"id":1,"result":{}}"#);
        } else if line.contains("\"id\":2") {
            println!("{}",r#"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":18,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":36,"windowDurationMins":10080,"resetsAt":2000000000}}}}"#);
        }
        io::stdout().flush().unwrap();
    }
}
''')
                subprocess.run(["rustc",str(fixture),"-o",str(fake)],check=True,timeout=60)
            else:
                fake.write_text(shim)
                fake.chmod(0o755)
            env=dict(os.environ,HOME=str(home),XDG_CACHE_HOME=str(p/"cache"),XDG_STATE_HOME=str(p/"state"),AETHER_CODEX_HOMES=str(account),PATH=str(bins)+os.pathsep+os.environ["PATH"])
            env.update(USERPROFILE=str(home),APPDATA=str(p/"appdata"),LOCALAPPDATA=str(p/"local"),AETHER_CODEX_BIN=str(fake),CODEX_HOME=str(home/".codex"))
            env.pop("AETHER_T3_SETTINGS",None)
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

if __name__=="__main__":
    unittest.main()
