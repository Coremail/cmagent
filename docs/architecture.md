# cmagent Architecture

A map of how the binary wires up and where each responsibility lives.
Targeted at contributors landing a feature; if you only want to use
cmagent see the README and `docs/configuration-guide.md`.

## Layered view

```
┌──────────────────────────────────────────────────────────────────┐
│                       User-facing surface                        │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │ TUI        │  │ Chat REPL  │  │ Gateway    │  │ ACP server │ │
│  │ (default)  │  │ (line I/O) │  │ (HTTP+WS)  │  │ (stdio)    │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘ │
└────────┼────────────────┼────────────────┼────────────────┼─────┘
         ▼                ▼                ▼                ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Interface layer (-interface)                  │
│  Terminal manager, panels, input buffer, paste-burst, soft-wrap, │
│  workspace browser, memory TUI, ask-user panel, theme/colors.    │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Agent loop (-core)                         │
│  ConfigLoader -> Provider -> ToolRegistry -> Agent::run         │
│    user message -> compaction check -> deterministic skill       │
│    selection -> system-prompt assembly -> provider call          │
│    (stream or complete) -> tool dispatch (native + 3 text fmts)  │
│    -> security gates -> append -> checkpoint -> loop.            │
└──────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Cross-cutting subsystems                     │
│  ┌────────┐  ┌────────┐  ┌─────────┐  ┌────────┐  ┌──────────┐  │
│  │provider│  │ tool   │  │security │  │storage │  │ channels │  │
│  │(LLM)   │  │(20+    │  │(4-layer │  │(SQLite │  │(Lunkr /  │  │
│  │        │  │tools)  │  │ stack)  │  │ +FTS5) │  │ TG/Slack │  │
│  └────────┘  └────────┘  └─────────┘  └────────┘  └──────────┘  │
│  ┌────────┐  ┌────────┐  ┌─────────┐  ┌────────┐                │
│  │ config │  │  mcp   │  │protocol │  │  lsp   │                │
│  │ schema │  │client  │  │ (A2A)   │  │ (lang) │                │
│  └────────┘  └────────┘  └─────────┘  └────────┘                │
└──────────────────────────────────────────────────────────────────┘
```

## Workspace crates

| Crate                | Owns                                                          |
|----------------------|---------------------------------------------------------------|
| `cmagent-config`     | TOML / YAML schemas, loader, provider/skill/MCP catalogs, OAuth helpers (Codex), env+keyring access. |
| `cmagent-storage`    | SQLite history + audit + Ralph state, SQLite brain store (FTS5 trigram search), schema migrations. |
| `cmagent-security`   | Input guard, application policy, OS sandbox (Landlock/bwrap/Docker/Noop), output safety. |
| `cmagent-provider`   | LLM backends (`openai`, `openai_compatible`, `openai_codex`, `anthropic`, `glm`), SSE streaming, auto reasoning. |
| `cmagent-tool`       | Built-in tools (file, shell, browser, search, memory, messaging, audit, ...), tool registry, schema cleaning. |
| `cmagent-mcp`        | MCP client + stdio server (model context protocol). |
| `cmagent-protocol`   | A2A inter-agent message framing. |
| `cmagent-channels`   | Inbound/outbound adapters for Lunkr, Telegram, Slack, Discord, WeChat. |
| `cmagent-gateway`    | HTTP + WebSocket gateway, multi-user RBAC, channel registration, cron scheduler/executor. |
| `cmagent-core`       | Agent loop, dispatcher, undo manager, skill selector, hooks, Ralph runner, hard-gate extraction. |
| `cmagent-interface`  | Terminal manager, scroll region, soft-wrap (grapheme-aware, scroll-to-cursor), paste-burst tracker, panels, workspace browser, memory TUI. |
| `cmagent-lsp`        | LSP code intelligence (definitions / references / hover / symbols / rename / file moves) behind the `lsp_query` tool. |
| `cmagent-media`      | Media backends: image vision, audio transcription (STT), text-to-speech (TTS), ffmpeg helpers. |

The binary crate (`cmagent`) sits on top: CLI parsing, command
dispatch (`init` / `tui` / `chat` / `gateway` / `acp` / `ralph` /
`doctor` / `config` / `skill` / `update`), and the `infra` module
that wires `ConfigLoader` -> Provider -> ToolRegistry -> Agent.

Dependency direction is strictly inward: `cmagent-tool` may use
`cmagent-config` and `cmagent-security`, never the reverse. The
binary crate is the only place that knows every subsystem.

## How a turn flows

1. User submits text in any front-end. The TUI's `tui2::event_loop`
   maps Enter to either submit or paste-newline via the
   `PasteBurstTracker`; the line-REPL just reads stdin.
2. Front-ends hand the message to `cmagent_core::Agent::run`.
3. The agent's pre-call pipeline:
   - Checks for `/` commands (slash-built-ins + skill commands).
   - Appends the user turn to context; runs progressive compaction
     if approaching `max_context_tokens`.
   - Runs deterministic skill selection (keyword/tag/regex score in
     `skill_selector.rs`) -- no LLM round-trip.
   - Builds the multi-section system prompt (identity, tools,
     security policy, active skills, workspace, datetime).
4. Sends the request to the configured provider:
   - SSE streaming when the provider supports it (Anthropic, OpenAI,
     Codex); fallback to non-streaming `complete()` otherwise.
   - Token deltas / thinking deltas push into `SharedState` so the
     TUI can render incrementally.
5. Tool calls:
   - Native tool calls come straight from the API JSON.
   - Falls back to text-extraction (XML / Markdown / GLM formats)
     for providers without native tool use.
   - Each call goes through input guard -> application policy ->
     `Tool::execute` (with sandbox) -> output safety.
6. Loop repeats up to `MAX_TOOL_ITERATIONS` (10) or until the model
   produces a final assistant message without tool calls.
7. Turn is checkpointed for `/undo` / `/redo` / `/retry`.

## Context compaction

When the conversation approaches the provider's `max_context_tokens`,
`ContextManager::auto_compact` runs at the start of each agent loop
iteration. The stage is picked by usage ratio:

| Ratio of max_context | Stage | What runs |
|---|---|---|
| 80% | Mask | tool result content -> `[ref: N chars, see history]` placeholders for older results |
| 85% | Prune | mask + drop older tool result content entirely |
| 90% | Aggressive | mask + prune + truncate older messages to half capacity |

Aggressive truncation drops older messages and feeds them to the
compaction LLM, which writes a structured summary
(`## Objective` / `## Pending User Asks` / `## Open Issues` /
`## Exact Identifiers` / etc). The summary is injected as a user-role
message right after the system block; old summaries are condensed by
section priority -- Pending User Asks and Exact Identifiers always
survive condensing, Technical Context fragments first.

`sanitize_kept_tail` cleans the truncation boundary before commit so
the resulting message array is provider-valid: no orphan tool_result
(no preceding assistant tool_use), no orphan tool_calls (assistant
tool_use with missing tool_result), and no leading user message that
would collide with the summary user-message (Anthropic alternation
rule).

Token counting includes every field that consumes provider context:
`content`, `tool_calls` JSON, `reasoning_content` (DeepSeek thinking
chains), `codex_reasoning_items` (OpenAI Responses encrypted blobs),
and images (~1000 tokens per image). The previous content-only
estimator systematically underestimated, delaying compaction past
the real wire limit.

`/compact` (manual) bypasses the staged path and runs the full
mask+prune+aggressive sequence regardless of usage ratio.

## Per-session persistence

The session DB (`<workspace>/.cmagent/sessions/<id>.db`) carries
three blocks of state that survive a process restart:

| State | Column | Loaded on | Saved on |
|---|---|---|---|
| Conversation messages | `context_state.messages` | `ContextManager::load` | end of every turn |
| Tool tree (for TUI resume) | `context_state.tool_outputs_json` | `ContextManager::load` | end of every turn |
| Session todo list | `context_state.todos_json` | `ContextManager::load` | end of every turn |

The agent loop persists these together via `Agent::save_context`,
which:

1. Snapshots `state.tool_outputs` -> `context.tool_outputs_json`
2. Serializes `agent.todos` (the `SharedTodoList`) -> `context.todos_json`
3. Calls `context.save()` which writes all three columns

Saving raw via `context.save()` would persist stale sidecar
columns (the tool tree and todos that haven't been re-synced from
the live agent state). All save sites in the agent loop and
in `/compact` route through `save_context` for this reason.

The longest unsaved window is therefore one turn -- a crash
mid-turn loses everything in that turn, but the previous turn's
state is durable. Tasks queued before the crash are still
present when the user resumes the session.

`/clear` resets all three blocks together (messages get
archived to a separate table; tool_outputs and todos are
dropped). New sessions and session switches re-seed in-memory
state from the new session's columns via
`Agent::reset_session`.

## Streaming + rendering pipeline

```
Provider stream -> StreamEvent -> SharedState.streaming_text
                                              streaming_thinking
                                              live_tools
                       │
                       ▼
   TUI render tick (per-keystroke + ~50ms idle)
     - render scroll region (chat history, append-only)
     - render fixed bottom area (status bar + soft-wrapped input)
     - render activity tree (when /verbose)
```

The soft-wrap walks plain + styled in lockstep, breaks at grapheme
clusters so emoji/CJK survive, and scrolls the visible window so the
cursor stays on screen. See `crates/cmagent-interface/src/terminal.rs`
`wrap_input_visual` + `scroll_start_for_cursor`.

## Security model (4 layers)

| Layer | Component | Always on? |
|-------|-----------|-----------|
| 0     | Input guard (injection detection, secret scan)    | Yes |
| 1     | Application policy (path rwx, command allowlist)  | Yes |
| 2     | OS sandbox (Landlock / bwrap / Docker / Noop)     | Auto-detect |
| 3     | Output safety (truncate, leak detect, scrub)      | Yes |

Layer 2 is detected at startup (`cmagent-security::sandbox::detect_sandbox`)
and varies by platform. The other three always run.

## Extension points

Trait-and-factory pattern throughout. To extend cmagent, implement
the trait and register in the factory module:

| Trait             | Crate             | File                          |
|-------------------|-------------------|-------------------------------|
| `Provider`        | cmagent-provider  | `src/traits.rs`               |
| `Tool`            | cmagent-tool      | `src/traits.rs`               |
| `HistoryStore`    | cmagent-storage   | `src/traits.rs`               |
| `BrainStore`      | cmagent-storage   | `src/traits.rs`               |
| `Sandbox`         | cmagent-security  | `src/sandbox.rs`              |
| `Interface`       | cmagent-interface | `src/traits.rs`               |
| `ToolDispatcher`  | cmagent-core      | `src/dispatcher/mod.rs`       |
| `UndoManager`     | cmagent-core      | `src/undo.rs`                 |
| `Skill`           | cmagent-config    | `src/skill.rs` (SKILL.md)     |
| `ChannelAdapter`  | cmagent-channels  | `src/channel.rs` (in/out)     |

## Where to look for ...

| Topic                                  | Start here                                                |
|----------------------------------------|-----------------------------------------------------------|
| Provider wire format                   | `crates/cmagent-provider/src/{openai,anthropic,openai_codex}.rs` |
| Tool execution loop                    | `crates/cmagent-core/src/agent/run.rs`                    |
| Skill selection scoring                | `crates/cmagent-core/src/skill_selector.rs`               |
| SSE streaming + back-pressure          | `crates/cmagent-provider/src/{base,sse}.rs`               |
| TUI input rendering + scrolling        | `crates/cmagent-interface/src/terminal.rs`                |
| Paste-burst recovery                   | `crates/cmagent-interface/src/paste_burst.rs`             |
| Auto reasoning-effort                  | `crates/cmagent-provider/src/auto_reasoning.rs`           |
| Memory TUI / brain review              | `crates/cmagent-interface/src/memory_tui.rs`              |
| Ralph Loop runner                      | `crates/cmagent-core/src/ralph/`                          |
| Outbound channel dispatch              | `crates/cmagent-channels/src/outbound/`                   |
| Cross-channel audit query              | `crates/cmagent-tool/src/builtin/audit_query.rs`          |
| Hooks (9 lifecycle points + matcher)   | `crates/cmagent-core/src/hooks.rs`                        |
| Cron scheduler                         | `crates/cmagent-core/src/cron.rs`                         |
| Sub-agent spawn                        | `crates/cmagent-core/src/spawner.rs`                      |
| Codex CLI auth import                  | `crates/cmagent-config/src/{codex_auth,codex_oauth}.rs`   |
| Provider model probing (Ollama / LM)   | `crates/cmagent-config/src/provider_probe.rs`             |

## Constraints to keep in mind

- **ASCII-only in `src/` and `crates/*/src/`.** Tests, benches, and
  docs may use Unicode.
- **Zero warnings** under `cargo clippy --all-targets -- -D warnings`.
- **No `.unwrap()` / `.expect()`** in production code; use
  `thiserror` errors per crate and `anyhow` at binary boundaries.
- **No mocks in tests.** Use real implementations, `tempfile` for
  scratch dirs, and dedicated stubs when a real impl isn't possible.
- **No mixed commits** (logic + formatting + unrelated cleanup).
- **No `super::`** imports; prefer `crate::`.

See `CLAUDE.md` for the full engineering principles.

## Known follow-ups

These are deliberately-deferred pieces, recorded here so they don't
get reinvented:

- **Retry-attempt UI indicator.** The retry loop itself lands in
  `crates/cmagent-provider/src/retry.rs` and is engaged whenever
  `retry_max > 0` in a provider config, but there's no live
  status-bar indicator that shows "retrying (attempt N of M)" while
  it's happening -- only the tracing logs surface it. Worth adding
  once the retry wrapper proves to be in regular use.
- **Codex Phase B live validation.** The `openai_codex` provider
  was implemented from vendor-code reverse-engineering, not against
  a live ChatGPT account. Model id (`gpt-5.5`), Responses API
  field names, and SSE event names may need tweaking the first
  time a real account exercises them; the SSE parser uses
  `#[serde(other)]` for unknown items so failures should degrade
  rather than panic.
