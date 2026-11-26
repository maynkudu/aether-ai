# Provider artwork sources

aether.ai uses provider-supplied artwork. Codex, Claude Code, Pi and OpenCode logos are bundled in `provider-logos/`, with source URLs and SHA-256 records in `sources.json`. The installer, updater and release archive carry both theme variants, so these clients always have real logos offline. The app does not download images at runtime or substitute letters. Logos are trademarks of their respective owners and identify services without implying sponsorship.

| Provider | Source | Treatment |
|---|---|---|
| Codex / OpenAI | [Official Cookbook Blossom assets](https://github.com/openai/openai-cookbook/tree/4a85c3018d20ceef48bf7549450c567896501bf9/examples/voice_solutions/realtime_translation_guide/livekit-translation-demo/public/brand) and [OpenAI brand guidelines](https://openai.com/brand/) | Approved transparent white/black SVGs; pinned blob hashes; original proportions and artboard retained. Used for provider identification only. |
| Claude | [Anthropic-hosted product favicon](https://assets-proxy.anthropic.com/claude-ai/v2/assets/v1/cd02a42d9-Vq_H3mgS.svg) | Preserve the original mark and its colours; only resolve inherited currentColor if present. |
| Grok | [Official xAI brand kit](https://x.ai/legal/brand-guidelines) | Select the supplied light/dark standalone logomarks, never a wordmark or a redrawn substitute. |
| OpenCode | [First-party provider SVG](https://github.com/anomalyco/models.dev/blob/dev/providers/opencode/logo.svg) and [brand guidelines](https://opencode.ai/brand) | Resolve currentColor to the appropriate foreground, retain geometry and opacity. |
| Pi | [Official press kit](https://pi.dev/press-kit), [square badge](https://pi.dev/favicon.svg) | Preserve supplied artwork and resolve currentColor if used. |
| OpenRouter | [Official repository mark](https://github.com/OpenRouterTeam/sign-in-with-openrouter/blob/main/public/openrouter-logo.svg) and [brand assets](https://openrouter.ai/brand) | Resolve currentColor; preserve artwork. |
| DeepSeek | [Official Harness repository](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/web/public) | Use supplied light/dark favicons. |

## Additional providers

Installations from before bundled client logos need one full source installation. Older seven-file updaters cannot add these assets; the current updater includes them.

Additional authentic artwork can be saved as `<provider-id>-dark.png` and `<provider-id>-light.png` in `~/.config/quickshell/aether/brand-icons/` (or the matching XDG config location). IDs are lowercase and strip non-alphanumeric characters; known agent/provider aliases are normalized in shell.qml. Dark means artwork intended for a dark background. Run `bash install.sh --ui-only` to rebuild the local index and restart aether. Files in that local directory are not committed. The four supported clients use their bundled marks.

`--fetch-icons` remains an optional refresh of external artwork, with checked Git hashes for pinned upstream assets. The bundled PNGs preserve source geometry and artboards. Codex uses the supplied white and black exports. Claude and OpenCode resolve the source's inherited currentColor. Pi resolves its original light/dark CSS before rasterisation. Original brand colours are retained where no monochrome variant exists. No legacy Rune provider artwork or initial fallback is used.

Remote site assets and the Grok archive layout still require an end-to-end installation test; the source paths and the pinned Git blobs have been checked separately.

### GitHub mark and provider grouping

The small GitHub mark in the sidebar and repository link uses the original vector path from [Primer Octicons](https://github.com/primer/octicons/blob/main/icons/mark-github-24.svg), Git blob `81949e7b460a7bbf1cb2431462f6bd947e32f0ce`. The upstream license is retained in `shell/OCTICONS-LICENSE`.

The dropdown chevron uses the original Feather `chevron-down` geometry, exposed as `FiChevronDown` by React Icons. See [Feather](https://github.com/feathericons/feather/blob/main/icons/chevron-down.svg) and `shell/FEATHER-LICENSE` (MIT).
