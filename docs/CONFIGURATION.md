# Configuration reference

[← Project home](../README.md)

## Appearance

Linux provides Grid/Rings, eight corner/edge hotspots, seven built-in palettes plus Caelestia, rounding and width controls, font selector, 12–48 px scroll fades and Liquid/Smooth/Reduced motion. Default animation duration is 1100 ms. Downward dropdowns grow from top-left; upward dropdowns from bottom-left. Reduced disables new spring transitions; some existing colour/quota transitions remain.

The optional font pack includes Inter, Manrope, Montserrat, Poppins, DM Sans, Plus Jakarta Sans, Space Grotesk, Outfit, Sora, Figtree, Rubik and Noto Sans, plus JetBrains Mono for numbers. Installed families appear in the selector. Fonts live in XDG_DATA_HOME/fonts/aether-ai (default ~/.local/share/fonts/aether-ai) with upstream OFL licenses.

Caelestia requires a running standard `qs -c caelestia` instance and a usable scheme JSON (normally ~/.local/state/caelestia/scheme.json). If unavailable, the option is disabled and existing selections fall back to Mono. Nonstandard config names are not detected automatically.

## Scrolling

Appearance → Scrolling controls scroll edge fades, fade depth and trackpad speed (0.8–3.0×; default 1.6×). Precision touchpad events use their pixel delta directly, including precision events classified as mouse input by Qt. Conventional wheel notches use a fixed 48 px step; the trackpad multiplier applies only to pixel deltas. Animation speed does not control scrolling.

## Account discovery

The shared core discovers CODEX_HOME (or ~/.codex), experimental T3 settings and explicit extra homes. Deduplication is by directory. Managed T3 authentication is not implemented; shadow homes are treated as standalone CODEX_HOME directories. Codex itself may refresh credentials. aether does not write T3 configuration.

| Variable | Purpose |
|---|---|
| CODEX_HOME | Default Codex directory |
| AETHER_CODEX_HOMES | Additional homes; colon on Unix, semicolon on Windows |
| AETHER_T3_SETTINGS | Exact T3 settings JSON path |
| AETHER_CODEX_BIN | Explicit trusted native CLI path |

Fish example: `set -x AETHER_T3_SETTINGS /actual/path/settings.json`. For Linux daemon environment use `systemctl --user edit aether.service` and Environment under [Service], then restart. Visibility filters affect display, not authentication/polling. Only Codex is implemented.

## Analytics

Recorded remaining quota percentages, not token counts or spending. The daemon polls every 180 seconds; successful snapshots are recorded. Choose 24h/7d/30d/90d, session/weekly and line/bars. Samples are retained roughly 92 days and downsampled to 15-minute/hourly buckets. No previous T3 cost or token history imported.

## Local data

| Data | Linux default | macOS default | Windows default |
|---|---|---|---|
| Cache | ~/.cache/aether/usage.json | ~/Library/Caches/aether/usage.json | %LOCALAPPDATA%/aether/usage.json |
| History | ~/.local/state/aether/history | ~/Library/Application Support/aether/history | %LOCALAPPDATA%/aether/history |
| Preferences | ~/.config/quickshell/aether/preferences.ini | ~/Library/Application Support/aether/desktop-preferences.json | %LOCALAPPDATA%/aether/desktop-preferences.json |

XDG cache/state overrides are supported. Linux configuration respects XDG_CONFIG_HOME. Unix files use restrictive creation permissions; Windows inherits user-profile ACLs. Names and paths in cache/history are private. No telemetry or cloud storage. Optional network requests include Codex, asset retrieval and enabled update checks.
