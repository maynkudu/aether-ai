#!/usr/bin/env python3
"""Check installation and rollback without changing the user's home or services."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="aether-install-test-")
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.source = self.directory / "source"
        self.source.mkdir()
        for name in ["install.sh", "shell/install.sh", "shell/shell.qml", "shell/fetch-brand-icons.py", "scripts/update.py", "systemd/aether.service", "systemd/aether-ui.service", "systemd/aether-update.service", "systemd/aether-update.timer"]:
            destination = self.source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        shutil.copytree(ROOT / "shell/provider-logos", self.source / "shell/provider-logos")
        self.tools = self.directory / "tools"
        self.tools.mkdir()
        self.log = self.directory / "commands.jsonl"
        stub = self.tools / "installer-test-command"
        stub.write_text('''#!/usr/bin/env python3
import json,os,pathlib,subprocess,sys
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ["AETHER_INSTALL_TEST_LOG"],"a") as stream: stream.write(json.dumps([name,*args])+"\\n")
if name=="id": print("1000")
elif name=="cargo":
 p=pathlib.Path("target/release/aether");p.parent.mkdir(parents=True,exist_ok=True);p.write_text("fixture backend")
elif name=="install":
 destination=pathlib.Path(args[-1])
 if destination.parent==pathlib.Path.home()/".local/bin": args[-1]=str(pathlib.Path(os.environ["AETHER_INSTALL_TEST_BIN"])/destination.name)
 raise SystemExit(subprocess.call(["/usr/bin/install",*args]))
elif name=="systemctl" and args==["--user","restart","aether.service"] and os.environ.get("AETHER_INSTALL_TEST_FAIL"): raise SystemExit(1)
''')
        stub.chmod(0o755)
        for name in ["id", "cargo", "install", "systemctl", "qs"]:
            (self.tools / name).symlink_to(stub)
        self.env = dict(os.environ, PATH=str(self.tools) + os.pathsep + os.environ["PATH"], XDG_CONFIG_HOME=str(self.directory / "config"), XDG_STATE_HOME=str(self.directory / "state"), AETHER_INSTALL_TEST_LOG=str(self.log), AETHER_INSTALL_TEST_BIN=str(self.directory / "bin"), WAYLAND_DISPLAY="test-display")

    def install(self, *args):
        return subprocess.run(["bash", "install.sh", *args], cwd=self.source, env=self.env, capture_output=True, text=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_install_enables_services_and_replaces_manual_ui(self):
        for _ in range(2):
            result = self.install()
            self.assertEqual(result.returncode, 0, result.stderr)
        units = self.directory / "config/systemd/user"
        self.assertEqual((units / "aether-ui.service").read_text(), (ROOT / "systemd/aether-ui.service").read_text())
        self.assertTrue((self.directory / "bin/aether").is_file())
        for logo in (ROOT/"shell/provider-logos").glob("*.png"):
            self.assertEqual((self.directory/"config/quickshell/aether/provider-logos"/logo.name).read_bytes(),logo.read_bytes())
        commands = self.commands()
        self.assertIn(["systemctl", "--user", "enable", "aether.service"], commands)
        self.assertIn(["systemctl", "--user", "enable", "aether-ui.service", "aether-update.timer"], commands)
        self.assertEqual(commands.count(["systemctl", "--user", "restart", "aether-ui.service"]), 2)
        self.assertIn("ExecStartPre=-/usr/bin/qs -c aether kill", (units / "aether-ui.service").read_text())

    def test_ui_only_keeps_backend_and_build_untouched(self):
        result = self.install("--ui-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.directory / "bin/aether").exists())
        commands = self.commands()
        self.assertFalse(any(command[0] == "cargo" for command in commands))
        self.assertNotIn(["systemctl", "--user", "restart", "aether.service"], commands)
        self.assertIn(["systemctl", "--user", "restart", "aether-ui.service"], commands)

    def test_console_install_defers_graphical_start(self):
        self.env.pop("WAYLAND_DISPLAY")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("next graphical session", result.stdout)
        self.assertNotIn(["systemctl", "--user", "restart", "aether-ui.service"], self.commands())

    def test_failed_service_start_is_reported(self):
        self.env["AETHER_INSTALL_TEST_FAIL"] = "1"
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Installed.", result.stdout)

    def test_bad_argument_does_not_install(self):
        result = self.install("--invalid")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.directory / "state").exists())
        self.assertFalse((self.directory / "config").exists())


class UpdaterRollbackTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="aether-rollback-test-")
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        spec = importlib.util.spec_from_file_location("aether_updater_test", ROOT / "scripts/update.py")
        self.updater = importlib.util.module_from_spec(spec)
        original_path = os.environ["PATH"]
        spec.loader.exec_module(self.updater)
        os.environ["PATH"] = original_path
        for name, relative in {"BIN": "bin", "UNITS": "units", "SHELL": "shell", "RECEIPT": "state/receipt", "ROLLBACK": "state/previous.zip", "BLOCKED": "state/blocked"}.items():
            setattr(self.updater, name, directory / relative)
        self.current = "b" * 40
        self.previous = "a" * 40
        self.updater.atomic(self.updater.RECEIPT, (self.current + "\n").encode())
        for target in self.updater.targets():
            self.updater.atomic(target, b"current")

    def archive(self, count):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            for index in range(count):
                archive.writestr(str(index), b"previous")
            archive.writestr("manifest.json", json.dumps({"from": self.previous, "to": self.current, "files": [{"exists": True, "mode": 0o644}] * count}))
        self.updater.atomic(self.updater.ROLLBACK, buffer.getvalue())

    def test_legacy_archive_preserves_ui_service(self):
        self.archive(6)
        self.assertTrue(self.updater.rollback_available())
        with patch.object(self.updater, "restart"):
            self.updater.rollback(self.current)
        self.assertEqual((self.updater.UNITS / "aether-ui.service").read_bytes(), b"current")
        self.assertEqual((self.updater.BIN / "aether").read_bytes(), b"previous")
        self.assertEqual(self.updater.installed(), self.previous)

    def test_current_archive_restores_ui_service(self):
        self.archive(7)
        with patch.object(self.updater, "restart"):
            self.updater.rollback(self.current)
        self.assertEqual((self.updater.UNITS / "aether-ui.service").read_bytes(), b"previous")

    def test_logo_archive_restores_all_provider_artwork(self):
        self.archive(len(self.updater.targets()))
        self.assertTrue(self.updater.rollback_available())
        with patch.object(self.updater, "restart"):
            self.updater.rollback(self.current)
        self.assertTrue(all(path.read_bytes() == b"previous" for path in self.updater.targets()))

    def test_restart_failure_restores_current_installation(self):
        self.archive(7)
        with patch.object(self.updater, "restart", side_effect=[RuntimeError("restart failed"), None]):
            with self.assertRaisesRegex(RuntimeError, "restart failed"):
                self.updater.rollback(self.current)
        self.assertTrue(all(path.read_bytes() == b"current" for path in self.updater.targets()))
        self.assertEqual(self.updater.installed(), self.current)

    def test_restart_preserves_an_inactive_ui(self):
        with patch.object(self.updater, "run") as run:
            self.updater.restart()
        self.assertIn(unittest.mock.call(["systemctl", "--user", "try-restart", "aether-ui.service"], stdout=self.updater.sys.stderr), run.call_args_list)
        self.assertNotIn(unittest.mock.call(["systemctl", "--user", "start", "aether-ui.service"]), run.call_args_list)


if __name__ == "__main__":
    unittest.main()
