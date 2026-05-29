# Hooks & cron

Two ways to run things automatically: **hooks** fire a command on a
lifecycle event (a tool is about to run, a session started, a message
arrived); **cron** runs an agent prompt, shell command, or webhook on a
schedule.

## Hooks

A hook runs an external command when a cmagent event fires. The command
receives event context (e.g. the tool name and arguments for a
tool-call hook) on stdin, and its output can be surfaced back.

### Events

| Event | Fires when |
|---|---|
| `on_session_start` | a session starts |
| `on_session_end` | a session ends |
| `on_message_received` | a user message is submitted |
| `on_message_incoming` | a message arrives on a channel |
| `on_message_sent` | the agent sends a message out |
| `before_llm_call` | just before each LLM request |
| `before_tool_call` | before a tool runs (can gate it) |
| `on_after_tool_call` | after a tool produces its result |
| `on_heartbeat_tick` | on the periodic heartbeat |

### Configuration

Native hooks are TOML files in `~/.cmagent/hooks/`. cmagent also reads
**Claude Code `hooks.json`** files and bridges them, so an existing
Claude Code hook setup works as-is. The event names map:

| Claude Code | cmagent |
|---|---|
| `SessionStart` | `on_session_start` |
| `Stop` | `on_session_end` |
| `UserPromptSubmit` | `on_message_received` |
| `PreToolUse` | `before_tool_call` |
| `PostToolUse` | `on_after_tool_call` |

Matchers (the tool-name regex on `PreToolUse`/`PostToolUse`, the subtype
on `SessionStart`) are honoured; a malformed `hooks.json` is logged and
skipped, never blocking startup.

## Cron

Cron schedules recurring work. The scheduler runs inside the
[gateway](gateway.md) (it starts with `cmagent gateway`), so cron fires
whenever the gateway is up.

### Job shape

A job has a **trigger**, a **type** (what to run), a **session target**,
and a **delivery** mode.

- **Trigger**: `at` (one specific time), `every` (fixed interval),
  `cron` (a cron expression), `event` (fire on a cmagent event), or
  `manual` (only when run by hand).
- **Type**:
  - `agent_prompt` — run a prompt as an agent turn (the common case:
    "every morning, summarize yesterday's channel audit log" via the
    `sys-auditor` profile).
  - `shell` — run a shell command.
  - `webhook` — call an HTTP endpoint.
- **Session target**: `main` (the default session), `isolated` (a fresh
  throwaway session), or a `named` session.
- **Delivery**: `none`, `announce` (post the result to a channel), etc.

### Managing jobs

Cron jobs are created and managed by the agent through the
`cron_create` / `cron_list` / `cron_update` / `cron_delete` tools (the
gateway registers them), and persisted under `~/.cmagent/cron/`. A
typical setup: a scheduled `agent_prompt` job pointed at a dedicated
profile (e.g. `sys-auditor` for daily audit summaries), delivered to a
channel via `announce`.
