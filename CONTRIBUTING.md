# Contributing

Welcome! Linux / Wayland fixes, provider adapters, documentation and compositor testing are appreciated.

1. Open an issue for substantial changes.
2. Fork, create a descriptive branch, and keep changes focused.
3. Preserve existing Linux installation paths and local data compatibility.
4. Run relevant tests; update Unreleased changelog; include testing evidence in the PR.
5. For UI changes include redacted screenshots/recordings and platform details.

```bash
cargo test -p aether-ai
cargo build --release -p aether-ai
python3 scripts/test_backend.py target/release/aether
python3 scripts/release_check.py
bash -n install.sh
bash -n shell/install.sh
```

Use `--locked` once Cargo.lock is committed. Linux UI: `bash install.sh --ui-only` and restart aether. CI runs automatically on version tags only, or manually from Actions. It covers headless Quickshell builds; real interaction tests need an active desktop.

## Principles

- Local-first, no telemetry or inference proxy.
- Real quota data; explicit unavailable states.
- Native rendering, legible contrast, reduced-motion support.
- Independent provider adapters and credential-free tests.
- No silent modifications to compositor/provider configuration.
- Document provenance and licensing for third-party assets.

Use conventional commit messages where practical. See [release engineering](docs/RELEASING.md). Contributions are licensed under MIT. Be constructive and respectful.

Never include credentials, raw T3 settings or unredacted private cache/history. For security-sensitive reports, follow [SECURITY.md](SECURITY.md).
