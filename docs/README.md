# cmagent Documentation

Start with the [README](../README.md) for an overview; these guides go deep.

## Concepts & reference

| Document | Description |
|---|---|
| [architecture.md](architecture.md) | How the binary wires up; crates and the agent loop |
| [configuration-guide.md](configuration-guide.md) | Providers, agent profiles, skills, presets, MCP, config reference |
| [tools.md](tools.md) | The built-in tool catalog (risk levels, what each does) |
| [commands.md](commands.md) | Interactive `/` commands, `@`-file mentions, `/steer` & `/queue` |
| [security-model.md](security-model.md) | Risk levels, security gates, tool permissions |

## Capabilities

| Document | Description |
|---|---|
| [lsp.md](lsp.md) | Code intelligence: definitions, references, outline, rename, file moves |
| [channels.md](channels.md) | Telegram / Slack / Discord / WeChat / Lunkr messaging (in + out), per-channel capability matrix |
| [media.md](media.md) | Vision, text-to-speech (TTS), and speech-to-text (STT) settings |
| [memory.md](memory.md) | Brain layers, review summaries, memory browser TUI |
| [skill-slash-commands.md](skill-slash-commands.md) | User-invocable skills and command dispatch |
| [skill-packages.md](skill-packages.md) | Nested skill packages, hooks.json, Claude Code plugin compatibility |
| [hooks-cron.md](hooks-cron.md) | Run commands on lifecycle events; schedule recurring agent/shell/webhook jobs |
| [ralph-loop.md](ralph-loop.md) | Long-task iterative agent loop |

## Interfaces & ops

| Document | Description |
|---|---|
| [gateway.md](gateway.md) | HTTP API gateway — remote access and web UI |
| [acp.md](acp.md) | ACP stdio protocol — IDE and tool integration |
| [codex-import.md](codex-import.md) | Reuse OpenAI Codex CLI credentials |
| [update.md](update.md) | Auto-update and version management |

## Design Documents

Internal design, planning, and analysis docs live in `docs/internal/`
(`plans/`, `analysis/`, …). They record decisions made during development,
are not required reading for users, and are **not** published to the public
GitHub mirror.
