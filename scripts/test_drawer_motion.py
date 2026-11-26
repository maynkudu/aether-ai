#!/usr/bin/env python3
"""Check drawer entry and exit timing through actual Qt property bindings."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def qml_block(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 0
    for position in range(brace, len(source)):
        if source[position] == '{':
            depth += 1
        elif source[position] == '}':
            depth -= 1
            if depth == 0:
                return source[start:position + 1]
    raise ValueError('Unclosed QML block: ' + marker)


class DrawerMotionTiming(unittest.TestCase):
    def test_native_direction_timing(self):
        source = (ROOT / 'shell/shell.qml').read_text()
        component = qml_block(source, 'component MotionValue: Item')
        component = component.replace('id: motion', 'id: motion; property int measuredDuration: tween.duration', 1)
        drawer = qml_block(source, 'MotionValue { id: drawerSpring;')
        functions = '\n'.join(qml_block(source, 'function ' + name + '(') for name in ['motionDuration', 'dataDuration'])
        qml = '''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property bool opened: false
    property int step: 0
    property var readings: ({})
    QtObject { id: prefs; property string motionStyle: "smooth"; property int motionMs: 240; property int dataMotionMs: 450 }
''' + functions + '\n' + component + '\n' + drawer + '''
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: {
            if (root.step === 0) root.opened = true
            else if (root.step === 1) {
                root.readings.opening = drawerSpring.measuredDuration
                drawerSpring.jump(1)
                root.opened = false
            } else if (root.step === 2) {
                root.readings.closing = drawerSpring.measuredDuration
                drawerSpring.jump(0.63)
            } else if (root.step === 3) {
                root.readings.partialClosing = drawerSpring.measuredDuration
                prefs.motionStyle = "reduced"
            } else {
                root.readings.reducedValue = drawerSpring.value
                console.log("DRAWER_TIMING " + JSON.stringify(root.readings))
                Qt.quit()
            }
            root.step++
        }
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='aether-drawer-timing-') as directory:
            path = Path(directory) / 'shell.qml'
            path.write_text(qml)
            environment = dict(os.environ, QT_QPA_PLATFORM='offscreen')
            result = subprocess.run(['qs', '-p', str(path), '--no-color'], env=environment, capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        match = re.search(r'DRAWER_TIMING (\{[^\n]+\})', output)
        self.assertIsNotNone(match, output)
        readings = json.loads(match[1])
        print(json.dumps(readings), flush=True)
        self.assertGreaterEqual(readings['opening'], 580, 'Opening must retain the approved entrance timing')
        self.assertLessEqual(readings['opening'], 610)
        self.assertEqual(readings['closing'], readings['opening'], 'Closing must reverse the entrance at the same speed')
        self.assertLess(readings['partialClosing'], readings['closing'])
        self.assertEqual(readings['reducedValue'], 0)


if __name__ == '__main__':
    unittest.main()
