#!/usr/bin/env python3
"""Validate Wisp SVGs and normalized motion tracks without third-party packages."""
import json
import hashlib
import pathlib
import struct
import xml.etree.ElementTree as ET
root = pathlib.Path(__file__).resolve().parents[1]
assets = root / "docs/assets"
brand = assets / "branding"
ns = {"svg": "http://www.w3.org/2000/svg"}
light = ET.parse(brand / "wisp-light.svg").find("svg:path", ns)
dark = ET.parse(brand / "wisp-dark.svg").find("svg:path", ns)
logo = ET.parse(assets / "logo.svg").find("svg:path", ns)
assert light is not None and dark is not None and logo is not None
assert light.get("d") == dark.get("d") == logo.get("d")
for path in brand.glob("*.svg"):
    tree = ET.parse(path)
    assert not tree.findall(".//svg:script", ns)
for variant in ("light", "dark"):
    tree = ET.parse(brand / f"wisp-animated-{variant}.svg")
    assert "prefers-reduced-motion" in (tree.find("svg:style", ns).text or "")
    body = tree.find(".//svg:path[@id='wisp-body']", ns)
    assert body is not None and light.get("d").startswith(body.get("d"))
data = json.loads((brand / "motion.json").read_text())
assert data["durationMs"] == 18000
for name, points in data["tracks"].items():
    assert points[0][0] == 0 and points[-1][0] == 100
    assert points[0][1] == points[-1][1], name
    assert all(a[0] < b[0] for a, b in zip(points, points[1:])), name
for path in (assets / "logo.png", brand / "wisp-body.png"):
    assert path.read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
print("Wisp geometry, SVGs, PNG signatures and motion tracks validated.")

logos = root / "shell/provider-logos"
sources = json.loads((logos / "sources.json").read_text())
assert set(sources) == {"codex", "claude", "opencode", "pi"}
for name, source in sources.items():
    for variant in ("dark", "light"):
        data = (logos / f"{name}-{variant}.png").read_bytes()
        assert data.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">II", data[16:24]) == (192, 192)
        assert hashlib.sha256(data).hexdigest() == source[f"{variant}Sha256"]
print("All eight bundled client logos match their recorded hashes and dimensions.")
