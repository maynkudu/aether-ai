# Changelog

## Unreleased — Scroll polish and shortcuts

- Added viewport-relative, theme-aware top/bottom scroll fades for the drawer and all settings tabs; configurable depth and enable toggle.
- Added a Shortcuts tab with persistent desktop binding choices, duplicate detection, and copyable Hyprland legacy/Lua configuration. No compositor files changed automatically.
- Added focused-window Ctrl+1–7 navigation, Ctrl+R cache refresh, Escape dismiss, and IPC actions for analytics, refresh, dismiss and shortcuts.
- Documented Linux/Wayland scope and future native-platform port requirements. Backend unchanged.

## Unreleased — Appearance and provider polish

- Default Mono, Mono Light and five additional built-in/dynamic palettes; live theme switching, contrast-aware controls and reset to Mono.
- Curated Google Fonts typography selector, live preview, optional user-local font installer with upstream OFL licenses.
- Replace the square Codex application icon with the official transparent OpenAI Blossom (black/white).
- Nested linked-account cards with individual visibility, health and session/weekly quota previews. Backend and analytics unchanged.

## v0.2.0 — Control centre

- Sidebar-based settings, provider logos, persistent visibility filters, typography and hotspot controls, redesigned About page and MIT license.
- Real local quota history, 24h/7d/30d/90d line and bar views. T3 token/cost analytics are not connected yet.

## UI v7 — Brand artwork and circular rings

- Replaced provider-icon library lookup with an opt-in, documented first-party asset importer; Codex original app icons use a verified attributed mirror. No provider logo is borrowed from another brand. Missing artwork uses initials.
- Added local dark/light brand asset index and custom-provider artwork support. Original artwork geometry and brand colours retained.
- Replaced Canvas gauge with square, native QtQuick Shapes circular arcs, identical radii, rounded caps and constant top/bottom gaps. Preserved staggered reveal and Caelestia palette.
- Rust backend unchanged. See shell/BRAND-ASSETS.md for provenance and limitations.

## UI v6 — Customisation

- Added a persisted Grid / Rings layout selector, split session and weekly quota arcs, percentages and reset labels. Unknown quotas remain unknown.
- Added eight edge/corner hover positions and anchor-aware drawer expansion and contraction.
- Staggered header, cards, quota rows and footer using the reversible reveal timeline; added a preference to disable staggering.
- Added scrollable settings with a visual screen-position picker. Rust backend unchanged.

## Initial repository baseline

- Rust v0.1.0 backend: Codex App Server rate-limit polling, experimental T3 account discovery, cache, CLI and systemd service.
- UI v5: independent top-right Quickshell overlay, reversible corner morph, centered settings, Caelestia-aware palette, monochrome fallback, Rune Icons support, Inter/JetBrains Mono preference.
- Unified installer with UI-only updates, optional upstream icon retrieval and backup of installed QML.
