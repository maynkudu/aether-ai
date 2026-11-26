#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ui_only=false
icon_args=()
for arg in "$@"; do
  case "$arg" in
    --ui-only) ui_only=true ;;
    --fetch-icons|--fetch-fonts) icon_args+=("$arg") ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
if [[ "$(id -u)" == 0 ]]; then
  printf 'Run the installer as your desktop user, without sudo.\n' >&2
  exit 1
fi
required=(install flock systemctl qs python3)
if [[ "$ui_only" == false ]]; then required+=(cargo git); fi
for tool in "${required[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'Missing prerequisite: %s. See docs/LINUX.md.\n' "$tool" >&2; exit 1; }
done
systemctl --user show-environment >/dev/null || { printf 'A running systemd user manager is required. Run this from your user session.\n' >&2; exit 1; }
state="${XDG_STATE_HOME:-$HOME/.local/state}/aether"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$state"
chmod 700 "$state"
exec 9>"$state/update.lock"
flock -n 9 || { printf 'Another aether installation is running.\n' >&2; exit 1; }
if [[ "$ui_only" == false ]]; then
  cargo build --release --locked
  install -Dm755 target/release/aether "$HOME/.local/bin/aether"
  install -Dm644 systemd/aether.service "$unit_dir/aether.service"
fi
bash shell/install.sh "${icon_args[@]}"
install -Dm755 scripts/update.py "$HOME/.local/bin/aether-update"
install -Dm644 systemd/aether-ui.service "$unit_dir/aether-ui.service"
install -Dm644 systemd/aether-update.service "$unit_dir/aether-update.service"
install -Dm644 systemd/aether-update.timer "$unit_dir/aether-update.timer"
if [[ "$ui_only" == false ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git diff --quiet && git diff --cached --quiet; then
  git rev-parse HEAD > "$state/installed-commit.tmp"
  chmod 600 "$state/installed-commit.tmp"
  mv -f "$state/installed-commit.tmp" "$state/installed-commit"
fi
systemctl --user daemon-reload
if [[ "$ui_only" == false ]]; then
  systemctl --user enable aether.service
  systemctl --user restart aether.service
  systemctl --user is-active --quiet aether.service
fi
systemctl --user enable aether-ui.service aether-update.timer
systemctl --user start aether-update.timer
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  session_vars=(WAYLAND_DISPLAY)
  for name in DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE; do
    if [[ -n "${!name:-}" ]]; then session_vars+=("$name"); fi
  done
  systemctl --user import-environment "${session_vars[@]}"
  systemctl --user restart aether-ui.service
  ui_ready=false
  for attempt in {1..50}; do
    if qs -c aether ipc show >/dev/null 2>&1; then ui_ready=true; break; fi
    if ! systemctl --user is-active --quiet aether-ui.service; then break; fi
    sleep 0.1
  done
  if [[ "$ui_ready" == false ]]; then
    printf 'Aether UI did not become ready. Check journalctl --user -u aether-ui.service.\n' >&2
    exit 1
  fi
  printf 'Installed. The quota daemon and Wayland interface are managed by systemd.\n'
else
  printf 'Installed. The interface is enabled for your next graphical session.\n'
fi
printf 'See docs/LINUX.md for boot-time polling, compositor startup, usage and logs.\n'
