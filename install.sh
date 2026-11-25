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
if [[ "$ui_only" == false ]]; then
  cargo build --release
  install -Dm755 target/release/aether "$HOME/.local/bin/aether"
  install -Dm644 systemd/aether.service "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/aether.service"
  systemctl --user daemon-reload
fi
bash shell/install.sh "${icon_args[@]}"
printf 'Installed. See README.md for startup and service instructions.\n'
