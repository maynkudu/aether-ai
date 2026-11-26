#!/usr/bin/env python3
"""Exercise the shell's real grouping, motion and async-read code in Qt."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

from test_drawer_motion import qml_block

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'shell/shell.qml').read_text()


def run_qml(body):
    with tempfile.TemporaryDirectory(prefix='aether-shell-state-') as directory:
        path = Path(directory) / 'shell.qml'
        path.write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\nShellRoot {\nid: root\n' + body + '\n}')
        result = subprocess.run(['qs', '-p', str(path), '--no-color'],
                                env=dict(os.environ, QT_QPA_PLATFORM='offscreen'),
                                capture_output=True, text=True, timeout=12)
    output = result.stdout + result.stderr
    if result.returncode:
        raise AssertionError(output)
    match = re.search(r'SHELL_CHECK (\{[^\n]+\})', output)
    if not match:
        raise AssertionError(output)
    return json.loads(match[1])


class ShellState(unittest.TestCase):
    def test_service_rows_preserve_auth_hierarchy_and_pair_unknown_or_free_peers(self):
        cases = [(['oauth', 'oauth'], [2]), (['oauth'] * 3, [2, 1]),
                 (['oauth', 'oauth', 'api_key'], [2, 1]),
                 (['oauth', 'api_key', 'api_key'], [1, 2]),
                 (['oauth', 'api_key'], [2])]
        inputs = [(service, kinds, sizes) for service in ['Codex', 'Claude Code', 'Pi', 'OpenCode']
                  for kinds, sizes in cases]
        inputs += [('Codex', ['oauth', 'unknown'], [2]),
                   ('OpenCode', ['api_key', 'free'], [2])]
        functions = '\n'.join(qml_block(SOURCE, 'function ' + name + '(')
                              for name in ['authTier', 'accountRows', 'overviewGroups'])
        result = run_qml('''
property var accounts: []
function accountUsage(account) { return {available:false} }
function hasUsageData(usage) { return usage.available }
''' + functions + '''
Timer { interval:1; running:true; onTriggered: {
    let results=[]
    for(let test of ''' + json.dumps(inputs) + ''') {
        root.accounts=test[1].map((authKind,index)=>({id:String(index),name:String(index),provider:test[0],authKind:authKind,windows:[]}))
        let groups=root.overviewGroups()
        results.push({service:groups[0].provider,sizes:groups[0].rows.map(row=>row.length),ids:groups[0].rows.reduce((all,row)=>all.concat(row.map(item=>item.account.id)),[])})
    }
    console.log("SHELL_CHECK "+JSON.stringify({results:results}))
    Qt.quit()
}}
''')
        for (service, kinds, sizes), actual in zip(inputs, result['results'], strict=True):
            self.assertEqual(actual['service'], service)
            self.assertEqual(actual['sizes'], sizes, (service, kinds))
            self.assertEqual(actual['ids'], [str(i) for i in range(len(kinds))])

    def test_menu_uses_monitor_timing_in_both_directions_and_reduced_motion(self):
        component = qml_block(SOURCE, 'component MotionValue: Item').replace(
            'id: motion', 'id: motion; property int measuredDuration: tween.duration', 1)
        functions = '\n'.join(qml_block(SOURCE, 'function ' + name + '(')
                              for name in ['motionDuration', 'dataDuration'])
        clocks = '\n'.join(qml_block(SOURCE, marker) for marker in
                           ['MotionValue { id: drawerSpring;', 'MotionValue { id: settingsSpring;'])
        result = run_qml('''
property bool opened: false
property bool settingsOpen: false
property int step: 0
property var readings: ({})
QtObject { id:prefs; property string motionStyle:"smooth"; property int motionMs:360; property int dataMotionMs:450 }
''' + functions + component + clocks + '''
Timer {
    interval:40; running:true; repeat:true
    onTriggered: {
        if(root.step===0) {root.opened=true;root.settingsOpen=true}
        else if(root.step===1) {
            root.readings.monitorOpen=drawerSpring.measuredDuration
            root.readings.menuOpen=settingsSpring.measuredDuration
            drawerSpring.jump(1);settingsSpring.jump(1)
            root.opened=false;root.settingsOpen=false
        } else if(root.step===2) {
            root.readings.monitorClose=drawerSpring.measuredDuration
            root.readings.menuClose=settingsSpring.measuredDuration
            drawerSpring.jump(.63);settingsSpring.jump(.63)
        } else if(root.step===3) {
            root.readings.monitorPartial=drawerSpring.measuredDuration
            root.readings.menuPartial=settingsSpring.measuredDuration
            prefs.motionStyle="reduced"
        } else {
            root.readings.menuReduced=settingsSpring.value
            console.log("SHELL_CHECK "+JSON.stringify(root.readings));Qt.quit()
        }
        root.step++
    }
}
''')
        self.assertEqual(result['menuOpen'], result['monitorOpen'])
        self.assertEqual(result['menuClose'], result['menuOpen'])
        self.assertEqual(result['menuPartial'], result['monitorPartial'])
        self.assertLess(result['menuPartial'], result['menuClose'])
        self.assertEqual(result['menuReduced'], 0)

    def test_real_process_loading_and_failure_keep_the_last_successful_reading(self):
        backend = 'import json,sys,time;time.sleep(0.15);sys.exit(1) if sys.argv[1]!="7" else print(json.dumps({"samples":[{"id":"recorded"}],"clients":[],"openCode":{"status":"ok"}}))'
        process = qml_block(SOURCE, 'Process {\n        id: analyticsReader')
        process = process.replace('[Quickshell.env("HOME") + "/.local/bin/aether", "analytics", requestedPeriod]',
                                  '[' + ','.join(json.dumps(v) for v in [sys.executable, '-c', backend]) + ',requestedPeriod]')
        refresh = qml_block(SOURCE, 'function refreshAnalytics(')
        result = run_qml('''
property string analyticsPeriod:"7"
property var analyticsSamples:[]
property var openCodeAnalytics:({})
property var clientUsage:[]
property bool usageReady:false
property double analyticsUpdatedAt:0
property string analyticsStatus:""
property string analyticsError:""
property int phase:0
property int ticks:0
property var readings:({loading:false,kept:false})
''' + process + refresh + '''
Component.onCompleted: root.refreshAnalytics()
Timer {
    interval:10; running:true; repeat:true
    onTriggered: {
        root.ticks++
        if(analyticsReader.running) {
            root.readings.loading=true
            if(root.phase===1) root.readings.kept=root.analyticsSamples.length===1
        } else if(root.usageReady && root.phase===0) {
            if(root.analyticsSamples.length!==1) throw new Error("Successful usage did not arrive")
            root.phase=1;root.analyticsPeriod="8";root.refreshAnalytics()
        } else if(root.usageReady && root.phase===1) {
            root.readings.errorStopped=!!root.analyticsError && !analyticsReader.running
            root.readings.finalSamples=root.analyticsSamples.length
            console.log("SHELL_CHECK "+JSON.stringify(root.readings));Qt.quit()
        }
        if(root.ticks>400) throw new Error("Read did not settle")
    }
}
''')
        self.assertTrue(result['loading'])
        self.assertTrue(result['kept'])
        self.assertTrue(result['errorStopped'])
        self.assertEqual(result['finalSamples'], 1)


if __name__ == '__main__':
    unittest.main()
