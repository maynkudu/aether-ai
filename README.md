# aether.ai

**Intelligence, within limits.**

A local-first AI quota monitor for Linux. Rust backend, independent Quickshell/QML overlay, experimental T3 Code account discovery, and Caelestia-aware theming. No inference proxy or telemetry.

## Current state

Experimental Rust backend v0.1.0 + UI v7. Codex is the only implemented quota provider; Claude, Grok, OpenCode and Pi are planned. The UI does not modify Caelestia or T3 Code. Native managed T3 authentication is not implemented. No license has been selected yet.

## Install

Requirements: Rust/Cargo, Codex CLI, Quickshell, systemd user services. Optional: Python 3 and ImageMagick for fetching/rendering provider artwork, Inter and JetBrains Mono fonts. Rings use QtQuick.Shapes (Qt 6.6+).

```sh
bash install.sh --fetch-icons
```

On Arch, optional dependencies: `sudo pacman -S --needed imagemagick inter-font ttf-jetbrains-mono`. Keep rustup if already installed. The opt-in icon fetch uses [documented provider artwork sources](shell/BRAND-ASSETS.md), not community icon libraries. Original brand artwork and theme variants are retained. Unknown/unavailable providers use initials.

In Fish, ensure `fish_add_path ~/.local/bin` has been run.

```sh
aether accounts
aether refresh
aether usage
systemctl --user enable --now aether.service
qs -c aether
```

Hover at the top-right (default) to open the drawer, or run `qs -c aether ipc call dashboard toggle` in a separate terminal. Settings: `qs -c aether ipc call dashboard settings`.

In Settings, choose Grid (detailed quota cards) or Rings (left semicircle: 5-hour session; right semicircle: weekly). Rings use native circular vector paths, with a fixed square drawing area and evenly spaced rounded caps. Ring colors use Caelestia primary/tertiary tones or two grayscale values in standalone mode. Missing windows show a dash. Choose any of the eight screen corners/edge centres, and enable or disable staggered motion. Settings persist locally. The overlay remains independent of Caelestia.

Optional personal Hyprland configuration:

```ini
exec-once = qs -c aether
bind = SUPER, U, exec, qs -c aether ipc call dashboard toggle
```

## Update

```sh
git pull --ff-only
bash install.sh
systemctl --user restart aether.service
qs kill -c aether
qs -c aether
```

For UI-only updates, use `bash install.sh --ui-only` and restart only aether's Quickshell instance. Preferences and locally installed brand artwork are retained. After updating from v6 or older, run `bash install.sh --ui-only --fetch-icons` once to acquire the new provider artwork. The UI installer backs up the existing shell.qml. Initial UI defaults: 440px width, 820ms opening, approximately 722ms closing.

## Account discovery and safety

T3 discovery is experimental and assumes a settings schema. To locate the settings file without printing secrets:

```sh
find ~/.config ~/.local/share ~/.t3 ~/.t3code -name settings.json 2>/dev/null
```

Use `AETHER_T3_SETTINGS` to specify its exact path or `AETHER_CODEX_HOMES` for colon-separated absolute Codex home paths. In Fish use `set -x AETHER_T3_SETTINGS /actual/path/settings.json` for the current session. Configure daemon overrides with `systemctl --user edit aether.service` and an `[Service]` section containing `Environment=AETHER_T3_SETTINGS=/absolute/path` if needed.

The backend launches native Codex app-server probes and caches primary/secondary quota windows. Codex itself may refresh credentials. Managed T3 credentials and shadow-home runtime semantics are not implemented; shadow homes are treated as standalone CODEX_HOME paths. Deduplication is by directory, not identity. Avoid concurrent manual and daemon refreshes. The daemon polls every 180 seconds. Never commit credentials, personal settings, usage caches or installed configuration directories.

## Roadmap

- Validate T3 discovery and native quota service, including managed accounts.
- Add provider adapters and event-driven discovery.
- Add automated Rust and QML validation, notifications and optional usage history.

The merged baseline preserves the previous backend and UI; the user's local build was reported working, but this repository bundle has not been compiled or tested with Quickshell in the packaging environment.
