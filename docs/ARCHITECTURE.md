# aether.ai monorepo

Linux / Wayland is the only active application target.

```text
Cargo.toml              # workspace + Rust core, root is default
src/lib.rs              # account discovery, Codex, cache
src/history.rs          # local history
src/main.rs             # CLI / Linux daemon
shell/                  # Linux Quickshell frontend
systemd/                # Linux user service and updater
apps/web/               # static product site
apps/desktop/           # paused native Windows/macOS prototype
scripts/                # update, tests and packaging
.github/workflows/      # Linux release and website checks
docs/
```

The root package remains the default workspace member. The existing desktop prototype and shared portability code are retained for possible future work; the Linux release validator does not require desktop bundle version changes, and CI does not build those targets. The Linux installer and updater keep their existing output paths.

## Website

The static Vite site uses the shared Wisp assets, illustrates quota data and documents Linux installation. It does not access local account state. Website CI is separate from Linux releases. See [website development and deployment](../apps/web/README.md).
