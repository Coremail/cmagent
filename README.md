# cmagent

A terminal-based AI agent for real work — coding, automation, and chat.
Full-screen TUI, multi-provider, with sub-agents, skills, MCP, language-server
code intelligence, and chat-platform channels. Single static binary; runs on
Linux, macOS, and Windows.

Providers: Anthropic, OpenAI / OpenAI-compatible, and GLM (z.ai), plus
anything reachable through an OpenAI-compatible endpoint.

## Install

### Linux / macOS

```sh
curl -fsSL https://raw.githubusercontent.com/Coremail/cmagent/main/install.sh | sh
```

Installs to `~/.local/bin/cmagent`. If that directory is not in your PATH, the
installer will tell you what to add to your shell profile.

### Windows

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/Coremail/cmagent/main/install.ps1 | iex
```

Installs to `%LOCALAPPDATA%\cmagent\cmagent.exe` and adds it to your user PATH.

### Manual download

Download the binary for your platform from the
[Releases](https://github.com/Coremail/cmagent/releases/latest) page, extract,
and place it on your PATH.

| Platform        | File                            |
|-----------------|---------------------------------|
| Linux x86\_64   | `cmagent-linux-x86_64.tar.gz`   |
| macOS aarch64   | `cmagent-macos-aarch64.tar.gz`  |
| Windows x86\_64 | `cmagent-windows-x86_64.zip`    |

Each archive contains the single binary plus a `.sha256` checksum.

## Quick start

```sh
cmagent init                    # first run: configure a provider (e.g. Anthropic)
cmagent tui                     # launch the full-screen TUI (most common)
cmagent                         # no args: menu (TUI / chat / gateway / config / status)
cmagent -m "Explain this repo"  # one-shot: send a message and exit
cmagent tui --agent coding      # pick an agent profile
```

`cmagent doctor` verifies your setup (providers, sandbox, language servers,
skills, …) at any time.

## Features

cmagent is more than a chat box. Each capability below links to its guide.

### Interfaces

Drive the same agent five ways:

- **`cmagent tui`** — the recommended full-screen TUI. Two front-ends share
  all commands, sessions, and config: **canvas** (default; multi-pane, mouse
  selection, live tool/thinking tree, sidebar with tokens/context/git/plan/…)
  and **streaming** (print-based into native scrollback, best for SSH / demos).
  Pick with `--canvas` / `--streaming` or `[general] default_tui`.
- **`cmagent chat`** — a plain stdin/stdout REPL for restricted terminals or
  piping.
- **`cmagent -m "…"`** — non-interactive one-shot for scripts, cron, and CI.
- **`cmagent gateway`** — a local HTTP + WebSocket server so other tools, web
  frontends, or remote TUI clients can drive the agent. See
  [docs/gateway.md](docs/gateway.md).
- **`cmagent acp`** — an Agent Client Protocol stdio server to embed cmagent in
  an IDE or another app. See [docs/acp.md](docs/acp.md).

### Providers & models

Configure one or many providers; pin per-agent models and endpoints, or set a
session override. Credentials live as environment variables (e.g.
`ANTHROPIC_API_KEY`). If you use the OpenAI Codex CLI, cmagent can import its
credentials — see [docs/codex-import.md](docs/codex-import.md). Full provider /
model reference: [docs/configuration-guide.md](docs/configuration-guide.md).

### Agents & profiles

An *agent profile* bundles a system prompt, a tool allowlist, a security
posture (`prompt_threshold`, allowed commands, workspace leash), brain scopes,
skills, and MCP servers. Shipped profiles include `coding`, `chat`, and
`admin`; create your own with `cmagent config`. Profiles can inherit shared
**presets**. Configuration: [docs/configuration-guide.md](docs/configuration-guide.md).

### Tools

A broad built-in toolset — file read/write/edit, `apply_patch` (multi-file
diffs + git-conflict resolution), gitignore-aware search, shell, web fetch/
search, HTTP, memory, planning, and more — each gated by the security model.
The agent's `tools = [...]` allowlist is the hard limit. Full catalog:
[docs/tools.md](docs/tools.md).

### Code intelligence (LSP)

`lsp_query` drives real language servers (rust-analyzer, pyright, gopls, …) for
go-to-definition, references, hover, a token-lean file outline, project-wide
symbol rename, and reference-updating file moves. See [docs/lsp.md](docs/lsp.md)
(`cmagent lsp list` to see what to install).

### Skills

Skills are SKILL.md bundles (prompt + optional slash commands) loaded from
`~/.cmagent/skills/`. Selection is deterministic (keyword/tag/regex, not LLM),
and trust levels attenuate tool risk. Claude Code plugin bundles are supported.
See [docs/skill-slash-commands.md](docs/skill-slash-commands.md) and
[docs/skill-packages.md](docs/skill-packages.md).

### Sub-agents

`spawn_agent` and `plan_tasks` fan work out to specialized, spawn-only workers
(`sub-coder`, `sub-reviewer`, `sub-debugger`, `sub-researcher`, …), each with
its own tool surface and depth limit. Agents can also message each other (A2A)
via `sessions_send`.

### Long-term memory (brain)

Layered memory — global, per-workspace, and per-agent — that the agent reads
and writes via the `brain` tool, with FTS search and a memory browser.
`learn_rule` lets the agent persist a confirmed rule for next session. See
[docs/memory.md](docs/memory.md).

### Channels (messaging)

Run cmagent as a bot on **Telegram, Slack, Discord, WeChat, or Lunkr**: it
answers on a channel and can proactively send messages, files, and interactive
buttons through one unified `messaging_*` surface. Inbound can be audited. See
[docs/channels.md](docs/channels.md).

### MCP

Connect Model Context Protocol servers to expose their tools, resources, and
prompts to an agent. Manage with `cmagent mcp`; configure per profile. See
[docs/configuration-guide.md](docs/configuration-guide.md).

### Hooks & cron

Run commands on lifecycle events (session start, before/after tool calls, …)
via Claude-Code-compatible hooks, and schedule recurring agent prompts or
maintenance with a built-in cron scheduler. See [docs/hooks-cron.md](docs/hooks-cron.md).

### Ralph loop — long iterative tasks

Run a task too large for one conversation as a series of fresh,
single-step iterations that read the workspace, take one step, update
`STATUS.md`, and exit — until a `done` sentinel or `max_iter`. For bulk
refactors, ports, and migrations. See [docs/ralph-loop.md](docs/ralph-loop.md).

```sh
cmagent ralph new "Port http client from reqwest to ureq"
cmagent ralph run <id>
```

### Tracking work in a session: plan, todos, goal

Three kinds of progress state, all persisted per session:

| | What | Loop? |
|---|---|---|
| `/plan` | A short, visible roadmap (3–8 steps) the agent commits to. `/plan run [N]` re-enters to work the next step. | manual |
| `/todos` | A fine-grained checklist for the small tasks in a batch. | no |
| `/goal <text>` | An autonomous, judge-evaluated loop: a judge LLM checks each turn against the goal and re-prompts until met (or a turn cap). | automatic |

In the canvas TUI each shows as a status-bar chip or a sidebar panel
(`Ctrl+B`).

## Commands

```sh
cmagent                 # menu picker (first run: setup wizard)
cmagent tui [--agent X] [-c] [--session ID] [--remote URL --token T]
cmagent chat [--agent X] [-c]      # line-based REPL
cmagent -m "..." [--agent X]       # one-shot, non-interactive
cmagent gateway [--port 3100]      # HTTP API; `gateway user add` for tokens
cmagent acp [--agent X]            # ACP stdio server (IDE integration)
cmagent ralph <new|run|status|...> # long iterative tasks
cmagent init                       # first-time setup wizard
cmagent config                     # interactive config editor
cmagent doctor [--fix]             # diagnostics (+ auto-fix migrations)
cmagent docs [topic]               # read the bundled guides in the terminal
cmagent lsp list                   # supported language servers + install hints
cmagent workspace                  # browse / rename / delete sessions
cmagent skill <cmd>                # list / install / enable / disable skills
cmagent brain <cmd>                # inspect long-term memory
cmagent mcp <cmd>                  # manage MCP servers
cmagent update [--yes]             # update the binary in place
```

`cmagent update` checks GitHub for a newer release, downloads the right binary,
verifies the checksum, and replaces the running executable.
See [docs/update.md](docs/update.md).

### In-session controls

While typing in the TUI or chat:

- **`/help`** — list every slash command (`/model`, `/agent`, `/session`,
  `/plan`, `/todo`, `/undo`, `/compact`, …).
- **`@`** — open a file browser; the picked file's contents are spliced into
  your message on send.
- **`Ctrl+Y`** — copy the last reply as markdown (or click the `⧉` button).
- **`Ctrl+O`** — open the activity viewer (tool calls, thinking, diffs);
  `Ctrl+Y` there copies the selected entry.
- **Full-screen viewers** — Activity (`Ctrl+O`), Memory (`/memory`),
  Workspace (`/session` → "Manage sessions…"), and Debug (`/debug`, debug
  builds). They share one detail pane: drag to select, `Ctrl+Y` to copy.
- **`/steer`** / **`/queue`** — redirect or line up input while the agent is
  working.

Full keybinding + command reference, incl. the
[full-screen viewers](docs/commands.md#full-screen-viewers):
[docs/commands.md](docs/commands.md).

## Configuration

Config lives in `~/.cmagent/` (override with `CMAGENT_HOME`). Run `cmagent init`
to set up providers and preferences, or `cmagent config` to edit any time. The
[configuration guide](docs/configuration-guide.md) is the full reference for
providers, agent profiles, presets, skills, MCP, and every config field.

## Security

cmagent is built to be safe to point at a real machine and real credentials.
Every tool call passes a layered policy; defaults are conservative and tighten
for unattended profiles. Full threat model: [docs/security-model.md](docs/security-model.md).

- **Tool allowlist (hard wall).** A profile's `tools = [...]` is the outer
  limit — no prompt, preset, or session can introduce a tool that wasn't
  listed.
- **Permission prompts by risk.** `prompt_threshold` decides when you're asked
  before a Medium/High tool runs; Low tools are silent. `never` skips prompts —
  but **not** the hard walls.
- **Non-overridable hard walls.** Even under `never`: a shell-command parser
  blocks dangerous shapes, and a path policy blocks traversal /
  out-of-workspace / forbidden reads and writes.
- **Control plane is off-limits.** Agent file tools and shell redirects can
  never touch cmagent's own config dir (profiles, skills, API keys, config,
  data) — so an injected call can't escalate, plant a persistent injection, or
  steal keys.
- **Untrusted output is data.** `web_fetch` / `web_search` / MCP / browser
  output is wrapped with an anti-spoof "this is DATA" delimiter and scanned
  (detect-only) for injection signals.
- **OS sandbox when available.** Landlock (Linux), Bubblewrap, or Docker is
  auto-detected; the policy layers apply regardless.
- **Secret-leak detection** scrubs/blocks credentials in tool output;
  interactive commands (`sudo`, `ssh`) fail fast instead of hanging.

## Requirements

- No runtime dependencies — single static binary.
- Optional: a Chromium-family browser for the browser tools; language servers
  for `lsp_query`; API keys for web search.

### Browser automation (optional)

The browser tools (`browser_query`, `browser_act`, `browser_eval`) drive any
CDP-speaking browser. cmagent detects Chrome, Chromium, Edge, Brave, Vivaldi,
and Opera on PATH and launches a headless instance (`launch` mode, default);
`cmagent doctor` reports whether the tools are enabled.

To **attach to a browser you already have open** (typical: Windows + Edge),
switch to `connect` mode:

1. Start the browser with the debug port:
   ```sh
   msedge.exe --remote-debugging-port=9222          # Windows / Edge
   google-chrome --remote-debugging-port=9222       # Linux / Chrome
   ```
2. Fetch the WebSocket URL: `curl http://127.0.0.1:9222/json/version` and copy
   `webSocketDebuggerUrl`.
3. `cmagent config` → **Browser Tool Configuration** → set `mode = "connect"`
   and paste the URL into `connect_url`.
4. Restart cmagent; `cmagent doctor` should report `Browser tools: ENABLED`.

Only loopback URLs (`127.0.0.1`, `[::1]`, `localhost`) are accepted in
`connect_url`.

## Where things live

cmagent splits state between a **global install dir** (`~/.cmagent/`, override
with `CMAGENT_HOME`) and a **per-project workspace dir** (`<project>/.cmagent/`).

```
~/.cmagent/
├── config.toml          # [general] defaults, [security], [browser], ...
├── providers/           # one .toml per provider
├── agents/<name>/       # profiles: config.toml + AGENT.md (+ optional brain.db)
├── presets/             # shared agent baselines
├── skills/  channels/   # installed skills; channel adapter configs
├── mcp/servers.toml     # MCP server registry
├── cron/  ralph/        # cron schedules; Ralph task state
├── sessions/  data/     # global sessions; brain.db / audit.db / logs
└── .env                 # provider credentials (never commit)

<project>/.cmagent/
├── workspace.toml       # workspace defaults
├── sessions/<id>.db     # one SQLite DB per session (transcript + tool calls)
├── brain.db  tmp/  dl/  # workspace memory; agent scratch; channel downloads
└── tool-output/ screenshots/
```

Logs roll daily in `~/.cmagent/data/logs/`; run with `--debug` (or
`RUST_LOG=cmagent_core=trace`) for more. Add `.cmagent/` to your project's
`.gitignore` unless you want sessions and brain DBs in version control.

## Documentation

Full guides are in [docs/](docs/README.md): configuration, security model,
tools, interactive commands (`@`-files, `/steer`, copy), code intelligence,
channels, media (vision/TTS/STT), gateway, ACP, memory, skills, Ralph loop,
and update.

## License

MIT
