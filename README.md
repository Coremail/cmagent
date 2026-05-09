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
# First-time setup: configure a provider (e.g. Anthropic)
cmagent init

# Interactive chat
cmagent

# Single message
cmagent -m "Explain this codebase"

# Use a specific agent profile
cmagent --agent coding
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

## Modes

### Terminal (default)

`cmagent` opens an interactive TUI. `cmagent -m "..."` runs a single message
and exits. Both modes read from `~/.cmagent/` and write conversation history
to a local SQLite database.

### Gateway (HTTP API)

`cmagent gateway` starts a local HTTP API server (default port 3100). The
gateway exposes a REST and WebSocket interface so other tools, scripts, or
web frontends can send messages and receive streaming responses.

```sh
# Start the gateway
cmagent gateway --port 3100

# Connect the TUI to a remote gateway instead of a local provider
cmagent tui --remote http://host:3100 --token <token>
```

User accounts and bearer tokens are managed with `cmagent gateway user add`.

### ACP (Agent Client Protocol)

`cmagent acp` starts a stdio-based server that speaks the Agent Client
Protocol. Use this to embed cmagent as a subprocess inside another
application or IDE extension. The host sends JSON messages over stdin and
reads streaming responses from stdout.

```sh
cmagent acp --agent coding
```

## Requirements

- No runtime dependencies — single static binary.
- Browser tools (`browser_query`, `browser_act`, `browser_eval`) require
  Chrome or Chromium on the host.

## License

MIT
