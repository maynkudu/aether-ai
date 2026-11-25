# Release engineering

Pre-1.0 semantic versioning: patch for fixes, minor for features; 1.0 is the stable milestone. Current development version is 0.2.0. No release was published by adding this workflow.

## Gates

CI on main, PRs and tags validates matching Cargo/QML versions, shell/Python syntax, Cargo tests and release build, isolated mock Codex quota/history/stale-cache behavior, and headless Sway/Quickshell startup and IPC. It produces source and Arch x86_64 binary archives with SHA256SUMS. Tag-only release job additionally verifies ancestry on main, tag/version match and a nonempty dated changelog section before drafting the GitHub release. Maintainer publishes only after review and actual desktop smoke testing.

## Prepare a release

1. Choose the version (e.g. 0.3.0), update Cargo.toml and QML version.
2. Move applicable Unreleased changes into a new dated heading: `## [0.3.0] - YYYY-MM-DD`. Preserve previous history.
3. Commit Cargo.lock (if not yet tracked), run checks, merge via reviewed PR. Protect main with the required Linux build and smoke check in GitHub settings.
4. After CI and manual Arch/Hyprland test, tag the tested main commit: `git tag -a v0.3.0 -m "aether.ai v0.3.0"`; `git push origin v0.3.0`.
5. Review the generated draft, artifacts and checksums. Publish on GitHub only when satisfied. Stable updater sees published releases; Development follows main as before.

## Limitations

CI generates a lockfile if missing; commit it for reproducible dependencies. Signed release provenance, cargo fmt/clippy enforcement, dependency audit and real Hyprland/HyprGlass visual interaction tests remain future gates. Headless Sway is not a Hyprland optics test. The workflow needs a first successful run and branch protection must be enabled manually. Artifacts are Arch-targeted, not universal Linux installers; existing updater still builds from source. macOS/Windows jobs come with actual ports.
