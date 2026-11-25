#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" -ne 0
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
export HOME="$work/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state" XDG_RUNTIME_DIR="$work/runtime"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME/quickshell/aether" "$HOME/.local/bin" "$XDG_CACHE_HOME/aether"
chmod 700 "$XDG_RUNTIME_DIR"
cp "$root/shell/shell.qml" "$XDG_CONFIG_HOME/quickshell/aether/"
cp "$root/target/release/aether" "$HOME/.local/bin/aether"
cp "$root/scripts/update.py" "$HOME/.local/bin/aether-update"
chmod +x "$HOME/.local/bin/aether-update"
printf '[AetherUI]\nviewMode=rings\n' > "$XDG_CONFIG_HOME/quickshell/aether/preferences.ini"
cat > "$XDG_CACHE_HOME/aether/usage.json" <<'JSON'
{"accounts":[{"id":"smoke-one","name":"Smoke 100","provider":"Codex","status":"ok","windows":[{"minutes":300,"remaining":100},{"minutes":10080,"remaining":64}]},{"id":"smoke-two","name":"Smoke zero","provider":"Codex","status":"ok","windows":[{"minutes":300,"remaining":0}]}],"updated":null}
JSON
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER_ALLOW_SOFTWARE=1
export LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=shm
unset WAYLAND_DISPLAY DISPLAY
printf 'output * resolution 1280x800\nxwayland disable\n' > "$work/sway.conf"
sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 &
compositor=$!
shellpid=""
cleanup() {
  code=$?
  if [[ -n "$shellpid" ]]; then kill "$shellpid" 2>/dev/null || true; fi
  kill "$compositor" 2>/dev/null || true
  if [[ -f "$work/sway.log" ]]; then cat "$work/sway.log" >&2; fi
  if [[ -f "$work/qs.log" ]]; then cat "$work/qs.log" >&2; fi
  rm -rf "$work"
  exit "$code"
}
trap cleanup EXIT
for i in $(seq 1 60); do
  socket="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' -print -quit)"
  if [[ -n "$socket" ]]; then export WAYLAND_DISPLAY="$(basename "$socket")"; break; fi
  kill -0 "$compositor"
  sleep 0.25
done
test -n "${WAYLAND_DISPLAY:-}" || { echo "Headless Wayland socket was not created" >&2; exit 1; }
qs -c aether >"$work/qs.log" 2>&1 &
shellpid=$!
for i in $(seq 1 80); do
  if grep -q 'Configuration Loaded' "$work/qs.log"; then break; fi
  kill -0 "$shellpid"
  sleep 0.25
done
grep -q 'Configuration Loaded' "$work/qs.log"
for action in toggle settings analytics shortcuts dismiss; do
  timeout 15 qs -c aether ipc call dashboard "$action"
  sleep 3
  kill -0 "$shellpid"
done
if grep -Ei 'failed to load configuration|TypeError:|ReferenceError:|Cannot assign to non-existent property|ERROR:' "$work/qs.log"; then exit 1; fi
