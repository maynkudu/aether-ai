# Changelog

## [Unreleased]

- Keep Linux / Wayland as the supported target and run release checks for Linux builds.
- Add token analytics and smoother quota charts to the Linux control centre.

## [0.2.0-alpha.1] - 2026-11-25

First public alpha candidate. The release is a prerelease, not a stable build.

### Highlights

- Local-first Codex quota monitoring, multiple accounts, real quota history, and Wisp branding.
- Linux (Arch x86_64 / Wayland): Quickshell control centre, grid/ring quotas, configurable motion, palettes including Caelestia, shortcuts and existing opt-in updater.
- Arch Linux x86_64 release archive, source archive, SHA256 checksums, tag-only CI, and release preflight.

### Known limitations

- Codex is the only implemented provider adapter.
- The Linux binary archive targets Arch x86_64; Quickshell, Wayland and Codex prerequisites still apply.

## Development history before alpha

- Bound the native poller's result storage to its latest snapshot.

- Validate release tags and lockfile before expensive matrix builds; embed release identity in native binaries.


- Accept version-matched alpha, beta and RC release tags with exact dated notes, and draft suffixed tags as GitHub prereleases; retain release-only CI.

### Release-only CI

- Fix invalid QML separators after per-item growth transforms.

### Responsive navigation, slow data growth

- Separate interface timing (820 ms default) from quota/graph timing (1800 ms default), preserving slow linear ring sweeps without slowing navigation or dropdowns.
- Replace page-wide and heading clipping with individual top-left anchored growth on settings headings, rows, cards and repeated items across all eight tabs.
- Keep analytics axes stationary while chart data reveals independently. Add separate interface and data motion preferences.

### Calmer native motion

- Use one shared duration scale, default 1800 ms, for Linux drawer, settings, navigation, menus and control transitions. Reverse from the current position without overshoot; keep scrolling and input independent.
- Draw concentric quota rings with a dedicated linear clock and preserve ring delegates across unchanged account identities. Animate changed quota values independently.
- Extend headless smoke coverage to render real-shaped sample ring cards, including 100%, zero and unknown quota states.

### Concentric quota rings

- Adopt full concentric session and weekly quota gauges on Linux, preserving real quota values, resets and provider identity.

### Wisp identity

- Adopt Wisp as the official mascot while retaining aether.ai as the product name. Replace the spiral in the README, QML headers and native icons.
- Add static and animated SVGs, wordmark lockups and Linux QML motion tracks. Respect Reduced motion and persist the animation preference on Linux.
- Include branding assets in Linux archives and test mascot timing in Linux CI.

### Simplification, identity and CI reliability

- Remove all glass-material preferences, renderer probes and setup UI. Retain opaque themes, liquid motion and Caelestia detection.
- Add direct precision trackpad scrolling and configurable speed, independently of reveal animations.
- Adopt the approved spiral brand mark in documentation, Linux navigation and native window icons.
- Fix the headless Sway execution failure in containerized Linux CI by removing its file capabilities in the disposable runner only; retain all graphical smoke-test gates. Strengthen Linux mock tests, icon self-tests and diagnostic artifacts.

### Documentation and startup fix

- Rename the dropdown's custom height property to avoid overriding Qt Popup's final property.
- Redesign the README with original SVG illustrations, platform and configuration guides, contribution and security policies, and issue/PR templates.

### Linux interface and shared core

- Correct upward dropdown growth: bottom-left to top-right; downward remains top-left to bottom-right.
- Keep the Rust quota core, Linux CLI and Quickshell paths in one package.

### Release engineering and interaction fixes

- Upward dropdowns grow from bottom-left; downward dropdowns grow from top-left. Direction-aware chevrons and available-space sizing.
- Disable Caelestia without an active standard shell and usable palette; disable Liquid Glass without an active HyprGlass layer renderer. Explanatory tooltips and setup links, with existing safe fallbacks.
- Linux CI, mock Codex integration tests, headless Quickshell smoke checks, gated draft releases with versioned notes and SHA256 checksums, and architecture documentation.
- Stabilize dropdown and read-only text focus.

### Dropdown polish and refractive material

- Slower page stagger, permanent GitHub and shortcut surfaces, original Feather chevrons, hover/keyboard option states, top-left clipped dropdown growth and grid palette previews.
- Separate Solid, Frosted and Liquid Glass materials. Optional real compositor refraction via HyprGlass contour layers, readiness status, copyable Lua configuration and tint slider; safe solid fallback, no automatic plugin installation or compositor edits.

### Fluid control refinement

- Shared liquid-style native dropdowns for appearance, typography, shortcut choices and update channels.
- Slower 1100 ms default, damped corner-anchored growth with fixed content coordinates, left-to-right page clipping and staggered sections. Existing custom speed settings preserved.
- Provider categories, shared FreeGG/AgentRouter artwork by maintainer request, official GitHub mark in navigation and About.
- Optional translucent glass surfaces with compositor blur namespaces; no screen refraction or compositor edits. Backend/updater unchanged.

### Liquid motion and updater

- Native analytic springs inspired by Modulo: interruptible shell growth, separately staggered content, sliding navigation pill, elastic button/switch/slider details. Liquid, Smooth and Reduced motion modes.
- Updates tab and local updater with Stable releases and Development commits, opt-in installation, six-hour user timer, source ancestry checks, isolated builds and restoration on install errors and one previous-build rollback. No release is published by this change.
- Ctrl+7 opens Updates; Ctrl+8 opens About. Existing provider/backend logic unchanged.

### Scroll polish and shortcuts

- Added viewport-relative, theme-aware top/bottom scroll fades for the drawer and all settings tabs; configurable depth and enable toggle.
- Added a Shortcuts tab with persistent desktop binding choices, duplicate detection, and copyable Hyprland legacy/Lua configuration. No compositor files changed automatically.
- Added focused-window Ctrl+1–7 navigation, Ctrl+R cache refresh, Escape dismiss, and IPC actions for analytics, refresh, dismiss and shortcuts.
- Documented Linux / Wayland support and release requirements. Backend unchanged.

### Appearance and provider polish

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
