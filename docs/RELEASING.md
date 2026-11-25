# Release engineering

Pre-1.0 semantic versioning: patch for fixes, minor for features; 1.0 is the stable milestone. Current development version is 0.2.0. No release was published by adding this workflow.

## Gates

CI automatically runs only on version-tag pushes (`v*`), or manually through Actions → CI and releases → Run workflow. Normal branch pushes and pull requests do not start hosted CI. The separate Website checks workflow follows the same trigger policy. A manual application run builds and tests without drafting a release. Website checks are reviewed separately from the native release gate.

Application CI validates matching Cargo/QML versions, shell/Python syntax, Cargo tests and release build, isolated mock Codex quota/history/stale-cache behavior, and headless Sway/Quickshell startup and IPC. It produces source and Arch x86_64 binary archives, plus Windows and macOS preview ZIPs, with SHA256SUMS on releases. Tag-only release job additionally verifies ancestry on main, tag/version match and a nonempty dated changelog section before drafting the GitHub release. Maintainer publishes only after review and actual desktop smoke testing.

## Prepare a release

Prereleases use `v0.2.0-alpha.1`, `v0.2.0-beta.1` or `v0.2.0-rc.1` with an exact dated changelog heading such as `## [0.2.0-alpha.1] - YYYY-MM-DD`. Keep the shared Cargo/QML/macOS bundle version numeric (`0.2.0`). The workflow marks suffixed tags as GitHub prereleases; do not publish them as stable. Ordinary commits still do not trigger either workflow.

1. Choose the version (e.g. 0.3.0), update root Cargo.toml, QML version, apps/desktop/Cargo.toml and both macOS Info.plist version fields.
2. Move applicable Unreleased changes into a new dated heading: `## [0.3.0] - YYYY-MM-DD`. Preserve previous history.
3. Commit Cargo.lock (if not yet tracked), run relevant checks locally and merge reviewed changes. If desired, manually run application and website CI on the candidate commit before tagging. Do not configure skipped automatic PR checks as mandatory branch checks unless you intend to run them manually for every PR.
4. After local desktop testing, tag the main commit: `git tag -a v0.3.0 -m "aether.ai v0.3.0"`; `git push origin v0.3.0`.
5. Wait for the tag-triggered application build and website checks. Review both results, the generated draft, artifacts and checksums. Publish on GitHub only when satisfied. Stable updater sees published releases; Development follows main as before.

## Limitations

CI generates a lockfile if missing; commit it for reproducible dependencies. Signed release provenance, cargo fmt/clippy enforcement, dependency audit and real Hyprland visual interaction tests remain future gates. Headless Sway exercises startup and IPC, not visual fidelity. The native binary self-test validates embedded icon decoding and platform storage without opening a GUI. Failed Linux smoke logs are saved as a diagnostic artifact. The disposable Arch CI container removes Sway's file capabilities before launching it as an unprivileged user, avoiding Docker's capability-boundary execution failure. No change to the user's installed compositor is needed. Repository branch protection and required-check settings are managed separately in GitHub; review existing requirements after adopting release-only CI. Artifacts are Arch-targeted, not universal Linux installers; existing updater still builds from source. Windows x64, Apple Silicon and Intel macOS preview builds are now included as required jobs. macOS uses ad-hoc signing only; no notarization. Native desktop smoke testing on real machines remains required.
