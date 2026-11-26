# Configuration reference

[← Project home](../README.md)

## Appearance

Linux provides Grid/Rings (outer session and inner weekly concentric gauges), eight corner/edge hotspots, seven built-in palettes plus Caelestia, rounding and width controls, font selector, 12–48 px scroll fades and Liquid/Smooth/Reduced motion. Interface motion defaults to 240 ms (120–1200 ms); data motion defaults to 450 ms (200–2800 ms). Revision 5 replaces the former 820/1800 ms defaults while retaining custom timings, motion style and saved stagger choices. Revision-3 timing still migrates to data motion. Smooth adds 12% to interface duration only. The drawer grows from its selected edge or corner, then its contents appear in a reversible stagger; dismissal collapses it back toward that origin. The control centre fades with a 1.5% scale change. Dismissal is shorter than entry, and interrupted transitions reverse from their current position. Settings rows scale by at most 1.5%; stagger is on for new preferences and spreads content entries over up to 170 ms. Control feedback takes 80–140 ms. Ring sweeps retain their linear clock (about 430 ms at the default data speed). Quota bars and chart data reveal use the separate data clock; chart axes remain stationary. Cache refreshes retain ring delegates when account IDs are unchanged. Downward dropdowns grow from top-left; upward dropdowns from bottom-left. Reduced disables interface transitions and Wisp motion, including transitions already in progress. Trackpad input, scrolling, cache polling and hover dismissal delays are independent of the animation setting.

Refresh beside Settings in the drawer reads the existing local quota cache, like Ctrl+R in the control centre. It does not request fresh provider quotas or change the daemon's polling cadence. The drawer grows from the selected hotspot toward the centre and collapses back to that edge or corner, with content entering in a short stagger. The hotspot is suppressed while Hyprland reports a full-screen window by default. Behaviour → Allow over full-screen apps enables the override. Activation-position controls show the screen edge or corner with a marker and support keyboard activation.

The optional font pack includes Inter, Manrope, Montserrat, Poppins, DM Sans, Plus Jakarta Sans, Space Grotesk, Outfit, Sora, Figtree, Rubik and Noto Sans, plus JetBrains Mono for numbers. Installed families appear in the selector. Fonts live in XDG_DATA_HOME/fonts/aether-ai (default ~/.local/share/fonts/aether-ai) with upstream OFL licenses.

Caelestia requires a running standard `qs -c caelestia` instance and a usable scheme JSON (normally ~/.local/state/caelestia/scheme.json). If unavailable, the option is disabled and existing selections fall back to Mono. Nonstandard config names are not detected automatically.

## Scrolling

Appearance → Scrolling controls scroll edge fades, fade depth and trackpad speed (0.8–3.0×; default 1.6×). Precision touchpad events use their pixel delta directly, including precision events classified as mouse input by Qt. Conventional wheel notches use a fixed 48 px step; the trackpad multiplier applies only to pixel deltas. Animation speed does not control scrolling.

## Account discovery

The development build discovers Codex, Claude Code, Pi and OpenCode. Codex uses CODEX_HOME (or ~/.codex), experimental T3 settings and explicit extra homes. Managed T3 authentication is not implemented; shadow homes are treated as standalone CODEX_HOME directories. Codex itself may refresh credentials. Aether does not write T3 configuration.

Claude Code uses its Linux `.credentials.json` OAuth entry, with five-hour and seven-day quota windows from Anthropic's usage endpoint. API-key or gateway credentials in its settings are recognised without reporting subscription limits. MCP server credentials are ignored. Pi reads `auth.json` in its agent directory. OpenCode v2 uses `opencode auth export` internally, with bounded output and a timeout; v1 `auth.json` is also supported. The command output stays in memory and is never logged or cached. All saved OpenCode accounts are included, even when inactive.

For Pi and OpenCode, OpenAI/Codex OAuth uses the upstream account's ChatGPT quota windows, and Anthropic OAuth uses Anthropic's account windows. Matching OAuth credentials share one request per refresh. These are upstream account readings, not a separate allowance per app. Provider policy determines which clients consume each allowance. Other OAuth providers are marked unsupported; API-key accounts without a supported allowance endpoint show quota resources unavailable. AgentRouter and FreeGG entries are omitted. Tokens and refresh tokens are never copied into Aether's cache or history. Aether does not renew these clients' tokens or write their auth files; open the owning client when a login needs refreshing. The existing three-minute polling cadence remains, with a three-request concurrency limit, request timeouts and retry delays for rate limits. Failed reads retain a stale previous reading when one exists; authentication failures clear it.

OpenCode Go keys use its usage endpoint for five-hour, weekly and monthly allowance readings. With a compatible OpenCode v2 client, Aether also reads `opencode api experimental.usage.limits` for the active Console workspace's Go allowances and monthly spending budgets. Budget amounts are shown in USD, with reset times and a shared-budget label where applicable. A zero-dollar budget remains visible as exhausted. Monthly and budget history use separate period identifiers rather than pretending every month has the same duration. A successful signed-out response removes the previous workspace reading; failed reads retain it as stale.

`opencode api model.list` supplies a separate free-model row. It counts enabled, active OpenCode models whose input and output prices are zero across all reported tiers; hover over the row for model names. The row includes seven-day model steps and token totals from OpenCode's local statistics. Failed statistics reads retain the previous total with a cached label. View usage opens the model breakdown in Analytics. Remaining free allowance stays unknown.

Aether opens OpenCode's local SQLite database read-only and selects model identifiers, completion timestamps and error metadata from assistant messages. A saved `provider.free-limit` error provides an observed limit. Its retry countdown uses the error's completion time plus a valid `retryAfterMs` of at most 45 days. A passed deadline says Retry time passed, not that quota has been restored. A later successful completion clears the active warning for that model. These observations describe local requests; they do not establish the provider's quota pool or remaining allowance. Missing or incompatible databases show Limit history unavailable. Observed limits are matched to models used in the selected period.

`aether usage` rereads this local metadata on each call, including the drawer's cache polling interval, without querying provider quotas. The daemon refreshes cached free-model statistics and the model catalogue every three minutes. These read-only operations do not send inference requests or retain prompts, response bodies or credentials. Older clients without these commands can still use the credential-based adapters above.

| Variable | Purpose |
|---|---|
| CODEX_HOME | Default Codex directory |
| AETHER_CODEX_HOMES | Additional homes; colon-separated |
| AETHER_T3_SETTINGS | Exact T3 settings JSON path |
| AETHER_CODEX_BIN | Explicit trusted native CLI path |
| CLAUDE_CONFIG_DIR | Claude Code config directory, default ~/.claude |
| AETHER_CLAUDE_HOMES | Additional Claude config directories; OS path-list separator |
| PI_CODING_AGENT_DIR | Pi agent directory, default ~/.pi/agent |
| XDG_DATA_HOME | OpenCode data root, default ~/.local/share |
| AETHER_OPENCODE_BIN | Explicit trusted OpenCode CLI path |
| AETHER_OPENCODE_AUTH | Explicit OpenCode credential JSON file, bypassing CLI export |
| AETHER_OPENCODE_DB | Explicit OpenCode SQLite database path, default XDG_DATA_HOME/opencode/opencode.db |

Fish example: `set -x AETHER_T3_SETTINGS /actual/path/settings.json`. For Linux daemon environment use `systemctl --user edit aether.service` and Environment under [Service], then restart. Visibility filters affect display, not authentication/polling. `aether accounts` lists all discovered client accounts without exposing credentials.

## Analytics

Analytics reads token-count events from local Codex session logs without retaining prompt text. It reports input, cached input, output, reasoning, total tokens and request counts for 24h/7d/30d/90d. The 24h view groups by hour; longer views group by day and include zero-use periods. Lines use rounded curves and a stable color for each provider. Cost is an API-equivalent estimate using [standard OpenAI model rates](https://platform.openai.com/pricing/) when the model is supported. Unknown models or cache-write events show an unavailable estimate instead of a fabricated number. API-key sessions are labelled in the drawer and contribute token usage when local session logs contain it, while subscription quota resources remain unavailable. Quota snapshots remain available through the daemon's local history command.

The OpenCode section uses `opencode api experimental.session.stats` for the selected rolling 24h/7d/30d/90d range. It shows device-wide totals and a model breakdown across all OpenCode sessions, including paid providers. Model variants are combined. Input includes cache reads and writes; output includes reasoning. Cached input and reasoning are also listed separately. Model steps are OpenCode assistant steps, not HTTP request counts. Recorded cost can be an endpoint charge or a catalogue estimate and is not an invoice. A reported zero stays numeric zero in CLI output and displays a dash in the UI. These totals stay separate from the Codex account charts to avoid mixing scopes or inventing time-series data. Provider visibility filters can hide the OpenCode section; account filters apply to Codex account data.

Pi reads assistant usage metadata from its local `sessions` JSONL files. Input includes cache reads and writes; output already includes reasoning, so reasoning is not added twice. Replayed response IDs and repeated Claude message snapshots are counted once. Removed AgentRouter and FreeGG usage is excluded. Costs come from the client's saved metadata and may be estimates, including a configured zero price. Missing prices stay unknown.

Claude Code reads assistant input and cache metadata from each configured profile's `projects` JSONL files. Claude streamed assistant output can be a provisional value, so this adapter reports input/cache counts as Known tokens and leaves final output unavailable rather than treating a placeholder as a final count. Recorded cost fields are estimates. Profiles without usage records show an empty state. Oversized records and unreadable files mark data partial; prompts, responses and credentials are never retained.

## Local data

| Data | Linux default |
|---|---|
| Cache | ~/.cache/aether/usage.json |
| History | ~/.local/state/aether/history |
| Preferences | ~/.config/quickshell/aether/preferences.ini |

XDG cache/state/config overrides are supported. Local files use restrictive creation permissions. Names and paths in cache/history are private. No telemetry or cloud storage. Network requests include the configured subscription quota endpoints, opt-in asset retrieval and enabled update checks.

## Wisp

Wisp is the aether.ai mascot. Appearance → Animate Wisp controls the 18-second idle motion (blink, float, breathing, curious/happy expressions and halo). Reduced motion overrides the preference on Linux. Static icons retain the original transparent silhouette. See [branding](BRANDING.md).
