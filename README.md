# aether.ai

<p align="center"><strong>See your Codex session and weekly quota on your Linux desktop.</strong><br>
A local monitor with a top-right quota drawer, account view, and private usage history.</p>

<div align="center">

[![CI and releases](https://github.com/maynkudu/aether-ai/actions/workflows/ci.yml/badge.svg)](https://github.com/maynkudu/aether-ai/actions/workflows/ci.yml)
[![MIT](https://img.shields.io/badge/license-MIT-informational)](LICENSE)
[![Stars](https://img.shields.io/github/stars/maynkudu/aether-ai)](https://github.com/maynkudu/aether-ai/stargazers)
[![Status](https://img.shields.io/badge/status-early%20development-lightgrey)](CHANGELOG.md)
[![Linux / Wayland](https://img.shields.io/badge/platform-Linux%20%2F%20Wayland-252525)](#platform)

[Quick start](#quick-start) · [Features](#features) · [Provider support](#provider-support) · [Documentation](#documentation) · [Contribute](#contributing)

</div>

Track remaining Codex quota across local accounts, see session and weekly reset times, and review up to 90 days of locally recorded history. Aether runs on Linux / Wayland with a Rust daemon and Quickshell interface. It sends no telemetry and does not proxy inference requests.

> [!NOTE]
> **Early development (v0.2.0).** Linux / Wayland is the only supported target. Arch Linux x86_64 and Hyprland are the primary tested setup. Codex is the only implemented quota adapter. Claude Code, Grok, and other providers are planned. Windows and macOS prototypes are paused. No stable GitHub release is available yet.

## The current Linux interface

<img src="docs/assets/interface.svg" alt="Illustration of aether control centre, quota cards, circular drawer and history" width="100%">

The top-right drawer keeps quotas in view. The control centre holds account settings and local history. This illustration uses sample data, not a live screenshot.

## Features

| | |
|---|---|
| **At-a-glance quotas** — Session and weekly limits, reset information, grid cards and circular gauges. | **Multiple accounts** — Local Codex homes, experimental T3 discovery and independent visibility. |
| **Local analytics** — Real recorded quota history, line and bar views, 24h–90d ranges. | **Fluid interactions** — Subtle, interruptible transitions, reduced motion, directional dropdowns and scroll fades. |
| **Personal by design** — Wisp, eight palettes, curated typefaces, configurable hotspots and shortcuts. | **Stay current** — Linux opt-in updates, Stable/Development channels and previous-build rollback. |

### Appearance

<img src="docs/assets/palettes.svg" alt="Seven built-in colour schemes and dynamic Caelestia palette" width="100%">

Linux supports Liquid, Smooth and Reduced motion, with opaque theme-aware surfaces and adjustable trackpad speed. Caelestia is optional and disabled when its prerequisites are missing. See [configuration](docs/CONFIGURATION.md).

## Meet Wisp

<img src="docs/assets/branding/wisp-light.svg" width="76" align="right" alt="Wisp, the aether.ai mascot">

Wisp is Aether's mascot. The product name remains **aether.ai**. Linux supports optional animation and reduced motion.

[Brand assets and motion guide](docs/BRANDING.md) · [Animated Wisp SVG](docs/assets/branding/wisp-animated-light.svg)

## Platform

Aether is actively developed and distributed for **Linux / Wayland**. Arch Linux (x86_64) is the tested binary target; Hyprland is the primary compositor. Other compatible Wayland setups may work from source but are not guaranteed.

The Rust daemon runs independently of the Quickshell interface. Windows and macOS ports are preserved in the repository for future development, but are not currently supported, built or distributed in new releases.

### Provider support

| Group | Provider | Quota adapter |
|---|---|---|
| First-party agents | OpenAI Codex | Implemented |
| First-party agents | Claude Code, Grok | Planned |
| Harnesses / routing | OpenCode, Pi, OpenRouter | Planned |
| Aggregators | AgentRouter, FreeGG | Planned |
| Other providers | DeepSeek | Planned |

Artwork and provider visibility entries do not imply working quota integrations. See [account discovery](docs/CONFIGURATION.md#account-discovery).

## Quick start

Follow these phases on Arch Linux with a working Wayland session. Hyprland is the primary compositor. The [full Linux guide](docs/LINUX.md) includes compositor startup, service controls, logs, updates, and removal.

### Phase 1: prerequisites

```bash
sudo pacman -Syu --needed base-devel git curl python util-linux quickshell imagemagick fontconfig
cargo --version
rustc --version
```

If Rust is missing, run `sudo pacman -S --needed rust`. Keep an existing working toolchain. Quickshell needs Qt 6.8 or newer, Python must be 3.12 or newer, and systemd user services must be available. ImageMagick and fontconfig support optional asset downloads. Caelestia is optional.

For Bash, add the binary directory to this terminal and future terminals:

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

Fish users should run `fish_add_path ~/.local/bin` instead.

### Phase 2: provider signup and Codex

Create or sign in to your [ChatGPT account](https://chatgpt.com/). Check [Codex access for your plan](https://help.openai.com/en/articles/11369540-codex-in-chatgpt). If Codex is not installed, use its [official installer](https://github.com/openai/codex#installing-and-running-codex-cli):

```bash
codex_install_script="$(mktemp)"
curl -fsSL https://chatgpt.com/codex/install.sh -o "$codex_install_script"
sh "$codex_install_script"
rm "$codex_install_script"
```

Verify Codex and complete its ChatGPT sign-in:

```bash
codex --version
codex login
codex login status
```

Codex is the working quota adapter. Other providers remain planned; their accounts are not prerequisites for Aether.

### Phase 3: install Aether

Run as your desktop user, without sudo:

```bash
git clone https://github.com/maynkudu/aether-ai.git
cd aether-ai
bash install.sh --fetch-icons --fetch-fonts
loginctl enable-linger "$USER"
systemctl --user status aether.service aether-ui.service --no-pager
```

The installer enables the quota daemon and a separate graphical-session service. Lingering starts the daemon at boot before login. The interface starts when your Wayland session is available. No manual `qs` launch is needed on a managed graphical session. For a manually started compositor, follow the [startup integration instructions](docs/LINUX.md#compositors-without-systemd-session-integration).

Use `bash install.sh` to skip optional artwork and font downloads. [Installation details](docs/LINUX.md#phase-3-install-aether-and-enable-startup).

### Phase 4: usage

Hover over the top-right corner to open the drawer, then select Settings. You can also open the control centre from a terminal:

```bash
qs -c aether ipc call dashboard settings
aether accounts
aether usage
```

Refresh beside Settings and Ctrl+R reread the cache. The daemon queries quota every three minutes. The drawer remains available over other windows, including full-screen apps. See [usage and service commands](docs/LINUX.md#phase-4-usage).

### Release downloads

The historical Linux alpha archive is available [here](https://github.com/maynkudu/aether-ai/releases/download/v0.2.0-alpha.1/aether-arch-linux-x86_64.tar.gz). The archive is Arch x86_64-specific and predates this service setup. Use the source installation above for the complete current installer. Historical cross-platform preview assets are unsupported.

## CLI

```bash
aether accounts       # discovered account homes
aether usage          # cached quota JSON
aether history 7      # seven days of local history
aether version
```

`aether refresh` performs a provider probe. Stop the daemon before a manual probe and start it afterward, as shown in the [Linux guide](docs/LINUX.md#phase-4-usage). Fish users can run `fish_add_path ~/.local/bin` if the CLI is not found.

## Updates & releases

| Channel | Tracks |
|---|---|
| Stable | Published, non-prerelease GitHub releases |
| Development | Commits on main |

On Linux, automatic installation is opt-in. Until the first stable release exists, choose Development for testing. Updates build from isolated upstream sources rather than modifying your checkout.

```bash
aether-update check development
aether-update apply development
aether-update rollback
```

See [updates and rollback](docs/LINUX.md#updates-and-rollback) and [release engineering](docs/RELEASING.md). CI automatically validates Linux builds on version-tag pushes before drafting a release for manual review. Website checks also run on version tags. Both workflows can be started manually; ordinary pushes and pull requests do not trigger them.

## Architecture

<img src="docs/assets/architecture.svg" alt="Shared Rust quota core with the supported Linux app and paused Windows and macOS prototypes" width="100%">

Linux is the only supported and distributed app today. The Windows and macOS frontends in this diagram are paused prototypes. The Linux installer and cache format retain their existing layout.

[Explore the architecture →](docs/ARCHITECTURE.md)

## Privacy & security

aether queries the native Codex app-server and reads local account configuration. It does not forward inference requests, upload quota history or collect telemetry. Codex may refresh its own authentication. Local caches contain account names, paths and quota percentages; treat them as private. Optional assets and update checks contact upstream services.

See [security policy](SECURITY.md) and [local data](docs/CONFIGURATION.md#local-data).

## Documentation

| Guide | Contents |
|---|---|
| [Linux installation](docs/LINUX.md) | Setup, systemd, IPC, shortcuts, updates and troubleshooting |
| [Configuration](docs/CONFIGURATION.md) | Themes, fonts, motion, scrolling, discovery and storage |
| [Architecture](docs/ARCHITECTURE.md) | Workspace structure and shared interfaces |
| [Release engineering](docs/RELEASING.md) | CI gates, versioning, builds and publication |
| [Changelog](CHANGELOG.md) | Development and release history |
| [Wisp branding](docs/BRANDING.md) | Mascot, vector assets and motion |
| [Brand assets](shell/BRAND-ASSETS.md) | Artwork provenance and third-party licenses |

## Roadmap

- [ ] Expand quota adapters beyond Codex; validate managed T3 credentials.
- [ ] Refine the Linux drawer, settings and compositor integration.
- [ ] Add signed distribution, dependency auditing and reproducible release builds.
- [ ] Validate scroll interaction and reduced-motion behaviour.

## Contributing

Focused improvements, bug reports and provider adapters are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md). For visual feedback, include OS, compositor and a redacted screenshot or recording. Never attach credentials or private cache files.

[Report a bug](https://github.com/maynkudu/aether-ai/issues/new?template=bug_report.yml) · [Request a feature](https://github.com/maynkudu/aether-ai/issues/new?template=feature_request.yml)

## License & acknowledgements

MIT © [maynkudu](https://github.com/maynkudu). See [LICENSE](LICENSE).

Built with [Rust](https://www.rust-lang.org/), [Quickshell](https://quickshell.org/) and [Qt Quick](https://www.qt.io/). Motion inspired by [Modulo](https://modulo.maynkudu.com/components/liquid-animations). Provider trademarks and third-party artwork retain their respective ownership and terms.

<div align="center">

**Intelligence, within limits.**

</div>
