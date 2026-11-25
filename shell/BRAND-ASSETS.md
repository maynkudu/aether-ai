# Provider artwork sources

aether.ai uses provider-supplied artwork rather than icon-library redraws. The install-time fetch is opt-in; the app never downloads images at runtime. Logos are trademarks of their respective owners and are used only to identify services, not to imply sponsorship.

| Provider | Source | Treatment |
|---|---|---|
| Codex / OpenAI | [Official Cookbook Blossom assets](https://github.com/openai/openai-cookbook/tree/4a85c3018d20ceef48bf7549450c567896501bf9/examples/voice_solutions/realtime_translation_guide/livekit-translation-demo/public/brand) and [OpenAI brand guidelines](https://openai.com/brand/) | Approved transparent white/black SVGs; pinned blob hashes; original proportions and artboard retained. Used for provider identification only. |
| Claude | [Anthropic-hosted product favicon](https://assets-proxy.anthropic.com/claude-ai/v2/assets/v1/cd02a42d9-Vq_H3mgS.svg) | Preserve the original mark and its colours; only resolve inherited currentColor if present. |
| Grok | [Official xAI brand kit](https://x.ai/legal/brand-guidelines) | Select the supplied light/dark standalone logomarks, never a wordmark or a redrawn substitute. |
| OpenCode | [First-party provider SVG](https://github.com/anomalyco/models.dev/blob/dev/providers/opencode/logo.svg) and [brand guidelines](https://opencode.ai/brand) | Resolve currentColor to the appropriate foreground, retain geometry and opacity. |
| Pi | [Official press kit](https://pi.dev/press-kit), [square badge](https://pi.dev/favicon.svg) | Preserve supplied artwork and resolve currentColor if used. |
| OpenRouter | [Official repository mark](https://github.com/OpenRouterTeam/sign-in-with-openrouter/blob/main/public/openrouter-logo.svg) and [brand assets](https://openrouter.ai/brand) | Resolve currentColor; preserve artwork. |
| AgentRouter | [Official docs logo](https://github.com/agentrouter-org/docs/blob/main/index.md) | Preserve the original PNG. |
| DeepSeek | [Official Harness repository](https://github.com/deepseek-ai/deepseek-harness/tree/master/apps/web/public) | Use supplied light/dark favicons. |

## Additional providers

FreeGG and other aggregators without a verified source are not assigned somebody else's logo. The UI displays initials until a matching asset is available. To add your own authentic artwork, save PNG variants as `<provider-id>-dark.png` and `<provider-id>-light.png` in `~/.config/quickshell/aether/brand-icons/` (or the matching XDG config location). IDs are lowercase and strip non-alphanumeric characters; known agent/provider aliases are normalized in shell.qml. Dark means artwork intended for a dark background. Run `bash install.sh --ui-only` to rebuild the local index and restart aether. Files in that local directory are not committed.

Source files are downloaded on your machine only when `--fetch-icons` is passed; checked Git hashes reject changed pinned upstream assets. If a download or rasterisation fails, valid previously installed brand artwork is retained or the provider initial is shown. No legacy Rune provider artwork is used. Source artwork is not bundled with this repository. Follow the current brand guidelines and review permissions before redistributing assets. Original brand colours are retained where no approved monochrome variant exists.

Remote site assets and the Grok archive layout still require an end-to-end installation test; the source paths and the pinned Git blobs have been checked separately.

### GitHub mark and provider grouping

The small GitHub mark in the sidebar and repository link uses the original vector path from [Primer Octicons](https://github.com/primer/octicons/blob/main/icons/mark-github-24.svg), Git blob `81949e7b460a7bbf1cb2431462f6bd947e32f0ce`. The upstream license is retained in `shell/OCTICONS-LICENSE`. FreeGG is displayed using the AgentRouter asset at the maintainer's request; they remain distinct provider identities.

The dropdown chevron uses the original Feather `chevron-down` geometry, exposed as `FiChevronDown` by React Icons. See [Feather](https://github.com/feathericons/feather/blob/main/icons/chevron-down.svg) and `shell/FEATHER-LICENSE` (MIT).
