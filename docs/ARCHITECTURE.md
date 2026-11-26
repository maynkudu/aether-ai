# aether.ai architecture

Linux / Wayland is the only active application target.

```text
Cargo.toml              # Rust package and workspace
src/lib.rs              # account discovery, Codex, cache
src/history.rs          # local history
src/main.rs             # CLI / Linux daemon
shell/                  # Linux Quickshell frontend
systemd/                # Linux user service and updater
scripts/                # update, tests and packaging
.github/workflows/      # Linux release checks
docs/
```

The root package is the only workspace member. The Linux installer and updater keep their existing output paths.
