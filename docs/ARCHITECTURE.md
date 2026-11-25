# aether.ai monorepo

Current structure:
```text
Cargo.toml              # workspace + shared core package
src/lib.rs              # aether_core: platform paths, discovery, Codex, cache
src/history.rs          # shared history
src/main.rs             # aether CLI / Linux daemon
shell/                  # existing Linux Quickshell frontend
systemd/                # existing Linux service and updater
apps/desktop/           # native Windows/macOS frontend, shared Rust code
  src/main.rs
  macos/Info.plist
scripts/                # update, integration tests, CI
.github/workflows/      # Linux + Windows + macOS builds
docs/
```
The root package remains the default workspace member so Linux install and update commands keep their output paths. Both frontends use the same quota logic and data schema. Desktop uses eframe/egui native rendering rather than a webview. It polls in process while open. Future work can extract a separate crates/core package and platform-specific native shells without splitting the repository. Windows tray/startup, macOS menu bar/launchd, native global shortcuts and signed distribution are not yet implemented. No fake parity claims.

## Website

`apps/web/` contains the static Vite product site, using the shared Wisp brand assets. Website CI is independent of the desktop release workflow. The site illustrates quota data and links to preview builds; it does not access local account state. See [website development and deployment](../apps/web/README.md).
