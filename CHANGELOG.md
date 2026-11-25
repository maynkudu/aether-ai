# Changelog

## UI v6 — Customisation

- Added a persisted Grid / Rings layout selector, split session and weekly quota arcs, percentages and reset labels. Unknown quotas remain unknown.
- Added eight edge/corner hover positions and anchor-aware drawer expansion and contraction.
- Staggered header, cards, quota rows and footer using the reversible reveal timeline; added a preference to disable staggering.
- Added scrollable settings with a visual screen-position picker. Rust backend unchanged.

## Initial repository baseline

- Rust v0.1.0 backend: Codex App Server rate-limit polling, experimental T3 account discovery, cache, CLI and systemd service.
- UI v5: independent top-right Quickshell overlay, reversible corner morph, centered settings, Caelestia-aware palette, monochrome fallback, Rune Icons support, Inter/JetBrains Mono preference.
- Unified installer with UI-only updates, optional upstream icon retrieval and backup of installed QML.
