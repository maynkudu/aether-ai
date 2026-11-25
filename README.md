# aether.ai

**Intelligence, within limits.**

A local-first AI quota monitor for Linux. Rust backend, independent Quickshell/QML overlay, experimental T3 Code account discovery, and Caelestia-aware theming. No inference proxy or telemetry.

## Current state

Experimental v0.2.0. Codex is the only implemented quota provider; Claude, Grok, OpenCode and Pi are planned. The UI does not modify Caelestia or T3 Code. Native managed T3 authentication is not implemented. Licensed under MIT; third-party brand assets remain subject to their own terms.

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

## Control centre

The centred settings window now has a sidebar, provider artwork, per-provider and per-account visibility, appearance and behaviour controls, and project links. Analytics draws real local quota snapshots as lines or bars across 24 hours, 7, 30 or 90 days. History starts with the new daemon; previous T3 token/cost history is not imported yet. Visibility does not change T3 configuration or stop polling. History is kept locally in XDG_STATE_HOME/aether/history (default ~/.local/state/aether/history) for about 92 days. Rebuild the backend and restart its user service for this release.

### Appearance and typography

Mono is the default colour scheme. Mono Light, Midnight, Lavender, Forest, Ember, Paper and dynamic Caelestia are available in Appearance. Provider groups have nested account status and quota rows. Codex uses the original OpenAI Blossom in black or white, not the old square app icon.

Run `bash install.sh --ui-only --fetch-icons --fetch-fonts` to download brand assets and the curated OFL font pack. Fonts install in `$XDG_DATA_HOME/fonts/aether-ai` (default `~/.local/share/fonts/aether-ai`), with each upstream OFL license; no sudo needed. Restart the shell to see newly installed font families. Font and asset downloads are optional and do not occur at runtime. Missing assets/fonts are handled explicitly.


### Scroll fades and shortcuts

Appearance includes toggleable scroll-edge fades and a 12–48 px fade depth. Fades follow the viewport's scroll distance, disappear at its ends, and stay off for non-overflowing content.

The Shortcuts tab offers editable Hyprland modifiers/keys, duplicate detection within aether's generated bindings, and copyable legacy configuration or Lua. The defaults are Super+U (drawer), Super+Shift+U (control centre), and Super+Alt+U (analytics). Cache refresh and dismiss are optional actions, disabled in the generated defaults. Add the generated bindings to your personal Hyprland config, replacing older aether bindings, then reload. Aether never edits compositor configuration; preference changes do not remove previously installed compositor binds.

Legacy Hyprland:
```ini
bind = SUPER, U, exec, qs -c aether ipc call dashboard toggle
bind = SUPER SHIFT, U, exec, qs -c aether ipc call dashboard settings
bind = SUPER ALT, U, exec, qs -c aether ipc call dashboard analytics
```

Lua Hyprland:
```lua
hl.bind("SUPER + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard toggle"))
hl.bind("SUPER + SHIFT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard settings"))
hl.bind("SUPER + ALT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard analytics"))
```

IPC also supports `dashboard refresh`, `dashboard dismiss`, and `dashboard shortcuts`. Refresh reads the existing cache/history, not provider APIs. Within the focused control centre, Ctrl+1 through Ctrl+8 navigate the sidebar; Ctrl+R refreshes the view and Escape dismisses it. These local shortcuts may be disabled in Settings.

### Platforms

The current implementation targets Linux on Wayland, primarily Hyprland. The QML frontend uses Quickshell's Wayland layer-shell APIs, and the service installer uses systemd. The Rust backend also uses Unix file permissions and Linux-oriented discovery paths. macOS and Windows are not supported by this release; a native port requires a platform-specific window/hotkey implementation, service and filesystem adapters. The portable quota and analytics logic can be shared rather than rewriting it. No Caelestia requirement.

### Automatic updates

Run a full install from a clean Git checkout once. The installer installs the user-local updater and systemd timer, and records the installed commit. The timer is enabled but does no network work until **Updates → Automatically install updates** is enabled. Stable is the default channel; it follows the latest published non-prerelease GitHub release with a vMAJOR.MINOR.PATCH tag. Development follows main commits. Until the first release exists, Stable reports that there is no release. The updater uses only the official repository, an isolated bare Git cache and temporary build directory; it never modifies the developer checkout or credentials. Updates must be descendants of the installed commit. It builds before replacing the binary, shell and unit files, restarts the quota daemon and restores prior files on installation errors. Quickshell may reload its configuration; if not, restart it manually. Runtime QML validity is not automatically proven by the build, so Development is opt-in.

Manual commands: `aether-update status`, `aether-update check development`, `aether-update apply development`, `aether-update rollback`. One previous build is retained locally for rollback; the rolled-back commit is excluded from automatic reinstall until a newer commit arrives or an explicit installation is requested. Installation launched from the UI is detached so QML reload does not kill the updater. Disable the timer with `systemctl --user disable --now aether-update.timer` if desired. A full manual reinstall re-enables the timer, but the automatic-install preference remains authoritative. Manual UI-only installs do not advance the full-build receipt. The updater needs Python 3.12+, Git, Cargo, systemd and network access. Third-party artwork and fonts are not downloaded during updates.

### Liquid motion

Appearance → Motion offers Liquid (default), Smooth and Reduced. Inspired by Modulo's interruptible analytic springs, the drawer and settings window grow with separate shell/content layers; the sidebar has a moving selection capsule; buttons, switches and slider thumbs have spring-driven motion. Qt Quick FrameAnimation ticks only while spring values are moving. The UI retains native QML, and text and icon geometry remain unscaled. This is an adaptation of the design principles, not an embedded web library. Reduced disables the new spring transitions; some existing colour and quota transitions may remain. See `https://modulo.maynkudu.com/components/liquid-animations` for the original design reference.

### Fluid UI refinement

All ordinary settings selectors use one native liquid-styled ComboBox (including fonts, palettes, layout, motion mode, shortcut modifiers/keys and update channels). Analytics view switches remain quick-access controls. Default motion is 1100 ms (previous exact default 820 ms migrates once; custom durations are retained). The drawer grows from the selected corner/edge toward the screen, without resizing its content layout. Settings pages reveal left-to-right with staggered sections and a progressive title reveal. Smooth mode uses more heavily damped springs. Reduced remains available.

Providers are grouped as first-party agents, harnesses/routing platforms, aggregators and other providers. OpenRouter is grouped with harness/routing tools for convenience, not described as an agent harness. FreeGG uses AgentRouter's artwork at the maintainer's request; account identity and visibility remain separate. GitHub uses its official Octicons mark; see brand sources.

#### Glass materials

See the Liquid Glass setup below for the optional refractive compositor integration. Frosted Glass continues to use ordinary compositor blur for `aether-drawer` and `aether-settings`.

### Liquid dropdowns, slower reveals and surface materials

All selectors use a shared native ComboBox with the original Feather chevron, pointer and keyboard highlights, and independently clipped top-left-to-bottom-right popup growth. Palette selection uses a two-column swatch grid when room permits. Fonts render in their actual families. Page content reveals more slowly than the previous version. The GitHub and shortcut controls have persistent tonal surfaces and borders.

Choose **Appearance → Surface material**: Solid (default), Frosted Glass (existing compositor-blur material), or Liquid Glass (real compositor refraction). Previous glass preference migrates to Frosted, not Liquid. Liquid uses a compatible [HyprGlass](https://github.com/hyprnux/hyprglass) plugin with its live contour layer renderer. It samples the actual desktop framebuffer behind the app rather than screenshots or a simulated blur. It is optional and never installed automatically. The app checks `hyprctl -j hyprglass status` for an active layer renderer; if unavailable, it renders Solid. The status cannot prove the per-namespace configuration is correct. The UI offers a copyable Lua preset, adjustable tint, refraction, chromatic dispersion and lens height. The optical sliders update the generated Lua; apply that preset and reload the compositor for the optical changes to take effect. Merge this preset into your existing plugin configuration; use `hyprctl layers` to confirm namespace names and `hyprctl configerrors` to check your config. Use compatible plugin releases and never bypass ABI checks. Newer contour/lens options require recent HyprGlass releases. Legacy Hyprland configurations need the corresponding version's plugin syntax. No compositor files are modified. The `aether-liquid-drawer` and `aether-liquid-settings` namespaces are separate from normal/frosted layers. Restart aether when switching into or out of Liquid, because a layer-shell namespace cannot be changed after connection. This integration requires local compositor testing; neither optical quality nor GPU performance is verified here.

## Development and releases

See [release engineering](docs/RELEASING.md) and [cross-platform architecture](docs/ARCHITECTURE.md). CI runs on main, pull requests and version tags. A stable release is drafted only after checks succeed, then published manually. Windows and macOS experimental artifacts are built by the native CI matrix; see the desktop preview guide.

Caelestia requires an active standard `qs -c caelestia` instance and a valid scheme; Liquid Glass requires a compatible active HyprGlass layer renderer. Both are visibly disabled when unavailable, with tooltips and setup guidance. The renderer check does not prove the layer whitelist is correct. Upward dropdowns grow from bottom-left and downward ones from top-left.

## Windows and macOS preview

The repository is now a Cargo workspace with shared `aether_core` and a native desktop application in [apps/desktop](apps/desktop/README.md). Windows x64, Apple Silicon and Intel macOS CI produce experimental ZIP artifacts. Download them only from successful builds. The existing Linux installer, Quickshell configuration and updater paths remain unchanged. These ports currently provide Codex quota polling, history charts, account visibility and two monochrome themes; they do not yet offer Linux feature parity, native installers or global desktop integration.
