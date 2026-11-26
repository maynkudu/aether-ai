#!/usr/bin/env python3
"""Opt-in acquisition of provider-published artwork. No runtime network use."""
import argparse
import hashlib
import io
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

PNG = b"\x89PNG\r\n\x1a\n"
MAX_IMAGE = 5 * 1024 * 1024
MAX_ARCHIVE = 64 * 1024 * 1024
RAW = "https://raw.githubusercontent.com/"
BLOSSOM = RAW + "openai/openai-cookbook/4a85c3018d20ceef48bf7549450c567896501bf9/examples/voice_solutions/realtime_translation_guide/livekit-translation-demo/public/brand/"
GROK_KITS = (
    "https://data.x.ai/logos/SpaceXAI_Grok_Assets.zip",
    "https://data.x.ai/logos/xAI_Grok_Assets.zip",
)

def get(url, limit=MAX_IMAGE, git_sha=None):
    req = urllib.request.Request(url, headers={"User-Agent": "aether.ai/brand-assets"})
    with urllib.request.urlopen(req, timeout=20) as response:
        if not response.geturl().startswith("https://"):
            raise ValueError("non-HTTPS redirect")
        data = response.read(limit + 1)
    if not data or len(data) > limit:
        raise ValueError("invalid asset size")
    if git_sha:
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        if hashlib.sha1(blob).hexdigest() != git_sha:
            raise ValueError("upstream asset changed; review source before updating pin")
    return data

def checked_svg(data):
    # Permit ordinary inline styles and local paint servers used by official
    # brand exports, while rejecting active code and remote dependencies.
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper() or b"<?xml-stylesheet" in data.lower():
        raise ValueError("SVG declarations not permitted")
    root = ET.fromstring(data)
    if root.tag.rsplit("}", 1)[-1] != "svg":
        raise ValueError("not an SVG")

    def check_paint(value):
        if re.search(r"@import|@font-face|expression\s*\(|javascript:|vbscript:|\\", value, re.I):
            raise ValueError("active or external SVG style")
        for ref in re.findall(r"url\s*\(([^)]*)\)", value, re.I):
            if not ref.strip().strip("'\"").startswith("#"):
                raise ValueError("external SVG resource")

    for el in root.iter():
        tag = el.tag.rsplit("}", 1)[-1].lower()
        if tag in {"script", "foreignobject", "image", "iframe", "animate", "set", "animatetransform"}:
            raise ValueError("active or external SVG content")
        if tag == "style":
            check_paint(el.text or "")
        for k, v in el.attrib.items():
            key = k.rsplit("}", 1)[-1].lower()
            if key.startswith("on") or (key in {"href", "src"} and not v.startswith("#")):
                raise ValueError("external or active SVG reference")
            if key == "style" or "url" in v.lower():
                check_paint(v)
    return data

def install_art(dest, slug, variant, data, current_color=False):
    if data.startswith(PNG):
        suffix = ".png"
    else:
        suffix = ".svg"
        data = checked_svg(data)
        # Only source assets explicitly designed with currentColor adapt their
        # inherited paint. Do not flatten gradients, opacity or brand colours.
        if current_color:
            data = data.replace(b"currentColor", b"#ffffff" if variant == "dark" else b"#000000")
    with tempfile.TemporaryDirectory() as tmp:
        source = pathlib.Path(tmp) / ("source" + suffix)
        source.write_bytes(data)
        result = pathlib.Path(tmp) / "out.png"
        if shutil.which("magick"):
            subprocess.run([
                "magick", "-limit", "memory", "128MiB", "-limit", "map", "128MiB",
                "-background", "none", "-density", "192", str(source),
                "-resize", "192x192", "-gravity", "center", "-extent", "192x192",
                "PNG32:" + str(result),
            ], check=True, timeout=30, stdout=subprocess.DEVNULL)
            if not result.read_bytes().startswith(PNG):
                raise ValueError("rasterisation failed")
            rendered = result.read_bytes()
        elif suffix == ".png":
            rendered = data
        else:
            raise RuntimeError("ImageMagick (magick) is required for SVG artwork")
    target = dest / (slug + "-" + variant + ".png")
    temp = target.with_suffix(".tmp")
    temp.write_bytes(rendered)
    temp.replace(target)
    print("Installed:", target.name)

def both(dest, slug, url, git_sha=None, current_color=False):
    data = get(url, git_sha=git_sha)
    for variant in ("dark", "light"):
        install_art(dest, slug, variant, data, current_color)

def separate(dest, slug, sources):
    for variant, (url, sha) in sources.items():
        try:
            install_art(dest, slug, variant, get(url, git_sha=sha))
        except Exception as exc:
            print("Unavailable:", slug, variant, "-", exc)

def grok(dest):
    archive = None
    for url in GROK_KITS:
        try:
            archive = zipfile.ZipFile(io.BytesIO(get(url, MAX_ARCHIVE)))
            break
        except Exception as exc:
            print("Grok brand kit:", exc)
    if archive is None:
        raise RuntimeError("official Grok brand kit unavailable")
    with archive:
        for variant, tones in (("dark", ("light", "white")), ("light", ("dark", "black"))):
            names = {prefix + tone for prefix in ("groklogomark", "groksymbol", "grokicon") for tone in tones}
            matches = []
            for entry in archive.infolist():
                p = pathlib.PurePosixPath(entry.filename)
                key = re.sub(r"[^a-z0-9]", "", p.stem.lower())
                if key in names and p.suffix.lower() in {".svg", ".png"} and 0 < entry.file_size <= MAX_IMAGE:
                    matches.append(entry)
            matches.sort(key=lambda e: (not e.filename.lower().endswith(".svg"), len(e.filename)))
            if not matches:
                print("Unavailable: Grok", variant, "- no matching symbol in official kit")
                continue
            try:
                install_art(dest, "grok", variant, archive.read(matches[0]))
            except Exception as exc:
                print("Unavailable: Grok", variant, "-", exc)

def fetch(dest):
    # Use the approved transparent ChatGPT/OpenAI Blossom variants for
    # identification of OpenAI's Codex provider, not aether's own branding.
    separate(dest, "openai", {
        "dark": (BLOSSOM + "chatgpt-blossom-white.svg", "6341b6fa91c82e4f6fdd9f26e0c2103c13913135"),
        "light": (BLOSSOM + "chatgpt-blossom-black.svg", "7c119340c4fc1e6aa59628a2c7aa656077e29939"),
    })
    # First-party product sites and official source repositories.
    assets = [
        ("claude", "https://assets-proxy.anthropic.com/claude-ai/v2/assets/v1/cd02a42d9-Vq_H3mgS.svg", None, True),
        ("opencode", RAW + "anomalyco/models.dev/dev/providers/opencode/logo.svg", "2e9468f6ad10aca915d92b7d4128eceec2b8b045", True),
        ("pi", "https://pi.dev/favicon.svg", None, True),
        ("openrouter", RAW + "OpenRouterTeam/sign-in-with-openrouter/main/public/openrouter-logo.svg", "c86d1c8db9dc62b55b707b07b517c61c008df74c", True),
    ]
    for slug, url, sha, adaptive in assets:
        try:
            both(dest, slug, url, sha, adaptive)
        except Exception as exc:
            print("Unavailable:", slug, "-", exc)
    separate(dest, "deepseek", {
        "dark": (RAW + "deepseek-ai/deepseek-harness/master/apps/web/public/favicon-dark.svg", "648fe4f2b9b5c7f94973e922094613e3012ceeba"),
        "light": (RAW + "deepseek-ai/deepseek-harness/master/apps/web/public/favicon.svg", "754615a37acaf1d24973b4e757ccdb16b9b8f003"),
    })
    try:
        grok(dest)
    except Exception as exc:
        print("Unavailable: Grok -", exc)

def index(dest):
    result = {}
    for p in sorted(dest.glob("*.png")):
        match = re.fullmatch(r"([a-z0-9]{1,64})-(dark|light)\.png", p.name)
        if match and p.is_file():
            with p.open("rb") as stream:
                if stream.read(8) != PNG:
                    continue
            slug, theme = match.groups()
            result.setdefault(slug, {})[theme] = p.name
    target = dest / "index.json"
    temporary = target.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    temporary.replace(target)
    print("Indexed provider artwork:", ", ".join(result) or "none")
    if not result:
        print("No verified/local brand assets installed; provider initials will be shown.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--fetch", action="store_true")
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    if args.fetch:
        fetch(args.directory)
    index(args.directory)

if __name__ == "__main__":
    main()
