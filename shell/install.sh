#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
p="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/aether"
mkdir -p "$p/icons" "$p/brand-icons"
args=()
if [[ "${1:-}" == --fetch-icons ]]; then
  args+=(--fetch)
fi
if command -v python3 >/dev/null 2>&1; then
  python3 fetch-brand-icons.py "$p/brand-icons" "${args[@]}"
elif [[ ${#args[@]} -gt 0 ]]; then
  printf 'python3 is required to download provider artwork.\n' >&2
  exit 1
fi
# Keep the existing settings glyph, but never reuse old Rune provider icons.
if [[ -s "$p/icons/settings.svg" ]] && command -v magick >/dev/null 2>&1; then
  for variant in white black; do
    value=0%; [[ "$variant" != white ]] || value=100%
    out="$p/icons/settings-$variant.png"
    tmp="$out.tmp"
    if magick -background none -density 384 "$p/icons/settings.svg" -resize 128x128 -alpha on -channel RGB -evaluate set "$value" +channel "PNG32:$tmp"; then
      mv -f "$tmp" "$out"
    else
      rm -f "$tmp"
    fi
  done
fi
[[ ! -f "$p/shell.qml" ]] || cp -p "$p/shell.qml" "$p/shell.qml.bak.$(date +%s)"
install -m644 shell.qml "$p/shell.qml"
printf 'Updated %s. Restart aether only.\n' "$p"
