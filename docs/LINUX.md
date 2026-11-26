# Install and use Aether on Linux

[Project home](../README.md)

Follow the phases in order. Arch Linux on Wayland with Hyprland is the primary tested setup. Run Aether's installer as your desktop user. Use `sudo` only for system packages.

## Phase 1: prerequisites

You need a working Wayland session, Quickshell with Qt 6.8 or newer, a Rust toolchain, Git, Bash, Python 3.12 or newer, `flock`, and a systemd user manager. Caelestia is optional.

On Arch Linux:

```bash
sudo pacman -Syu --needed base-devel git curl python util-linux quickshell imagemagick fontconfig
```

ImageMagick converts optional provider artwork. Fontconfig refreshes optional downloaded fonts. You can omit both packages if you omit the asset-fetch flags in Phase 3.

Check your Rust installation:

```bash
cargo --version
rustc --version
```

If those commands work, keep your existing toolchain. If Rust is missing, install the Arch package:

```bash
sudo pacman -S --needed rust
```

Check the remaining tools:

```bash
qs --version
python3 --version
flock --version
systemctl --user show-environment >/dev/null
```

The last command must complete without a user-manager connection error.

Add user-installed binaries to your PATH. For Bash, run this once, then open a new terminal:

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

For Fish, use this command instead:

```fish
fish_add_path ~/.local/bin
```

Other distributions need equivalent packages and a compatible Quickshell build. Aether's published Arch binaries are not generic Linux binaries.

## Phase 2: provider signup and Codex setup

Codex is the implemented quota provider. Create or sign in to your [ChatGPT account](https://chatgpt.com/), and check the [Codex access included with your plan](https://help.openai.com/en/articles/11369540-codex-in-chatgpt). Aether shows subscription quota rather than API-key billing.

If Codex is already installed, keep it and continue to the version and login checks. Otherwise, use the [official Codex CLI installer](https://github.com/openai/codex#installing-and-running-codex-cli):

```bash
codex_install_script="$(mktemp)"
curl -fsSL https://chatgpt.com/codex/install.sh -o "$codex_install_script"
sh "$codex_install_script"
rm "$codex_install_script"
```

The official installer places the executable in `~/.local/bin` by default. Phase 1 makes that directory available in your terminal.

```bash
codex --version
codex login
codex login status
```

Complete the browser's ChatGPT sign-in, then confirm the login-status command succeeds. If the browser callback is unavailable, Codex also provides `codex login --device-auth`. See [Codex authentication](https://developers.openai.com/codex/auth).

Claude Code, Grok, OpenCode, Pi, OpenRouter, AgentRouter, FreeGG, and DeepSeek adapters are planned. You do not need accounts with those providers to install Aether, and signing up does not enable an unfinished adapter.

## Phase 3: install Aether and enable startup

```bash
git clone https://github.com/maynkudu/aether-ai.git
cd aether-ai
bash install.sh --fetch-icons --fetch-fonts
```

Use `bash install.sh` if you want to skip optional artwork and font downloads. Aether uses installed fonts and provider initials when downloaded assets are unavailable.

The installer builds the Rust backend, installs the QML interface and updater, and configures user services:

| Unit | Purpose | Automatic startup |
|---|---|---|
| `aether.service` | Poll Codex quota and record history every three minutes. | User-manager startup. With lingering, this includes boot before login. |
| `aether-ui.service` | Run the Quickshell drawer and control centre. | The graphical session, after a Wayland display is available. |
| `aether-update.timer` | Run the updater's automatic action periodically. | User-manager startup. Automatic downloads and installation require opt-in in Aether. |

The UI service stops an older manually launched Aether instance before it starts. Remove an old `exec-once = qs -c aether` entry so systemd owns one instance.

To run the quota daemon at boot before you log in:

```bash
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

Expect `Linger=yes`. This keeps your user manager running after logout. The graphical interface still starts only when you have a Wayland session.

Verify installation:

```bash
systemctl --user is-enabled aether.service aether-ui.service aether-update.timer
systemctl --user status aether.service aether-ui.service --no-pager
aether version
aether accounts
aether usage
```

Both services should be active when you install from your Wayland desktop. An installation from a text console or SSH enables the UI for the next graphical session.

### Compositors without systemd session integration

A session manager such as UWSM exports the Wayland environment and starts `graphical-session.target`. On a manually started compositor, add a startup command that imports the session environment and starts Aether's UI service.

For legacy Hyprland configuration:

```ini
exec-once = sh -c 'systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user restart aether-ui.service'
```

For Hyprland's Lua configuration, add this to your existing startup callback:

```lua
hl.exec_cmd("sh -c 'systemctl --user import-environment WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE; systemctl --user restart aether-ui.service'")
```

Keep your current session manager if it already handles startup. Aether's installer does not edit compositor configuration.

## Phase 4: usage

Hover over the top-right corner to open the quota drawer. Use **Settings** to open the control centre. **Behaviour** changes the activation position, hover behavior, and dismissal delay. The drawer stays above other shell surfaces and applications, including full-screen clients.

Open the control centre from a terminal:

```bash
qs -c aether ipc call dashboard settings
```

Other interface commands:

```bash
qs -c aether ipc call dashboard toggle
qs -c aether ipc call dashboard analytics
qs -c aether ipc call dashboard refresh
qs -c aether ipc call dashboard shortcuts
qs -c aether ipc call dashboard dismiss
```

The drawer's **Refresh**, Ctrl+R, and the `refresh` IPC command reread the local cache. They do not query the provider. The backend service collects quota independently every three minutes, and history starts with successful local observations.

Read local data:

```bash
aether accounts
aether usage
aether history 7
aether version
```

For a manual provider request, pause the daemon first and restart it afterward so two pollers do not compete:

```bash
systemctl --user stop aether.service
aether refresh
systemctl --user start aether.service
```

### Keyboard shortcuts

The **Shortcuts** tab generates compositor bindings and detects duplicates among Aether's bindings. Check for conflicts before adding them to your own configuration.

Legacy Hyprland:

```ini
bind = SUPER, U, exec, qs -c aether ipc call dashboard toggle
bind = SUPER SHIFT, U, exec, qs -c aether ipc call dashboard settings
bind = SUPER ALT, U, exec, qs -c aether ipc call dashboard analytics
```

Hyprland Lua:

```lua
hl.bind("SUPER + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard toggle"))
hl.bind("SUPER + SHIFT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard settings"))
hl.bind("SUPER + ALT + U", hl.dsp.exec_cmd("qs -c aether ipc call dashboard analytics"))
```

Inside the control centre, Ctrl+1 through Ctrl+8 select pages, Ctrl+R rereads the cache, and Escape dismisses the panels. See [configuration](CONFIGURATION.md) for themes, motion, fonts, and account discovery.

### Service controls and logs

```bash
systemctl --user restart aether.service
systemctl --user restart aether-ui.service
systemctl --user stop aether-ui.service
systemctl --user start aether-ui.service
journalctl --user -u aether.service -n 50 --no-pager
journalctl --user -u aether-ui.service -n 50 --no-pager
systemctl --user list-timers aether-update.timer --no-pager
```

Stopping the UI leaves quota collection running. Stop `aether.service` as well if you want to pause collection.

## Updates and rollback

From your source checkout:

```bash
git pull --ff-only
bash install.sh
```

The installer restarts the backend and, when run from Wayland, the UI service. It does not need a separate manual `qs` launch.

For QML and service updates without a Rust build, use an existing full installation:

```bash
bash install.sh --ui-only
```

Fetch missing assets with `bash install.sh --ui-only --fetch-icons --fetch-fonts`. UI-only installation does not advance the full-build commit receipt.

The updater requires one full installation from a clean tracked checkout to record its starting commit. A locally edited checkout still installs, but does not initialize or advance that receipt.

```bash
aether-update status
aether-update check development
aether-update apply development
aether-update rollback
```

Stable follows published, non-prerelease `vMAJOR.MINOR.PATCH` releases. Development follows `main`. The updater rejects downgrades and divergent commits, builds in an isolated directory, keeps a previous build, and restarts an active UI service. Older rollback archives retain the current UI service definition because those archives did not contain it.

Automatic installation is opt-in in **Updates**. The enabled timer invokes `aether-update auto` approximately every six hours; that action exits without a network check while automatic updates are disabled. Disable the timer with:

```bash
systemctl --user disable --now aether-update.timer
```

The historical Arch alpha archive predates this service setup and does not contain the complete source installer. Use the source installation above for these instructions.

## Troubleshooting

| Symptom | Check |
|---|---|
| `cargo` or `rustc` is missing | Complete the Rust step in Phase 1. Keep an existing working rustup toolchain. |
| `codex` or `aether` is missing | Complete the PATH step, then open a new terminal. |
| No accounts | Run `codex login status` and `aether accounts`. Additional Codex homes need explicit discovery settings. |
| Stale cache | Inspect `aether.service` status and its journal. The daemon must be able to find the native Codex executable. |
| UI is enabled but not running | Check for a Wayland session and systemd session integration. Use the compositor startup fallback when needed. |
| QML fails to load | Read `journalctl --user -u aether-ui.service -n 50 --no-pager` for the first error, then update and reinstall. |
| Two UI instances | Remove an old direct `qs` autostart command and restart `aether-ui.service`. |
| Artwork is missing | Install ImageMagick, then rerun the icon-fetch flag. Failed downloads fall back to initials. |
| Caelestia is unavailable | Check the standard `qs -c caelestia` instance and its palette. Caelestia is optional. |

If Codex is installed through a shell version manager, give the daemon an absolute executable path. Run `command -v codex`, then use that result in a service override:

```bash
systemctl --user edit aether.service
```

```ini
[Service]
Environment="AETHER_CODEX_BIN=/absolute/path/to/codex"
```

```bash
systemctl --user restart aether.service
```

For extra Codex homes and T3 discovery settings, see [account discovery](CONFIGURATION.md#account-discovery).

For reports, include the OS, architecture, `qs --version`, `hyprctl version`, `aether version`, and the first relevant error. Redact account names, private paths, and credentials.

## Removal

Disable the interface, daemon, and updater timer:

```bash
systemctl --user disable --now aether-ui.service aether.service aether-update.timer
```

Remove Aether-specific compositor startup commands and bindings. Remove the installed binaries, unit files, and QML file while keeping preferences and history:

```bash
aether_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
rm -f ~/.local/bin/aether ~/.local/bin/aether-update
rm -f "$aether_config_dir/systemd/user/aether.service" \
  "$aether_config_dir/systemd/user/aether-ui.service" \
  "$aether_config_dir/systemd/user/aether-update.service" \
  "$aether_config_dir/systemd/user/aether-update.timer"
rm -f "$aether_config_dir/quickshell/aether/shell.qml"
systemctl --user daemon-reload
```

Preferences, cache, history, and downloaded fonts are separate user data. Keep them if you plan to reinstall. Do not remove Codex credentials or Caelestia directories. Lingering is shared by all your user services; leave it enabled if any of them need to run before login.
