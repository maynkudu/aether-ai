#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
state="${XDG_STATE_HOME:-$HOME/.local/state}/aether"
mkdir -p "$state"
chmod 700 "$state"
exec 9>"$state/update.lock"
flock -n 9 || { printf "Another aether installation is running.\n" >&2; exit 1; }
ui_only=false
icon_args=()
for arg in "$@"; do
  case "$arg" in
    --ui-only) ui_only=true ;;
    --fetch-icons|--fetch-fonts) icon_args+=("$arg") ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
if [[ "$ui_only" == false ]]; then
  cargo build --release
  install -Dm755 target/release/aether "$HOME/.local/bin/aether"
  install -Dm644 systemd/aether.service "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/aether.service"
  systemctl --user daemon-reload
fi
bash shell/install.sh "${icon_args[@]}"
install -Dm755 scripts/update.py "$HOME/.local/bin/aether-update"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
install -Dm644 systemd/aether-update.service "$unit_dir/aether-update.service"
install -Dm644 systemd/aether-update.timer "$unit_dir/aether-update.timer"
if [[ "$ui_only" == false ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git diff --quiet && git diff --cached --quiet; then
  git rev-parse HEAD > "$state/installed-commit.tmp"
  chmod 600 "$state/installed-commit.tmp"
  mv -f "$state/installed-commit.tmp" "$state/installed-commit"
fi
systemctl --user daemon-reload
systemctl --user enable --now aether-update.timer || printf 'Updater timer could not be enabled; manual checks remain available.\n' >&2
printf 'Installed. See README.md for startup and service instructions.\n'
