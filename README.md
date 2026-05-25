# cmagent

A terminal-based AI agent. Supports Anthropic, OpenAI-compatible, and GLM providers.
Runs on Linux, macOS, and Windows.

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

Download the binary for your platform directly from the
[Releases](https://github.com/Coremail/cmagent/releases/latest) page,
extract the archive, and place the binary somewhere on your PATH.

| Platform        | File                              |
|-----------------|-----------------------------------|
| Linux x86\_64   | `cmagent-linux-x86_64.tar.gz`    |
| macOS aarch64   | `cmagent-macos-aarch64.tar.gz`   |
| Windows x86\_64 | `cmagent-windows-x86_64.zip`     |

Each archive contains a single binary (`cmagent` or `cmagent.exe`) and a
`.sha256` checksum file.

## Quick start

```sh
# First time only: configure a provider (e.g. Anthropic)
cmagent init

# Most common: launch the full-screen TUI
cmagent tui

# Run without args to get a menu (TUI / line chat / gateway / config / status)
cmagent

# One-shot: send a single message and exit (non-interactive)
cmagent -m "Explain this codebase"

# Pick an agent profile (default reads from ~/.cmagent/config.toml)
cmagent tui --agent coding
```

## Update

```sh
cmagent update
```

Checks GitHub for a newer release, downloads the correct binary for your
platform, verifies the checksum, and replaces the running executable in place.
Add `--yes` to skip the confirmation prompt.

## Configuration

Config lives in `~/.cmagent/`. Run `cmagent init` to set up providers and
preferences interactively, or `cmagent config` to edit settings at any time.

Provider credentials are stored as environment variables. For Anthropic:

```sh
export ANTHROPIC_API_KEY="sk-ant-..."
```

If you already use the [OpenAI Codex CLI](https://github.com/openai/codex),
`cmagent config provider -> Import from Codex CLI` re-uses the credentials
already in `~/.codex/auth.json` (both API-key and ChatGPT-account OAuth
flows are supported). See [docs/codex-import.md](docs/codex-import.md).

See `cmagent doctor` to verify your setup.

## Commands

### Default (`cmagent`)

With no arguments, opens a menu picker (TUI / Chat / Gateway / Config /
Status / Doctor). Useful when you want to switch interaction modes
without remembering the subcommand. On first launch this also triggers
the setup wizard.

### `cmagent tui` — full-screen TUI (recommended)

The primary interactive mode. Renders a scrollable chat pane, live
tool/thinking tree, status bar, and rich input with paste folding,
slash commands, and per-turn editing. This is the mode most users want
day-to-day.

```sh
cmagent tui                                 # default workspace + agent
cmagent tui --agent coding                  # pick an agent
cmagent tui -c                              # continue the most recent session
cmagent tui --session <id>                  # resume a specific session
cmagent tui --remote http://host:3100 --token <tk>  # connect to a remote gateway
```

#### Two TUIs: canvas (default) and streaming

cmagent ships two interactive front-ends. Both speak to the same
agent, share `/slash` commands, sessions, and config; they differ
only in how they paint the screen.

| Variant | What it is | When to pick it |
|---|---|---|
| `canvas` *(default)* | ratatui-based, multi-pane (transcript / sidebar / input). Mouse selection, in-place permission modals, live activity tree, sidebar showing tokens / context / git branch / MCP / todos / agent activity. | Local terminal, fast tty. Best at-a-glance signal density. |
| `streaming` | Print-based, prints into the terminal's native scrollback. No alt-screen takeover; selection works via the terminal's normal copy/paste. | High-latency SSH, very wide remote sessions, recording demos with `script(1)`, terminals that mangle alt-screen. |

Selection priority:

1. CLI flags `--canvas` / `--streaming` — force the named variant
   for this session. Mutually exclusive.
2. Config `[general] default_tui` — `"canvas"` (default) or `"streaming"`.
3. Built-in fallback — `"canvas"`.

Change the default via `cmagent config` → `Defaults` → `Default TUI`,
or edit `~/.cmagent/config.toml` directly:

```toml
[general]
default_tui = "streaming"
```

`cmagent` (no args) and `cmagent tui` (no flag) both honour the
config. `cmagent tui --canvas` or `cmagent tui --streaming`
override it for one session.

### `cmagent chat` — line-based REPL

Plain stdin/stdout REPL with no fullscreen takeover. Useful inside
restricted terminals, log scrapers, or when piping output. No mouse, no
panels — just `>` prompt + response.

```sh
cmagent chat --agent coding
cmagent chat -c
```

### `cmagent -m "..."` — single message

Non-interactive one-shot: send the message, print the agent's reply,
exit with a non-zero code on tool/policy errors. Ideal for scripts,
cron, and CI hooks.

```sh
cmagent -m "Summarize CHANGELOG.md" --agent docs
echo "review this diff" | cmagent -m "$(cat -)"
```

### `cmagent gateway` — HTTP API

Local HTTP server (default port 3100) exposing REST + WebSocket so other
tools, scripts, or web frontends can drive the agent.

```sh
cmagent gateway --port 3100
cmagent tui --remote http://host:3100 --token <token>  # remote TUI client
```

User accounts and bearer tokens are managed with `cmagent gateway user add`.

### `cmagent acp` — IDE / external tool protocol

Stdio-based JSON-RPC 2.0 server speaking the Agent Client Protocol. Use
this to embed cmagent as a subprocess inside another application or IDE
extension.

```sh
cmagent acp --agent coding
```

### `cmagent ralph` — long iterative tasks

Runs a long task as a series of short, independent iterations. Each
iteration spawns a fresh agent session that reads the workspace, takes
one small step, updates `STATUS.md`, and exits. The loop continues until
the agent writes a `done` sentinel or `max_iter` is reached.

Use it for tasks too large for a single conversation — bulk refactors,
language ports, multi-step migrations.

```sh
cmagent ralph new "Port http client from reqwest to ureq"
# (edit ~/.cmagent/ralph/<id>/prompt.md)
cmagent ralph run <id>
cmagent ralph status <id> | tail
```

### Utility commands

```sh
cmagent init          # first-time setup wizard
cmagent config        # interactive config editor
cmagent doctor        # diagnostics (providers, sandbox, skill deps, ...)
cmagent workspace     # browse / delete / rename saved sessions
cmagent skill <cmd>   # list / install / setup / enable / disable skills
cmagent brain <cmd>   # inspect long-term memory
cmagent mcp <cmd>     # manage MCP servers
cmagent update        # update the binary in place
```

## Requirements

- No runtime dependencies — single static binary.
- Browser tools (`browser_query`, `browser_act`, `browser_eval`) require
  a Chromium-family browser on the host. See below.

### Browser automation (optional)

The three browser tools drive any CDP-speaking browser. cmagent detects
Chrome, Chromium, Microsoft Edge, Brave, Vivaldi, and Opera on PATH and
launches a headless instance automatically (`launch` mode, default).
Run `cmagent doctor` to see whether the tools are currently enabled.

If you want cmagent to **attach to a browser you already have open** —
typical case: Windows + Edge — switch to `connect` mode:

1. Start the browser with the debug port:
   ```sh
   msedge.exe --remote-debugging-port=9222          # Windows / Edge
   google-chrome --remote-debugging-port=9222       # Linux / Chrome
   ```
2. Fetch the WebSocket URL:
   ```sh
   curl http://127.0.0.1:9222/json/version
   ```
   Copy the `webSocketDebuggerUrl` field from the response.
3. Run `cmagent config` → **Browser Tool Configuration** → set
   `mode = "connect"` and paste the URL into `connect_url`.
4. Restart cmagent. `cmagent doctor` should report
   `Browser tools: ENABLED`.

Only loopback URLs (`127.0.0.1`, `[::1]`, `localhost`) are accepted in
`connect_url`. Remote CDP endpoints are rejected at config time.

## Directory layout

cmagent splits state between a **global install directory** (one per
user, holds all config, credentials, long-term memory, logs) and a
**workspace directory** (one per project, holds per-project sessions,
brain, scratch files).

### Global install: `~/.cmagent/`

Root is `~/.cmagent/` on Linux/macOS, `%USERPROFILE%\.cmagent\` on
Windows. Override with the `CMAGENT_HOME` environment variable.

```
~/.cmagent/
├── config.toml             # [general] defaults, [security], [browser], ...
├── providers/              # one .toml per provider (anthropic, glm, openai-compat, ...)
│   └── claude-default.toml
├── agents/                 # agent profiles
│   └── <name>/
│       ├── config.toml     # profile (presets, tools, prompt_threshold, ...)
│       ├── AGENT.md        # the agent's system-prompt body
│       └── brain.db        # (optional) agent-private long-term memory
├── presets/                # shared agent baselines (sys-default, ...)
├── skills/                 # installed skills (one dir per skill)
├── channels/               # channel adapter configs (lunkr, telegram, slack, ...)
├── mcp/
│   └── servers.toml        # MCP server registry
├── plugins/                # installed Claude Code plugin bundles
├── adapters/               # legacy adapter shims
├── cron/                   # cron-schedule TOMLs
├── ralph/<task-id>/        # Ralph loop task state (prompt.md, STATUS.md, iter logs)
├── sessions/<id>/          # global (non-workspace) session JSON
├── data/
│   ├── brain.db            # global long-term memory (SQLite + FTS5)
│   ├── audit.db            # channel inbound audit log (when enabled)
│   ├── ralph.db            # Ralph task index
│   └── logs/
│       ├── cmagent.log.YYYY-MM-DD   # daily rolling app log
│       └── panics.log               # panic backtraces (TUI mode)
├── workspaces.toml         # registry of known project workspaces
├── remotes.toml            # saved `--remote` gateway URLs + tokens
├── gateway.toml            # gateway server config
├── gateway.pid             # gateway process PID (when running)
├── stt.toml / tts.toml / vision.toml  # media backend configs
└── .env                    # provider credentials (ANTHROPIC_API_KEY, ...)
```

**Logs**: text logs land in `~/.cmagent/data/logs/cmagent.log.YYYY-MM-DD`
(daily rotation, kept indefinitely — clean up by hand). Console only
shows WARN+. Run with `--debug` to bump the file level to DEBUG; set
`RUST_LOG=cmagent_core=trace` for finer per-module control.

**Credentials**: never commit `.env`. The installer / `cmagent init`
sets the right permissions; if you copy this directory between
machines, copy `.env` separately and out-of-band.

### Workspace: `<project>/.cmagent/`

Created lazily the first time you launch cmagent inside a directory.
Everything here is scoped to that one project.

```
<project>/.cmagent/
├── workspace.toml          # workspace defaults (temp_provider / temp_model overrides,
│                           # known sessions, display preferences like show_activity)
├── brain.db                # workspace-scoped long-term memory
├── sessions/
│   ├── <uuid>.db           # one SQLite DB per session (transcript + tool calls)
│   └── telegram-<chat>.db  # channel-bound sessions use a stable id, not UUID
├── tmp/                    # agent scratch space (file_write to relative paths, etc.)
├── tool-output/            # overflow storage for large tool outputs the chat
│                           # transcript truncated (referenced via file://...)
├── screenshots/            # `screenshot` tool drops PNGs here
├── dl/                     # channel adapters store downloaded attachments here
└── skills/                 # workspace-local skill overlays (optional)
```

The `tmp/` directory is the agent's safe scratch area. The sandbox's
default policy whitelists writes inside the workspace; paths outside
(`/tmp/...`, `~/Documents/...`) get rejected.

Add `.cmagent/` to your project's `.gitignore` unless you want sessions
and brain DBs in version control.

## License

MIT
