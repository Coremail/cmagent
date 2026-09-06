# cmagent Configuration Guide

Comprehensive reference for configuring cmagent -- directory layout,
provider setup, security policy, prompt assembly, and agent profiles.

## Table of Contents

- [Directory Layout](#directory-layout)
- [.env File](#env-file)
- [Provider Configuration](#provider-configuration)
- [Application Config (config.toml)](#application-config)
- [Config Loading Priority](#config-loading-priority)
- [MCP Server Configuration](#mcp-server-configuration)
- [System Prompt Assembly](#system-prompt-assembly)
- [Agent Profile System](#agent-profile-system)
- [Skills System](#skills-system)
- [Quick Start Examples](#quick-start-examples)
- [Moving a Configuration Between Machines](#moving-a-configuration-between-machines)

## Directory Layout

```text
~/.cmagent/
├── config.toml              # Global application config
├── .env                     # API keys (KEY=VALUE format)
├── providers/               # One TOML file per provider
│   └── {id}.toml
├── presets/                 # Reusable config presets
│   └── {id}.toml
├── mcp/
│   ├── servers.toml         # MCP server configs
│   └── manifest.toml        # MCP auto-discovery manifest
├── agents/                  # Agent profiles (v0.2+)
│   └── {name}/
│       ├── config.toml      # AgentProfile definition
│       └── *.md             # Personality/skill markdown files
├── skills/                  # Shared skill definitions
│   ├── manifest.toml        # Skill availability manifest
│   └── {id}/
│       └── *.md             # Skill content (concatenated alphabetically)
├── sessions/
│   └── {uuid}.db            # SQLite per-session history
├── data/
│   ├── brain.db             # SQLite global memory (FTS5 trigram search)
│   ├── audit.jsonl          # Hook/security event audit log (append-only JSONL)
│   ├── audit.db             # Channel inbound audit log (SQLite + FTS5; opt-in per account)
│   └── ralph.db             # Ralph long-task index (SQLite)
└── plugins/                 # External plugins (v0.2+)
```

| Directory/File | Format | Purpose |
|---|---|---|
| `config.toml` | TOML | Global app settings (security, storage, interface) |
| `.env` | KEY=VALUE | API keys, kept separate from config for security |
| `providers/*.toml` | TOML | One file per LLM provider; filename = provider ID |
| `presets/*.toml` | TOML | Reusable config fragments for agent profiles |
| `mcp/servers.toml` | TOML | MCP server definitions (command, args, env) |
| `mcp/manifest.toml` | TOML | Tracks MCP server sources, versions, availability |
| `agents/{name}/` | Directory | Agent profile: `config.toml` + `*.md` personality files |
| `skills/{id}/` | Directory | Skill: one or more `.md` files concatenated as prompt |
| `skills/manifest.toml` | TOML | Tracks skill sources, versions, availability |
| `sessions/{uuid}.db` | SQLite | Per-session conversation history (audit + context) |
| `data/brain.db` | SQLite | Global persistent memory (FTS5 trigram search, layered categories) |

Most files are optional. Missing files produce sensible defaults.
Run `cmagent init` to create the directory structure and set up
your first provider interactively.

## .env File

The `.env` file stores API keys separately from configuration for security.

**Location:** `~/.cmagent/.env`

**Format:**

```bash
# API keys for LLM providers
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
DEEPSEEK_API_KEY=sk-...
ZHIPU_API_KEY=abc123...

# Search engine keys
TAVILY_API_KEY=tvly-...
```

**Rules:**

- One `KEY=VALUE` per line
- Lines starting with `#` are comments
- Quoted values supported: `KEY="value"` or `KEY='value'` (quotes stripped)
- Empty lines are ignored
- **Does NOT override** existing shell environment variables -- if a var
  is already set in your shell, the `.env` value is skipped

**Loading:** `load_env_file()` in `src/main.rs` reads this file at
startup before any other initialization. Each key is set as a process
environment variable via `std::env::set_var`, but only when
`std::env::var(key)` returns `Err` (i.e., the var is not already set).

**Relation to providers:** Provider TOML files reference environment
variable *names* via `auth.api_key_env`. The actual secret lives in
`.env` (or your shell environment), never in the provider TOML itself.

## Provider Configuration

### Provider vs Backend

- **Backend**: the LLM API protocol implementation.
  Supported values: `"anthropic"`, `"openai"`, `"openai_compatible"`, `"glm"`.
- **Provider**: a named configuration that uses a backend.
  For example, "zhipu" uses `openai_compatible` backend with Zhipu's base URL.

Multiple providers can share the same backend. For instance, both
"deepseek" and "zhipu" can use `openai_compatible` with different
base URLs and models.

**Provider ID** = filename stem of `providers/{id}.toml`.

**Factory routing** is in `crates/cmagent-provider/src/factory.rs`:

| Backend | Implementation | Default base_url |
|---|---|---|
| `anthropic` | `AnthropicProvider` | `https://api.anthropic.com/v1` |
| `openai` | `OpenAiProvider` | `https://api.openai.com/v1` |
| `openai_compatible` | `OpenAiProvider` | (required -- no default) |
| `glm` | Auto-detect by URL | `https://open.bigmodel.cn/api/paas/v4` |

### ProviderConfig Fields

Full schema (parsed from `providers/{id}.toml`):

```toml
# Backend type (required)
backend = "anthropic"          # "anthropic" | "openai" | "openai_compatible" | "glm" | "openai_codex"
                                # openai_codex talks the Responses API at
                                # chatgpt.com/backend-api/codex with OAuth tokens
                                # imported from the codex CLI. See docs/codex-import.md.

# API endpoint (optional for anthropic/openai, required for openai_compatible)
base_url = "https://api.anthropic.com/v1"

# Model identifier (required)
model = "claude-sonnet-4-6"

# Sampling temperature: 0.0 - 2.0 (default: 0.7)
temperature = 0.7

# Maximum tokens in response (default: 4096)
max_tokens = 4096

# Human-readable description (optional)
description = "Anthropic Claude Sonnet"

# Retry settings (optional)
retry_max = 3                  # Max retry attempts
retry_backoff_ms = 1000        # Base backoff in milliseconds

# Fallback provider ID on failure (optional)
fallback_provider = "openai"

# --- Authentication ---
[auth]
method = "api_key"             # "api_key" | "oauth" | "custom_header"
api_key_env = "ANTHROPIC_API_KEY"  # Env var name (not the key itself)

# OAuth fields (when method = "oauth")
# token_url = "https://..."
# client_id_env = "CLIENT_ID"
# client_secret_env = "CLIENT_SECRET"
# scopes = ["scope1", "scope2"]
# token_cache = true

# Custom header auth (when method = "custom_header")
# [auth.headers_env]
# X-Custom-Auth = "MY_AUTH_TOKEN_ENV"

# --- Feature Flags ---
[features]
tool_calling = true            # Native tool calling support
vision = false                 # Image input support
thinking = false               # Extended thinking/reasoning mode
web_search = false             # Web search capability
mcp = true                     # MCP server integration
streaming = false              # Response streaming
max_context_tokens = 200000    # Context window size

# All feature fields are optional. Omitted fields use backend defaults:
#   anthropic: tool_calling=true, max_context_tokens=200000, mcp=true
#   openai:    tool_calling=true, max_context_tokens=128000, mcp=true
#   openai_compatible: tool_calling=true, max_context_tokens=128000

# --- Thinking/Reasoning ---
[thinking]
# Protocol type (inferred from backend if omitted)
protocol = "anthropic"         # "anthropic" | "openai"

# Anthropic protocol: token budget for thinking
budget_tokens = 10000

# OpenAI protocol: reasoning effort level
# reasoning_effort = "medium"  # "low" | "medium" | "high"
```

## Application Config

**Location:** `~/.cmagent/config.toml`

Full schema with defaults:

```toml
[general]
default_provider = ""          # Provider ID to use when none specified
log_level = "info"             # File log level: trace | debug | info | warn | error

[security]
# See docs/security-model.md for the full field reference.
prompt_threshold = "medium"    # "medium" | "high" | "never"
workspace_only = true          # Restrict file ops to workspace directory
max_actions_per_hour = 20      # Rate limit for tool actions
max_skill_risk = "high"        # "low" | "medium" | "high" (skills + MCP ceiling)
os_sandbox = "auto"            # "auto" | "enabled" | "disabled"
wasm_for_plugins = true        # Use WASM sandboxing for plugins (v0.2+)
sandbox_network = false        # Block network inside OS sandbox
sandbox_extra_read_paths = []  # App-level extra read-only sandbox mounts
sandbox_extra_write_paths = [] # App-level extra writable sandbox mounts

# Container sandbox settings (used when os_sandbox = "docker"/"podman" or auto-detected)
# Runtime: "auto" (podman preferred over docker), "podman", "docker"
sandbox_container_runtime = "auto"
sandbox_container_image = "alpine:latest"   # Container image
sandbox_container_memory_mb = 512           # Memory limit in MB
sandbox_container_cpu_limit = 1.0           # CPU limit (1.0 = 1 core)
sandbox_container_pids_limit = 256          # PID limit

# Browser cookie passthrough for web_fetch / http_request. App-level
# only -- no per-agent override. See docs/security-model.md.
cookie_domains = []            # Hosts that may receive real browser cookies
# [security.cookie_source]
# browser = "firefox"          # Which local browser to read cookies from
# profile = "abc123.work"      # Profile directory name (omit = default)

[security.paths]
forbidden = ["/etc", "/root", "~/.ssh", "~/.gnupg", "~/.aws"]

# Per-path permission overrides
# [[security.paths.permissions]]
# path = "/tmp/data"
# read = true
# write = true
# execute = false

[security.commands]
allowed = ["git", "cargo", "npm", "ls", "cat", "grep", "find", "echo",
           "mkdir", "touch", "rm", "cp", "mv", "python", "python3",
           "node", "bun"]

[security.network]
default_action = "block"       # "allow" | "block"
# [[security.network.rules]]
# pattern = "api.example.com"
# paths = ["/v1/*"]
# methods = ["GET", "POST"]
# action = "allow"

[storage]
history_backend = "sqlite"     # Session history backend
brain_backend = "sqlite"       # Global memory backend (default)

[interface]
default = "cli"                # Default interface (cli | tui | web)

[task_pool]
max_concurrency = 10           # Max concurrent sub-tasks
max_depth = 10                 # Max nesting depth for sub-agents

[sub_agent]
# default_provider = "fast-model"   # Provider ID for sub-agents (None = parent)
# planning_provider = "deep-model"  # Provider for deep planning (None = parent)
max_plan_duration_secs = 300        # Timeout for plan execution
```

## Logging

### Overview

cmagent uses dual-layer structured logging:

- **Console**: `warn` level only (silent during normal operation)
- **File**: rolling daily logs at `~/.cmagent/data/logs/`, 7-day retention

### CLI Flag

```bash
cmagent chat --debug          # File log level upgraded to debug
cmagent --debug -m "hello"    # Same for single-message mode
```

`--debug` upgrades the file log level to `debug`, adding tool arguments,
timing details, and (in debug builds only) HTTP request/response bodies.

### Config

```toml
[general]
log_level = "info"   # File log level (trace/debug/info/warn/error)
```

### What Each Level Shows

| Level | Content |
|-------|---------|
| `info` | Tool start/complete with duration, task pool stats, context compaction, MCP status |
| `debug` | Tool call arguments, provider request URLs, HTTP bodies (debug build only) |
| `warn` | Tool failures, security blocks, provider errors |
| `error` | MCP process errors, critical failures |

### HTTP Body Logging

HTTP request/response bodies (containing full prompts and tokens) are only
logged in **debug builds** (`cargo build`). Release builds (`cargo build --release`)
never log HTTP bodies, even with `--debug`, to prevent sensitive data leakage.

### Environment Override

`RUST_LOG` overrides console level for ad-hoc debugging:

```bash
RUST_LOG=debug cmagent chat    # Show debug output on console
RUST_LOG=trace cmagent chat    # Maximum console verbosity
```

### Log File Location

```text
~/.cmagent/data/logs/
  cmagent.log.2026-03-23       # Today
  cmagent.log.2026-03-22       # Yesterday
  ...                          # Auto-cleaned after 7 days
```

## Tool Risk Levels and Prompting

Tools are assigned a risk level in code: `low`, `medium`, or `high`.
The `prompt_threshold` setting in `[security]` (or per-agent override)
controls **at which risk level the user is prompted before the tool
runs**. Risk does not gate the call itself -- that is controlled by
the agent's explicit `tools = [...]` allowlist.

| Risk | Tools |
|------|-------|
| Low | file_read, list_dir, glob_search, content_search, history_search, brain, todo, update_plan, learn_rule, ask_user, diff_preview, tool_search, help, audit_query, messaging_query, web_fetch (+ browser_query, vision, screenshot, tts when present) |
| Medium | file_write, file_edit, apply_patch, trash, http_request, web_search, lsp_query, messaging_send, sessions_send, browser_act, MCP adapters |
| High | shell, spawn_agent, plan_tasks, skill_manager, browser_eval |

`web_fetch` and `http_request` both report **High**, regardless of their
table row above, for a URL whose host matches `[security] cookie_domains`
-- that call attaches a real browser cookie and acts as the logged-in
user. See [Browser Cookie Passthrough](security-model.md#browser-cookie-passthrough-cookie_domains--cookie_source)
for details.

**`prompt_threshold` semantics:**

- `medium` -- ask before medium + high risk tools (default for user agents)
- `high` -- ask only before high-risk tools (dev-style agents)
- `never` -- never ask (autonomous workers only)

Low-risk tools are always silent regardless of the threshold.

**Per-agent override** (edit `~/.cmagent/agents/<name>/config.toml`):

```toml
[security]
prompt_threshold = "high"
```

See `docs/security-model.md` for the full model (three gates, the
difference between tool risk and skill/MCP risk, how `extra_dirs` /
`brain_readonly` / `relaxed_shell` interact).

## Config Loading Priority

Configuration merges from multiple sources. Higher sources override lower:

```text
Built-in defaults  ->  config.toml  ->  Environment (CMAGENT_*)  ->  Session overrides
(lowest)                                                              (highest)
```

The `ConfigLoader` (in `crates/cmagent-config/src/loader.rs`) handles
this gracefully:

- **Missing files are OK** -- defaults are returned for any absent config
- **Partial TOML is OK** -- all structs use `#[serde(default)]`, so
  you only need to specify fields you want to change
- **Provider ID from filename** -- the `id` field is set from the
  `.toml` filename, not from TOML content

Provider resolution order at runtime:

1. CLI flag: `--provider <id>` or `-p <id>`
2. `config.toml`: `[general] default_provider`
3. First available provider (alphabetical by ID)

## MCP Server Configuration

**Location:** `~/.cmagent/mcp/servers.toml`

```toml
[servers.github]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
enabled = true

[servers.github.env]
GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_..."

[servers.filesystem]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]
enabled = true
```

Each server entry has:

| Field | Type | Default | Description |
|---|---|---|---|
| `command` | string | `""` | Command to launch the server |
| `args` | string[] | `[]` | Arguments to pass |
| `env` | map | `{}` | Environment variables for the server process |
| `enabled` | bool | `true` | Whether this server is active |

MCP servers are started during `cmd_chat`. Failed servers are
skipped with a warning. Successfully started servers register their
tools into the `ToolRegistry`.

### MCP Manifest

**Location:** `~/.cmagent/mcp/manifest.toml`

Tracks MCP server sources and default availability:

```toml
[servers.github]
source = "https://github.com/modelcontextprotocol/servers"
version = "0.1.0"
availability = "enabled"   # "enabled" | "optional" | "disabled"
```

Auto-discovery: `ConfigLoader::auto_discover_mcp()` scans for
subdirectories in `mcp/` containing `config.toml` and adds them
as `optional` entries in the manifest.

## System Prompt Assembly

The system prompt is rebuilt every turn by `Agent::build_system_prompt()`
in `crates/cmagent-core/src/agent.rs`. Sections are joined by `\n\n`,
and empty sections are filtered out.

| Order | Section | Source | Description |
|---|---|---|---|
| 1 | Identity | Hardcoded | Agent name + base description |
| 2 | Tools | `ToolRegistry` | Available tool specs (sub-agents exclude `plan_tasks`) |
| 3 | Security | `SecurityPolicy` | Autonomy level, workspace constraints, forbidden paths |
| 4 | Skills | `skills/{id}/*.md` | Shared skill prompts, in declaration order |
| 5 | Agent MD | `agents/{name}/*.md` | Agent personality files, priority-sorted |
| 6 | Workspace | Runtime | Working directory path + session ID |
| 7 | DateTime | Runtime | Current UTC timestamp (`YYYY-MM-DD HH:MM UTC`) |
| 8 | SubAgent | Hardcoded (depth=0 only) | Sub-agent capability description (`plan_tasks`, `spawn_agent`) |

### Agent MD Priority Order

When multiple `.md` files exist in an agent directory, they are sorted
by a predefined priority (defined in `crates/cmagent-config/src/agent.rs`):

```text
SOUL.md > IDENTITY.md > RULES.md > EXPERTISE.md > CONTEXT.md > TOOLS.md > USER.md > MEMORY.md > [others alphabetical]
```

Files not in the priority list are appended in lexicographic order.
This is how the agent-curated `LEARNED.md` (see [Learned Rules](#learned-rules-learnedmd))
is picked up: it is loaded just like a hand-written file, sorted after
the eight known names.

## Agent Profile System

### Default Agent

A default agent is created during `cmagent init` at `agents/default/`.
It contains a minimal `config.toml` and 8 markdown template files
(SOUL, IDENTITY, RULES, EXPERTISE, CONTEXT, TOOLS, USER, MEMORY).

These templates are embedded in the binary from `assets/agents/default/`.
Developers can customize the default agent by editing files in that
assets directory before building.

Select a different agent at runtime:

```bash
cmagent chat --agent my-agent
cmagent -a my-agent -m "hello"
```

Or set the default in `config.toml`:

```toml
[general]
default_agent = "my-agent"
```

### Directory Structure

Each agent is a directory under `agents/`:

```text
agents/
├── default/           # Created by init
│   ├── config.toml
│   ├── SOUL.md
│   ├── IDENTITY.md
│   ├── RULES.md
│   ├── EXPERTISE.md
│   ├── CONTEXT.md
│   ├── TOOLS.md
│   ├── USER.md
│   └── MEMORY.md
└── coder/             # Custom agent example
    ├── config.toml
    ├── SOUL.md
    └── EXPERTISE.md
```

The eight template files above are hand-written (or scaffolded by
`cmagent init`). One more file can appear in an agent directory that
**you do not create by hand** -- `LEARNED.md`, described next.

### Learned Rules (LEARNED.md)

`agents/{name}/LEARNED.md` is the agent's own rule book: durable,
always-on directives it has accumulated across sessions (a project
convention, a preference you keep correcting). It is loaded into the
system prompt exactly like `RULES.md` -- the only difference is who
writes it.

**Only the `learn_rule` tool writes this file**, and only after you
explicitly approve. When the agent proposes a rule it gets a `Save` /
`Discard` prompt; on `Save` the rule is appended as a single markdown
bullet with a provenance comment:

```markdown
# Learned rules

<!-- Curated by the agent via `learn_rule`, each entry user-approved.
This file is loaded into the agent's system prompt. Edit or delete
entries freely; lines starting with `- ` are the rules. -->

- Always run cargo fmt before committing.  <!-- learned 2026-05-29; user corrected this twice -->
```

Key properties:

- **Applies from the *next* session, not the current turn.** The file
  is read when the agent profile loads, so a freshly learned rule takes
  effect after a restart.
- **Per agent.** Each agent has its own `LEARNED.md`; a rule learned by
  `coding` does not affect `chat`.
- **Confirmation required.** Without an interactive session (cron,
  Ralph) the tool refuses rather than auto-writing, and it never touches
  `RULES.md`, `config.toml`, or any security field -- it writes this one
  file via its own path, never through the generic `file_write` tool.
- **Bounded.** Up to 100 rules / 8 KiB (it is in every system prompt).
  When full, `learn_rule` errors and asks you to prune the file.
- **Hand-editable.** It is plain markdown -- edit or delete bullets
  freely; lines starting with `- ` are the rules.

Use `learn_rule` for always-applicable directives; one-off facts or
contextual notes belong in the [`brain`](memory.md) memory tool instead.

### AgentProfile Fields

`agents/{name}/config.toml`:

```toml
description = "Expert coding assistant"

# Provider/model selection
endpoint = "claude"           # Provider ID from providers/
model = "claude-sonnet-4-6"   # Override provider's default model

# Preset references. For user (Main) agents built by the wizard,
# this list stays empty — preset content is flattened inline at
# creation. For built-in sub-/sys-agents, `presets = ["sys-default"]`
# pulls in the shared baseline at runtime. Setting presets here by
# hand is fine, and is what operators do to centrally adjust
# sub-/sys- permissions via `sys-default.toml`.
# presets = ["sys-default"]

# Skills to inject into system prompt
skills = ["code-review", "testing"]

# MCP servers (None = inherit global; [] = no MCP)
mcp_servers = ["github", "filesystem"]

# Tool allowlist (None = all tools; [...] = only these)
# tools = ["shell", "file_read", "file_write"]

# Tools to exclude (applied after all merging)
tools_exclude = ["web_search"]

# Final-answer presentation. "direct" = results-first: no preamble or
# process narration, the reply IS the deliverable (or the path of the
# file holding it). Absent = inherit `[general] output_style` from
# config.toml; set explicitly to override the global either way.
# output_style = "direct"

# Sandbox mode override
sandbox = "auto"               # "auto" | "enabled" | "disabled"

# Sub-agent endpoint IDs
# sub_agent_endpoints = ["fast-model"]

# Session behavior
[session]
max_tool_iterations = 10
# compaction_token_threshold = 100000

# Security overrides (see docs/security-model.md)
# [security]
# workspace_only = true
# prompt_threshold = "medium"         # "medium" | "high" | "never"
# max_skill_risk = "medium"           # ceiling for skills + MCP
# brain_readonly = false              # block brain remember/forget
# relaxed_shell = false               # downgrade shell NeedsConfirm
# forbidden_paths = ["/etc/secrets"]
# allowed_commands = ["git", "cargo"]
# [[security.extra_dirs]]
# path = "/data/shared"
# mode = "r"                          # any combo of r/w/x

# Search engine override
# [search]
# backend = "tavily"
# api_key_env = "TAVILY_API_KEY"
# max_results = 5
```

### Presets

Presets are pre-filled bundles of agent settings (tools, security,
session, brain scopes, ...). Two distinct ways they get used:

**1. Creation-time templates for user (Main) agents.**
When `cmagent config agent` → "Create a new agent" runs, the user
picks one or more presets. The wizard merges them, shows a preview,
and — on confirm — writes the result **inline** into the new
agent's `config.toml`. The agent carries no ongoing preset
reference; its TOML is self-describing. Edit flow, preset-create,
and preset-edit all go through the same field-by-field editor.

**2. Runtime baseline for built-in (Sub/Sys) agents.**
Each shipped sub-/sys-agent TOML carries `presets = ["sys-default"]`
so operators can adjust the shared baseline (prompt_threshold,
tools_exclude, ...) in one place rather than editing 11 agent files.
Per-agent inline fields still override the baseline — `sys-auditor`
sets `prompt_threshold="medium"` + `brain_readonly=true`,
`sys-ralph-worker` sets `prompt_threshold="never"`, and so on.

Runtime merge rule is the same for both paths:

```text
preset[0]  ->  preset[1]  ->  ...  ->  Agent profile
```

Later values overwrite earlier ones for scalars; list-union fields
accumulate; list-replace fields replace on any `Some`.

| Merge Type | Fields | Behavior |
|---|---|---|
| Scalar | endpoint, model, sandbox, prompt_threshold, max_skill_risk, workspace_only, brain_readonly, relaxed_shell, sandbox_network | Later `Some` overwrites |
| List-Replace | tools, mcp_servers, sub_agent_endpoints, allowed_commands | Later `Some` replaces entirely |
| List-Union | skills, tools_exclude, forbidden_paths, extra_dirs (by path) | Accumulated, deduplicated |
| Security | security block | Per-field (scalars overwrite, list fields as above) |

`session` and `search` are taken from the agent's own profile only
— the runtime preset-merge does not read them. (The wizard-time
`flatten_presets` does copy them into the inline profile on
creation, so wizard-created agents behave correctly.)

Shipped presets (installed by `cmagent init` into
`~/.cmagent/presets/`):

- `default`, `chat`, `coding`, `channel` — user-facing templates
  offered in the creation wizard.
- `sys-default` — runtime baseline for built-in sub-/sys-agents.
  The `sys-*` prefix makes the config wizard hide it from user
  pickers and list/edit/remove commands. Edit it by hand only.

Init always overwrites the shipped files so upgrades carry the
latest defaults. User customizations belong in preset files with
different names.

### Doctor checks

`cmagent doctor` validates that every agent's `presets = [...]`
references resolve to actual files. A missing `sys-default.toml`
surfaces as one concrete error per affected sub-/sys-agent.

After merging, `tools_exclude` is applied to remove unwanted tools,
then global `ToolsConfig` filters out disabled tools.

Resolution logic: `resolve_agent()` in `crates/cmagent-config/src/agent.rs`.
The wizard-time flatten (with identical merge rules, but producing
an inline `AgentProfile` instead of the hydrated runtime form) is
`flatten_presets()` in the same module. The inverse,
`profile_to_preset()`, supports the "Export as preset" action in
the agent-edit sub-menu.

## Skills System

Skills are prompt extensions that inject context into the agent on relevant turns.
Each skill is a directory under `~/.cmagent/skills/<name>/` containing a single
`SKILL.md` file.

### SKILL.md Format

`SKILL.md` uses YAML frontmatter followed by a markdown prompt body:

```markdown
---
name: pdf
version: "1.0.0"
description: PDF manipulation toolkit
activation:
  keywords: [pdf, document]
  tags: [files]
  exclude_keywords: []
  patterns: ["(?i)\\bpdf\\b"]
  max_context_tokens: 2000
requires:
  bins: [python3]
  env: []
---

## PDF Skill

Use `pdftotext` or `pdfplumber` (Python) to extract text from PDF files...
```

**Frontmatter fields:**

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Skill ID (must match directory name) |
| `version` | No | Semver string |
| `description` | No | One-line summary |
| `activation` | No | Scoring criteria (see below) |
| `requires` | No | Prerequisite binaries / env vars |

**Activation scoring** (per turn, deterministic — no LLM involved):

| Criterion | Points | Cap |
|---|---|---|
| Keyword exact word match | 10 pt each | 30 pt total |
| Keyword substring match | 5 pt each | 30 pt total |
| Tag match | 3 pt each | 15 pt total |
| Regex pattern match | 20 pt each | 40 pt total |
| Exclude keyword present | veto (score = 0) | — |

Skills with **no activation criteria** (empty keywords/tags/patterns) are always
active when declared by the agent (unconditional, score = 1).

### Skills Manifest

`~/.cmagent/skills/manifest.toml` tracks metadata for every skill:

```toml
[skills.pdf]
source = "https://clawhub.example/api/v1/download?slug=owner/pdf"
version = "1.0.0"
availability = "optional"
trust = "installed"      # explicit; inferred from source if absent

[skills.my-review]
availability = "optional"
# trust omitted + no source => Trusted (user-authored)
```

**Trust levels** (`trust` field):

| Value | Meaning |
|---|---|
| `trusted` | User-authored skill; full tool access |
| `installed` | Downloaded from registry; full tool access (user explicitly enabled) |

Trust is inferred when the field is absent: `source` present → `installed`, absent → `trusted`.

**Availability levels** (`availability` field):

| Level | Meaning |
|---|---|
| `enabled` | Active for all agents unconditionally |
| `optional` | Active only when agent lists it in `skills = [...]` |
| `disabled` | Globally blocked; no agent can use it |

### Per-Agent Enablement

Agents declare which optional skills they want in
`~/.cmagent/agents/<name>/config.toml`:

```toml
skills = ["pdf", "my-review"]
```

### CLI Commands

```
cmagent skill list                        # list all skills
cmagent skill install <slug>              # install from ClawHub or owner/repo GitHub
cmagent skill enable  <name> [--agent <a>]  # add to agent's skills list
cmagent skill disable <name> [--agent <a>]  # remove from agent's skills list
cmagent skill remove  <name>              # delete files + manifest entry
cmagent skill info    <name>              # show manifest + activation criteria
```

`install` downloads the SKILL.md, writes to `skills/<name>/`, and records the
source URL and `trust = "installed"` in `manifest.toml`. Directory name is taken
from the `name:` field in the downloaded SKILL.md.

### In-Session Skill Management (`skill_manager` tool)

The built-in `skill_manager` tool (risk: **High**) allows agents to manage skills
during a conversation:

```
skill_manager(action="list")
skill_manager(action="install", slug="pdf")
skill_manager(action="enable",  name="pdf")
skill_manager(action="disable", name="pdf")
skill_manager(action="info",    name="pdf")
```

Changes are persistent (written to config) but take effect **next session** only.
The current session's loaded skills are immutable to prevent mid-session prompt
injection.

## Quick Start Examples

### Minimal Provider Setup (Anthropic)

1. Run `cmagent init` and follow the wizard, or manually create:

**`~/.cmagent/.env`:**

```bash
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**`~/.cmagent/providers/claude.toml`:**

```toml
backend = "anthropic"
model = "claude-sonnet-4-6"
description = "Anthropic Claude Sonnet"

[auth]
api_key_env = "ANTHROPIC_API_KEY"
```

2. Start chatting: `cmagent chat`

### OpenAI-Compatible Provider (DeepSeek)

**`~/.cmagent/.env`:**

```bash
DEEPSEEK_API_KEY=sk-your-deepseek-key
```

**`~/.cmagent/providers/deepseek.toml`:**

```toml
backend = "openai_compatible"
base_url = "https://api.deepseek.com"
model = "deepseek-chat"
description = "DeepSeek Chat"

[auth]
api_key_env = "DEEPSEEK_API_KEY"
```

### OpenAI-Compatible Provider (Zhipu GLM)

**`~/.cmagent/.env`:**

```bash
ZHIPU_API_KEY=your-zhipu-key
```

**`~/.cmagent/providers/zhipu.toml`:**

```toml
backend = "openai_compatible"
base_url = "https://open.bigmodel.cn/api/paas/v4"
model = "glm-4-plus"
description = "Zhipu GLM-4 Plus"

[auth]
api_key_env = "ZHIPU_API_KEY"
```

### Provider With Thinking Enabled

**`~/.cmagent/providers/claude-thinking.toml`:**

```toml
backend = "anthropic"
model = "claude-sonnet-4-6"
max_tokens = 16384
description = "Claude with extended thinking"

[auth]
api_key_env = "ANTHROPIC_API_KEY"

[features]
thinking = true

[thinking]
protocol = "anthropic"
budget_tokens = 10000
```

### Multiple Providers With Fallback

**`~/.cmagent/providers/primary.toml`:**

```toml
backend = "anthropic"
model = "claude-sonnet-4-6"
description = "Primary provider"
fallback_provider = "backup"
retry_max = 2
retry_backoff_ms = 500

[auth]
api_key_env = "ANTHROPIC_API_KEY"
```

**`~/.cmagent/providers/backup.toml`:**

```toml
backend = "openai"
model = "gpt-4o"
description = "Backup provider"

[auth]
api_key_env = "OPENAI_API_KEY"
```

### Verifying Configuration

```bash
# Check system health
cmagent doctor

# List configured providers
cmagent provider list

# Test provider connectivity
cmagent provider ping

# Test a specific provider
cmagent provider ping claude
```

## Moving a Configuration Between Machines

The desktop app's Settings screen has an **Import / Export** panel
(`/api/settings/transfer/*`, desktop-only like every settings route). It
writes one JSON bundle holding the records you tick:

| Carried | Not carried |
|---|---|
| `providers/*.toml` | `channels/*` -- an account is a login on one platform |
| `agents/<name>/` (user agents; text files only) | `agents/<name>/brain.db` and the rest of `data/` |
| `presets/*.toml` | `gateway.toml`, its users and `CMAGENT_TOKEN_*` |
| `skills/<name>/` | `workspaces.toml`, `[browser]` paths |
| `mcp/servers.toml` entries | `sessions/`, `cron/`, `plugins/` |
| `config.toml`: `[general] [security] [search] [interface]` | every other `config.toml` table |

### Keys

Carrying API keys is a separate tick and requires a passphrase. The keys
are encrypted with it (ChaCha20-Poly1305 over a PBKDF2-HMAC-SHA256 key);
the rest of the bundle stays readable, so a file can be inspected before
it is imported. Which variables may be carried is decided by NAME, from
the channel catalog and the `CMAGENT_TOKEN_` prefix -- a provider file
naming a channel's variable as its `api_key_env` still does not carry
that token away.

A record whose key is on neither machine is marked "needs a key" in the
import plan, with a box to type it; what is typed wins over what the
bundle carried.

### What an import does not inherit

- A skill arrives with `Installed` trust and **no grants**. Tool,
  command and hook grants are the exporting user's consent, given on
  their machine.
- An MCP server arrives **disabled**. It is a command this machine would
  run.
- Records that already exist are **skipped** unless "replace" is ticked.

Bundles are versioned (`format_version`); a bundle written by a newer
cmagent is refused rather than partially understood.
