#!/usr/bin/env python3
import argparse
import pathlib
import re
import tomllib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parents[1]

def version():
    v = tomllib.loads((ROOT/"Cargo.toml").read_text())["package"]["version"]
    match = re.search(r'property string version:\s*"([^"]+)"', (ROOT/"shell/shell.qml").read_text())
    if not match or match.group(1) != v or not re.fullmatch(r"\d+\.\d+\.\d+",v):
        raise SystemExit("Cargo and QML must share a MAJOR.MINOR.PATCH version")
    desktop = tomllib.loads((ROOT/"apps/desktop/Cargo.toml").read_text())["package"]["version"]
    with (ROOT/"apps/desktop/macos/Info.plist").open("rb") as stream:
        plist = plistlib.load(stream)
    if desktop != v or plist.get("CFBundleShortVersionString") != v or plist.get("CFBundleVersion") != v:
        raise SystemExit("Desktop and macOS bundle versions must match the shared version")
    return v

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--tag")
    p.add_argument("--notes",type=pathlib.Path)
    args = p.parse_args()
    v = version()
    if args.tag:
        if args.tag != "v"+v:
            raise SystemExit("Tag does not match Cargo/QML version")
        text = (ROOT/"CHANGELOG.md").read_text()
        match = re.search(r"(?m)^## \["+re.escape(v)+r"\] - \d{4}-\d{2}-\d{2}[ \t]*$",text)
        if not match:
            raise SystemExit("Release needs a dated ## [VERSION] - YYYY-MM-DD heading")
        notes = re.split(r"(?m)^## ",text[match.end():],maxsplit=1)[0].strip()
        if not notes:
            raise SystemExit("Empty release notes")
        if args.notes:
            args.notes.write_text(notes+"\n")
    print("Version metadata OK:",v)

if __name__ == "__main__":
    main()
