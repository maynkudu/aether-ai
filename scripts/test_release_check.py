#!/usr/bin/env python3
"""Release metadata tests; run without building Rust or Qt."""
import contextlib
import io
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import release_check

class ReleaseValidation(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=pathlib.Path(self.temp.name)
        (self.root/"shell").mkdir()
        (self.root/"Cargo.toml").write_text('[package]\nversion = "0.2.0"\n')
        (self.root/"shell/shell.qml").write_text('property string version: "0.2.0"\n')
        (self.root/"CHANGELOG.md").write_text("# Changelog\n\n## [0.2.0-alpha.1] - 2026-11-25\n\nAlpha changes.\n\n## [0.2.0] - 2026-11-25\n\nStable changes.\n")

    def invoke(self,tag):
        notes=self.root/"notes.md"
        with patch.object(release_check,"ROOT",self.root),patch.object(sys,"argv",["release_check.py","--tag",tag,"--notes",str(notes)]),contextlib.redirect_stdout(io.StringIO()):
            release_check.main()
        return notes.read_text()

    def test_stable_and_alpha(self):
        self.assertEqual(self.invoke("v0.2.0-alpha.1"),"Alpha changes.\n")
        self.assertEqual(self.invoke("v0.2.0"),"Stable changes.\n")

    def test_deferred_native_versions_do_not_gate_linux(self):
        (self.root/"apps/desktop").mkdir(parents=True)
        (self.root/"apps/desktop/Cargo.toml").write_text('[package]\nversion = "0.1.0"\n')
        self.assertEqual(self.invoke("v0.2.0-alpha.1"),"Alpha changes.\n")

    def test_wrong_or_missing_tag(self):
        for tag in ("v0.2.0-alpha.0","v0.2.0-alpha.01","v0.2.0-foo.1","v0.3.0-alpha.1","v0.2.0-beta.1","v0.2.0-alpha.2"):
            with self.subTest(tag=tag),self.assertRaises(SystemExit):
                self.invoke(tag)

    def test_mismatched_linux_shell(self):
        (self.root/"shell/shell.qml").write_text('property string version: "0.3.0"\n')
        with self.assertRaises(SystemExit):
            self.invoke("v0.2.0-alpha.1")

if __name__=="__main__":
    unittest.main()
