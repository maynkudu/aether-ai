# One repository, multiple desktops

Keep the current Linux layout (`src/`, `shell/`, `systemd/`, `scripts/`) intact until platform work begins. The planned Cargo workspace is:

```text
crates/
  aether-core/       # account and quota models, analytics
  aether-providers/  # reusable provider adapters
  aether-platform/   # path, credential discovery and permissions traits
apps/
  linux/             # Quickshell, layer shell, systemd
  macos/             # native window, menu bar, hotkeys, launchd
  windows/           # native window, tray, hotkeys, startup
design/              # shared tokens, motion and brand provenance
docs/
.github/workflows/
```

These are proposed boundaries, not shipped platforms. Core currently uses Unix file permissions and Linux discovery paths. Extract and test portable interfaces before moving code. Keep existing installer/updater paths until migration support exists. Share semantic versions and release tags; build platform-specific assets on native runners once supported. No fake Windows/macOS CI jobs. Glass rendering stays compositor-specific.
