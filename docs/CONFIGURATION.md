# Configuration reference

[← Project home](../README.md)

## Appearance

Linux provides Grid/Rings (outer session and inner weekly concentric gauges), eight corner/edge hotspots, seven built-in palettes plus Caelestia, rounding and width controls, font selector, 12–48 px scroll fades and Liquid/Smooth/Reduced motion. Interface motion defaults to 240 ms (120–1200 ms); data motion defaults to 450 ms (200–2800 ms). Revision 5 replaces the former 820/1800 ms defaults while retaining custom timings, motion style and saved stagger choices. Revision-3 timing still migrates to data motion. Smooth adds 12% to interface duration only. Panels keep their final layout dimensions: the drawer fades with up to 4 px of travel, and the control centre fades with a 1.5% scale change. Dismissal is shorter than entry, and interrupted transitions reverse from their current position. Settings rows scale by at most 1.5%; stagger is off for new preferences and, when enabled, delays content by no more than 120 ms. Control feedback takes 80–140 ms. Ring sweeps retain their linear clock (about 430 ms at the default data speed). Quota bars and chart data reveal use the separate data clock; chart axes remain stationary. Cache refreshes retain ring delegates when account IDs are unchanged. Downward dropdowns grow from top-left; upward dropdowns from bottom-left. Reduced disables interface transitions and Wisp motion, including transitions already in progress. Trackpad input, scrolling, cache polling and hover dismissal delays are independent of the animation setting.

Refresh beside Settings in the drawer reads the existing local quota cache, like Ctrl+R in the control centre. It does not request fresh provider quotas or change the daemon's polling cadence. The drawer uses the Overlay layer so its hotspot and panel remain available above other shell surfaces and full-screen clients. Behaviour's activation-position controls show the screen edge or corner with a marker and support keyboard activation.

The optional font pack includes Inter, Manrope, Montserrat, Poppins, DM Sans, Plus Jakarta Sans, Space Grotesk, Outfit, Sora, Figtree, Rubik and Noto Sans, plus JetBrains Mono for numbers. Installed families appear in the selector. Fonts live in XDG_DATA_HOME/fonts/aether-ai (default ~/.local/share/fonts/aether-ai) with upstream OFL licenses.

Caelestia requires a running standard `qs -c caelestia` instance and a usable scheme JSON (normally ~/.local/state/caelestia/scheme.json). If unavailable, the option is disabled and existing selections fall back to Mono. Nonstandard config names are not detected automatically.

## Scrolling

Appearance → Scrolling controls scroll edge fades, fade depth and trackpad speed (0.8–3.0×; default 1.6×). Precision touchpad events use their pixel delta directly, including precision events classified as mouse input by Qt. Conventional wheel notches use a fixed 48 px step; the trackpad multiplier applies only to pixel deltas. Animation speed does not control scrolling.

## Account discovery

The shared core discovers CODEX_HOME (or ~/.codex), experimental T3 settings and explicit extra homes. Deduplication is by directory. Managed T3 authentication is not implemented; shadow homes are treated as standalone CODEX_HOME directories. Codex itself may refresh credentials. aether does not write T3 configuration.

| Variable | Purpose |
|---|---|
| CODEX_HOME | Default Codex directory |
| AETHER_CODEX_HOMES | Additional homes; colon-separated |
| AETHER_T3_SETTINGS | Exact T3 settings JSON path |
| AETHER_CODEX_BIN | Explicit trusted native CLI path |

Fish example: `set -x AETHER_T3_SETTINGS /actual/path/settings.json`. For Linux daemon environment use `systemctl --user edit aether.service` and Environment under [Service], then restart. Visibility filters affect display, not authentication/polling. Only Codex is implemented.

## Analytics

Recorded remaining quota percentages, not token counts or spending. The daemon polls every 180 seconds; successful snapshots are recorded. Choose 24h/7d/30d/90d, session/weekly and line/bars. Samples are retained roughly 92 days and downsampled to 15-minute/hourly buckets. No previous T3 cost or token history imported.

## Local data

| Data | Linux default |
|---|---|
| Cache | ~/.cache/aether/usage.json |
| History | ~/.local/state/aether/history |
| Preferences | ~/.config/quickshell/aether/preferences.ini |

XDG cache/state/config overrides are supported. Local files use restrictive creation permissions. Names and paths in cache/history are private. No telemetry or cloud storage. Optional network requests include Codex, asset retrieval and enabled update checks.

## Wisp

Wisp is the aether.ai mascot. Appearance → Animate Wisp controls the 18-second idle motion (blink, float, breathing, curious/happy expressions and halo). Reduced motion overrides the preference on Linux. Static icons retain the original transparent silhouette. See [branding](BRANDING.md).
