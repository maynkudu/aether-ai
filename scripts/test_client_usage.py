#!/usr/bin/env python3
"""Exercise metadata-only Pi/Claude readers through the shipped CLI."""
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

BIN=Path(sys.argv.pop(1)).resolve() if len(sys.argv)>1 else Path('target/release/aether').resolve()


class ClientUsage(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)
        self.pi=self.root/'pi'
        self.claude=self.root/'claude'
        self.extra=self.root/'extra-claude'
        self.env=dict(os.environ)
        for key in ['AETHER_T3_SETTINGS','AETHER_CODEX_HOMES','AETHER_OPENCODE_AUTH','AETHER_OPENCODE_DB','OPENAI_API_KEY','CODEX_API_KEY']:
            self.env.pop(key,None)
        for variable,folder in [('HOME','home'),('USERPROFILE','home'),('CODEX_HOME','codex'),('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache'),('XDG_STATE_HOME','state'),('APPDATA','appdata'),('LOCALAPPDATA','local')]:
            self.env[variable]=str(self.root/folder)
        self.env.update(CLAUDE_CONFIG_DIR=str(self.claude),AETHER_CLAUDE_HOMES=str(self.extra),PI_CODING_AGENT_DIR=str(self.pi),AETHER_OPENCODE_BIN=str(self.root/'missing-opencode'))
        self.now=int(time.time())

    def tearDown(self):
        self.tmp.cleanup()

    def timestamp(self,offset=0):
        return datetime.datetime.fromtimestamp(self.now+offset,datetime.timezone.utc).isoformat().replace('+00:00','Z')

    def write(self,path,records):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text('\n'.join(json.dumps(r) for r in records)+'\n')

    def cli(self,*args):
        result=subprocess.run([str(BIN),*args],env=self.env,capture_output=True,text=True,check=True,timeout=35)
        self.assertNotIn('private-content',result.stdout+result.stderr)
        self.assertNotIn('fake-auth-value',result.stdout+result.stderr)
        return json.loads(result.stdout)

    def pi_record(self,provider='test-upstream',offset=0,output=8):
        return {'type':'message','id':'entry','timestamp':self.timestamp(offset),'message':{'role':'assistant','provider':provider,'responseId':'response','content':'private-content','usage':{'input':12,'output':output,'reasoning':2,'cacheRead':20,'cacheWrite':3,'cost':{'total':0.25,'totalFromProvider':False}}}}

    def test_usage_profiles_replays_provider_exclusion_and_unknown_prices(self):
        pi=self.pi/'sessions/project'
        self.write(pi/'one.jsonl',[self.pi_record(output=4)])
        self.write(pi/'two.jsonl',[self.pi_record(),self.pi_record('agentrouter'),self.pi_record('freegg'),self.pi_record('future',86400),self.pi_record('old',-10*86400)])
        message={'id':'message','role':'assistant','content':'private-content','usage':{'input_tokens':10,'output_tokens':1,'cache_read_input_tokens':5,'cache_creation_input_tokens':2}}
        one={'type':'assistant','requestId':'request','timestamp':self.timestamp(),'costUSD':0.2,'message':message}
        two=dict(one,message=dict(message,usage=dict(message['usage'],output_tokens=99)))
        self.write(self.claude/'projects/test/session.jsonl',[one,two])
        self.write(self.extra/'projects/test/session.jsonl',[dict(one,requestId='other',costUSD=None,message=dict(message,usage={'input_tokens':4,'output_tokens':20}))])
        files={p:p.read_bytes() for p in self.root.rglob('*.jsonl')}
        clients={c['provider']:c for c in self.cli('analytics','7')['clients']}
        pi=clients['Pi']
        self.assertEqual(pi['totals']['steps'],1)
        self.assertEqual(pi['totals']['inputTokens'],35)
        self.assertEqual(pi['totals']['outputTokens'],8)
        self.assertEqual(pi['totals']['totalTokens'],43)
        self.assertEqual(pi['totals']['costUsd'],0.25)
        self.assertEqual([p['providerID'] for p in pi['providers']],['test-upstream'])
        claude=clients['Claude Code']
        self.assertEqual(claude['totals']['steps'],2)
        self.assertEqual(claude['totals']['totalTokens'],21)
        self.assertEqual(claude['totals']['costUsd'],0.2)
        self.assertFalse(claude['totals']['costComplete'])
        self.assertFalse(claude['totals']['tokensComplete'])
        self.assertEqual(len(claude['accounts']),2)
        self.assertTrue(all(path.read_bytes()==before for path,before in files.items()))

    def test_ranges_and_nonsecret_usage_provider_metadata(self):
        recent=self.pi_record()
        old=self.pi_record(offset=-10*86400)
        old['message']['responseId']='old-response'
        self.write(self.pi/'sessions/session.jsonl',[recent,old])
        def total(days):return next(c for c in self.cli('analytics',str(days))['clients'] if c['provider']=='Pi')['totals']
        self.assertEqual(total(7)['steps'],1)
        self.assertEqual(total(30)['steps'],2)
        self.write(self.pi/'auth.json',[])
        (self.pi/'auth.json').write_text(json.dumps({'test-upstream':{'type':'api_key','key':'fake-auth-value'}}))
        self.claude.mkdir(parents=True,exist_ok=True)
        (self.claude/'settings.json').write_text(json.dumps({'env':{'ANTHROPIC_API_KEY':'fake-auth-value'}}))
        rows=self.cli('refresh')['accounts']
        self.assertEqual({r['provider'] for r in rows},{'Claude Code','Pi'})
        self.assertEqual({r['usageProvider'] for r in rows},{'anthropic','test-upstream'})
        self.assertTrue(all(r['authKind']=='api_key' and not r['windows'] for r in rows))

    def test_missing_logs_are_empty_and_never_create_client_folders(self):
        clients=self.cli('analytics','7')['clients']
        self.assertTrue(all(c['status']=='empty' for c in clients))
        self.assertTrue(all(c['totals']['steps']==0 for c in clients))
        self.assertFalse(self.pi.exists())
        self.assertFalse(self.claude.exists())


if __name__=='__main__':
    unittest.main()
