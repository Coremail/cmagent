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
  Chrome or Chromium on the host.

## License

MIT
