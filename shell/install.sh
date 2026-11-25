#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
p="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/aether"
mkdir -p "$p/icons"
# Reuse the original Rune SVGs from v3. No network access by default.
if [[ "${1:-}" == --fetch-icons ]]; then
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  git clone --depth 1 https://github.com/Runeicons/runeicons.git "$work/rune"
  python3 - "$work/rune" "$p/icons" <<'PY'
import pathlib,sys,re,shutil,xml.etree.ElementTree as ET
root,dest=map(pathlib.Path,sys.argv[1:]); files=list((root/'public').rglob('*.svg'))
for name,aliases,brand in [('codex',['codex','codex-openai','openai-codex'],True),('claude',['claude','claude-code'],True),('grok',['grok'],True),('opencode',['opencode','open-code'],True),('pi',['pi','pi-ai'],True),('settings',['settings','settings-2','gear','cog'],False)]:
 def norm(s): return re.sub(r'[^a-z0-9]','',s.lower())
 candidates=[f for f in files if norm(f.stem) in [norm(a) for a in aliases] and (('brand' in str(f.relative_to(root)).lower() or 'logo' in str(f.relative_to(root)).lower()) if brand else 'normal' in f.relative_to(root).parts)]
 for f in sorted(candidates,key=lambda f: (aliases.index(f.stem) if f.stem in aliases else 99,len(str(f)))):
  try:
   el=ET.parse(f).getroot(); assert el.tag.endswith('svg'); shutil.copyfile(f,dest/(name+'.svg')); print(name,':',f.relative_to(root)); break
  except (ET.ParseError,AssertionError): continue
 else: print('Rune asset not found:',name,'— retaining existing file or text fallback')
PY
fi
# Render actual monochrome alpha masks, not a hue tint. The RGB channels
# are set to pure white/black; transparent cutouts and antialiasing survive.
if command -v magick >/dev/null 2>&1; then
  for name in codex claude grok opencode pi settings; do
    src="$p/icons/$name.svg"
    if [[ ! -s "$src" ]]; then printf 'Missing Rune SVG: %s (text fallback)\n' "$name"; continue; fi
    for variant in white black; do
      value=0%; [[ "$variant" != white ]] || value=100%
      out="$p/icons/$name-$variant.png"
      tmp="$out.tmp"
      if magick -background none -density 384 "$src" -resize 128x128 -alpha on -channel RGB -evaluate set "$value" +channel "PNG32:$tmp"; then
        mv -f "$tmp" "$out"
      else
        rm -f "$tmp"; printf 'Could not render %s %s; using text fallback.\n' "$name" "$variant" >&2
      fi
    done
  done
else
  printf 'ImageMagick not installed; existing PNGs will be used, otherwise text fallback. Optional: sudo pacman -S --needed imagemagick\n'
fi
[[ ! -f "$p/shell.qml" ]] || cp -p "$p/shell.qml" "$p/shell.qml.bak.$(date +%s)"
install -m644 shell.qml "$p/shell.qml"
printf 'Updated %s. Restart aether only.\n' "$p"
