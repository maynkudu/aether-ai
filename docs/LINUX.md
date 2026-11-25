# Linux guide

[← Project home](../README.md)

## Install

Wayland, Quickshell (Qt 6.8+), Rust/Cargo, Bash, Git, Python 3.12+, util-linux flock, systemd user services and native Codex CLI. ImageMagick and fontconfig are optional. On Arch, use your normal package manager for missing dependencies; keep existing rustup if already installed.

```bash
git clone https://github.com/maynkudu/aether-ai.git
cd aether-ai
codex login
bash install.sh --fetch-icons --fetch-fonts
systemctl --user enable --now aether.service
qs -c aether
```

Fish: `fish_add_path ~/.local/bin`. In a second terminal run `qs -c aether ipc call dashboard settings`. Default hotspot: top-right; choose another in Behaviour.

## Shortcuts

The Shortcuts tab generates legacy or Lua bindings and detects duplicates among aether bindings. Merge into your existing compositor config after checking conflicts. No compositor files are edited automatically.

```ini
exec-once = qs -c aether
bind = SUPER, U, exec, qs -c aether ipc call dashboard toggle
bind = SUPER SHIFT, U, exec, qs -c aether ipc call dashboard settings
bind = SUPER ALT, U, exec, qs -c aether ipc call dashboard analytics
```

For compatible Lua Hyprland configurations:

```lua
hl.bind("SUPER + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard toggle"))
hl.bind("SUPER + SHIFT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard settings"))
hl.bind("SUPER + ALT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard analytics"))
```

Ctrl+1–8 navigate Overview, Appearance, Providers, Analytics, Behaviour, Shortcuts, Updates and About. Ctrl+R refreshes cached data; Escape dismisses. IPC also supports refresh, dismiss and shortcuts.

## Updates and rollback

```bash
git pull --ff-only
bash install.sh
systemctl --user restart aether.service
qs kill -c aether
qs -c aether
```

UI-only: `bash install.sh --ui-only`, restart only aether. Full installation records a clean tracked checkout's commit; UI-only does not advance the full-build receipt. Fetch missing fonts/artwork with `bash install.sh --ui-only --fetch-icons --fetch-fonts`.

The user timer checks approximately every six hours when automatic installation is enabled. Stable follows published non-prerelease vMAJOR.MINOR.PATCH releases; Development follows main. The updater rejects downgrades and divergent commits, builds in an isolated temporary directory, and retains a previous build. Rust compilation alone cannot prove QML validity.

```bash
aether-update status
aether-update check development
aether-update apply development
aether-update rollback
```

The rolled-back commit is excluded from automatic reinstall until a newer candidate or explicit install. Updates do not fetch fonts or artwork. Disable scheduled checks with `systemctl --user disable --now aether-update.timer`.

## Troubleshooting

| Symptom | Diagnostic |
|---|---|
| QML fails to load | Capture the first error from `qs -c aether`; check line number and reinstall after updating. |
| No accounts | Verify `codex --version`, `codex login` and `aether accounts`. |
| Stale cache | `systemctl --user status aether.service`; `journalctl --user -u aether.service -n 50 --no-pager`. |
| Missing artwork/fonts | Use opt-in fetch flags; restart aether. |
| Caelestia unavailable | Check standard `qs -c caelestia list` and valid palette. |

Include OS/architecture, `qs --version`, `hyprctl version` (if applicable), `aether version` and first error in reports. Redact names, private paths and credentials.

## Removal

Stop aether with `systemctl --user disable --now aether.service aether-update.timer` and `qs kill -c aether`. Remove only its binaries from ~/.local/bin and its three user unit files from XDG_CONFIG_HOME/systemd/user; run `systemctl --user daemon-reload`. Remove aether-specific compositor binds. Preferences, cache, history and fonts are separate; delete only if you no longer want them. Never delete provider or Caelestia directories.
