# Release engineering

Linux / Wayland is the only active release target. Windows and macOS prototypes remain in source control but are not built, packaged or supported in new releases.

## Gates

Application and website CI run only on version-tag pushes (`v*`) or explicit manual dispatch. Normal commits, main pushes and pull requests do not consume hosted CI runner time.

A lightweight job validates release metadata, notes, ancestry and tracked Cargo.lock before Linux compilation. The Linux job checks shell/Python syntax, Rust tests and build, mock Codex quota/history/cache integration and headless Sway/Quickshell startup and IPC. The website workflow independently checks its production build and browser interactions.

The tag-triggered release job verifies the exact Linux archive checksums and creates a draft with:

- `aether-arch-linux-x86_64.tar.gz`
- `aether-source.tar.gz`
- `SHA256SUMS`

A manual application run builds and tests without drafting a release. Publish the draft only after review and Linux smoke testing. The binary archive targets Arch x86_64, not all Linux distributions.

## Prepare a release

1. Choose the shared numeric version (e.g. 0.3.0). Update root Cargo.toml and the QML version only; dormant desktop metadata does not gate Linux releases.
2. Add an exact dated changelog heading, such as `## [0.2.0-alpha.2] - YYYY-MM-DD`. Preserve earlier release notes.
3. If dependencies change, run `cargo generate-lockfile` and commit Cargo.lock.
4. Run the lightweight checks locally:
   ```bash
   uv run --python 3.12 scripts/test_release_check.py
   uv run --python 3.12 scripts/release_check.py --tag v0.2.0-alpha.2
   cargo test --locked
   ```
5. Push the reviewed commit to main. Only when ready, create and push the new release tag:
   ```bash
   git tag -a v0.2.0-alpha.2 -m "aether.ai v0.2.0-alpha.2"
   git push origin v0.2.0-alpha.2
   ```
6. Review CI and the generated GitHub draft. Suffixes alpha.N, beta.N and rc.N are automatically marked as prereleases. Stable releases have numeric tags without suffixes. Do not mark alpha builds as stable.

The Stable Linux updater follows published non-prereleases; Development follows main. Existing alpha.1 binaries are historical. Do not move an existing tag or silently replace published assets.

## Limitations

Headless Sway exercises startup and IPC rather than visual fidelity. Actual Hyprland smoke testing, signed provenance, dependency auditing and reproducible release builds remain future work. Failed Linux smoke logs remain available as CI diagnostics. The disposable Arch CI container removes Sway file capabilities only inside the runner to avoid Docker capability-boundary failures.

Native desktop and DMG packaging source is retained but dormant. Before resuming macOS distribution, implement Developer ID signing, notarization and updater publisher-identity verification. Before resuming Windows distribution, review signing and test on real devices.
