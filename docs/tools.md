# Tools

Tools are the actions an agent can take. Every tool call passes through
the [security model](security-model.md) before it runs, and each tool
carries a **risk level** — `Low` (always silent), `Medium`, or `High` —
that, together with the agent's `prompt_threshold`, decides whether you
are asked first.

An agent profile's `tools = [...]` allowlist is the hard outer limit: a
tool not listed there can never run, no matter what. A profile with **no**
`tools` key gets every registered tool minus `tools_exclude`. See
[configuration-guide.md](configuration-guide.md) for how to scope a
profile.

Some tools register only when their backend is available (a browser on
PATH, a configured search provider, a channel account, an MCP server),
so the exact set an agent sees depends on your environment. Run
`cmagent doctor` to see what's active.

## Files & editing

| Tool | Risk | What it does |
|---|---|---|
| `file_read` | Low | Read a file (UTF-8 text with line offset/limit, or a binary hex dump). |
| `file_write` | Medium | Create or overwrite a file. |
| `file_edit` | Medium | Exact string-replace edits; pass an `edits` array for several at once. CRLF/indent/smart-quote tolerant. |
| `apply_patch` | Medium | Apply a structured patch or unified diff across one or more files; also create/delete/move files and **resolve git merge conflicts** (`*** Resolve Conflict: <path> #N`). Prefer this for multi-file or fuzzy edits. |
| `list_dir` | Low | List a directory. |
| `trash` / `file_delete` | Medium | Move a file to the OS trash (recoverable) instead of unlinking. |
| `diff_preview` | Low | Render a diff for review. |

## Search & code intelligence

| Tool | Risk | What it does |
|---|---|---|
| `content_search` | Low | Regex/literal search of file contents. gitignore-aware (skips `target/`, `node_modules/`, `.git/`); `include_ignored: true` to override. |
| `glob_search` | Low | Find files by glob (`**/*.rs`). Also gitignore-aware. |
| `lsp_query` | Medium | Language-server code intelligence: `definition`, `references`, `hover`, `symbols` (token-lean file outline with line spans), `rename` (project-wide symbol rename, applied), `rename_file` (move a file and update every import/`mod`/re-export). See [lsp.md](lsp.md). |
| `history_search` | Low | Search prior sessions' transcripts. |

## Shell & web

| Tool | Risk | What it does |
|---|---|---|
| `shell` | High | Run a command. The command parser blocks dangerous shapes even under `never`; the allowlist + path policy still apply. |
| `web_fetch` | Low | Fetch a URL as text/markdown. Output is wrapped as untrusted data. |
| `web_search` | Low | Web search via the configured backend (Tavily / Brave / Serper / DuckDuckGo). Registered only when a backend is set. |
| `http_request` | Medium | Make an arbitrary HTTP request. |

## Memory, planning & sub-agents

| Tool | Risk | What it does |
|---|---|---|
| `brain` | Low | Read/write long-term memory across global / workspace / agent layers. See [memory.md](memory.md). |
| `learn_rule` | Low | Append a user-confirmed rule to the agent's `LEARNED.md` (loaded next session). |
| `update_plan` | Low | Maintain the session `/plan` roadmap. |
| `todo` | Low | Maintain the session `/todos` checklist. |
| `plan_tasks` | Medium | Fan work out across sub-agents and collect results. |
| `spawn_agent` | Medium | Spawn a sub-agent (`sub-coder`, `sub-reviewer`, …) for an isolated task. |
| `ask_user` | Low | Ask the operator a question mid-task. |
| `skill_manager` | Medium | Install / enable / disable skills (a sanctioned control-plane writer). |
| `tool_search` | Low | Discover and activate tools that aren't in the active set. |

## Browser (optional)

Registered only when a Chromium-family browser is available (see the
README's *Browser automation* section). All output is marked untrusted.

| Tool | Risk | What it does |
|---|---|---|
| `browser_query` | Low | Navigate, screenshot, snapshot, read text. |
| `browser_act` | Medium | Click, type, scroll, press keys. |
| `browser_eval` | High | Run arbitrary in-page JavaScript. |

## Messaging & channels (optional)

Registered when a channel account is configured. See
[channels.md](channels.md).

| Tool | Risk | What it does |
|---|---|---|
| `messaging_query` | Low | Read surface: list channels/chats/contacts, list/search messages, download attachments. |
| `messaging_send` | Medium | Write surface: send messages/files, edit/delete, buttons, `notify` an operator. Gated per-account by `allow_outbound_send`. |
| `audit_query` | Low | Query the cross-channel inbound audit log (only the `sys-auditor` profile lists it by default). |
| `sessions_send` | Medium | Send a message to another agent session (A2A). |

## Media (optional)

| Tool | Risk | What it does |
|---|---|---|
| `screenshot` | Medium | Capture the screen (platform tool required). |
| `vision` | Low | Describe an image via a vision model (when a vision backend is configured). |
| `tts` | Low | Text-to-speech (when a TTS backend is configured). |

## Extending the tool surface

Beyond the built-ins, an agent's tools can be augmented by:

- **MCP servers** — external tools exposed over the Model Context
  Protocol, registered per agent. See `cmagent mcp` and
  [configuration-guide.md](configuration-guide.md).
- **Skills** — bundled prompt + (optionally) commands that can attenuate
  or extend behaviour. See [skill-slash-commands.md](skill-slash-commands.md)
  and [skill-packages.md](skill-packages.md).
