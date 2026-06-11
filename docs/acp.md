# ACP (Agent Client Protocol)

`cmagent acp` starts a JSON-RPC 2.0 server on stdin/stdout that implements
the Agent Client Protocol (ACP v0.19). External tools — such as IDE
extensions (Zed) — spawn the process and communicate via newline-delimited
JSON.

## Quick start

```sh
cmagent acp
cmagent acp --agent coding
```

The process reads JSON-RPC messages from stdin and writes responses and
notifications to stdout. Each message is a single JSON object on one line
terminated by `\n`. The process exits when stdin is closed.

## When to use ACP vs Gateway

| | ACP | Gateway |
|---|---|---|
| Transport | stdin/stdout | HTTP + WebSocket |
| Session model | One process per client | Multiple clients, shared server |
| Lifecycle | Managed by the host process | Long-running daemon |
| Best for | IDE extensions, subprocess embedding | Remote access, web UI, scripts |

Use ACP when your tool spawns cmagent as a child process and owns its
lifecycle. Use the gateway when you need a persistent server or multiple
simultaneous clients.

## Protocol

JSON-RPC 2.0 framing: every request/response/notification is one JSON
object on its own line. Requests carry an `id`; notifications omit it.

### `initialize`

Sent by the client immediately after connecting. Returns the protocol
version and the agent's capabilities.

Request:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientInfo":{"name":"my-ide","version":"1.0"}}}
```

Result:

```json
{"jsonrpc":"2.0","id":1,"result":{
  "protocolVersion":1,
  "agentInfo":{"name":"cmagent","version":"0.3.2","title":"cmagent (project)"},
  "agentCapabilities":{
    "loadSession":true,
    "promptCapabilities":{"supportedContentTypes":["text","image"]},
    "sessionCapabilities":{}
  }
}}
```

### `session/new`

```json
{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/path/to/project"}}
```

Result is `{"sessionId":"<uuid>"}`. The `cwd` becomes the session's
workspace and determines which config, skills, and MCP servers are
active. Immediately after, the agent emits an `available_commands_update`
and a `session_info_update` notification (see below).

### `session/load`

Reopen a previously created session by id.

```json
{"jsonrpc":"2.0","id":3,"method":"session/load","params":{"sessionId":"<uuid>","cwd":"/path/to/project"}}
```

Result is `{"sessionId":"<uuid>"}`. Before the result, the agent **replays
the persisted conversation** as `session/update` notifications
(`user_message_chunk` / `agent_message_chunk`) so the client can rebuild
the transcript instead of showing a blank session.

### `session/list`

```json
{"jsonrpc":"2.0","id":4,"method":"session/list","params":{"cwd":"/path/to/project"}}
```

Result:

```json
{"jsonrpc":"2.0","id":4,"result":{"sessions":[
  {"sessionId":"<uuid>","cwd":"/path/to/project","title":"…","updatedAt":"…"}
]}}
```

### `session/prompt`

The prompt is an array of content blocks (`text` or `image`).

```json
{"jsonrpc":"2.0","id":5,"method":"session/prompt","params":{"sessionId":"<uuid>","prompt":[{"type":"text","text":"Explain this function"}]}}
```

While the turn runs, the agent streams `session/update` notifications
(below). When the turn finishes, the request gets its result:

```json
{"jsonrpc":"2.0","id":5,"result":{"stopReason":"end_turn","usage":{"inputTokens":1200,"outputTokens":340}}}
```

`stopReason` is `"end_turn"` normally, or `"cancelled"` if the turn was
interrupted by `session/cancel`.

### `session/cancel`

A notification (no `id`, no response). Interrupts the in-flight prompt for
the session; the corresponding `session/prompt` result then reports
`"stopReason":"cancelled"`.

```json
{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"<uuid>"}}
```

## `session/update` notifications

While a prompt runs (and during `session/load` replay), the agent pushes
`session/update` notifications. Each has a `sessionId` and an `update`
object tagged by `sessionUpdate`:

```json
{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"<uuid>","update":{ … }}}
```

| `sessionUpdate` | Payload | Meaning |
|---|---|---|
| `agent_message_chunk` | `content:{type:"text",text}` | A chunk of the assistant's reply (also used for replay). |
| `agent_thought_chunk` | `content:{type:"text",text}` | A chunk of the model's reasoning/thinking. |
| `user_message_chunk` | `content:{type:"text",text}` | A prior user message, replayed on `session/load`. |
| `tool_call` | `toolCallId, title, kind, status` | A tool started. `kind` ∈ read/edit/search/fetch/execute/other. Sent before any update, even for tools that finish instantly. |
| `tool_call_update` | `toolCallId, status, kind, content` | Tool progress/completion. `status` ∈ in_progress/completed/failed; `content` is `[{type:"content",content:{type:"text",text}}]` carrying the output. |
| `plan` | `entries:[{content,priority,status}]` | The current task plan (from the Plan tool). `status` ∈ pending/in_progress/completed. |
| `available_commands_update` | `availableCommands:[{name,description}]` | The slash commands the client may offer (cmagent's user-invocable skills). Sent on session start. |
| `usage_update` | `size, used` | Context window size and tokens used. |
| `session_info_update` | `title` | A human-readable session title. |

## Permission requests

When the agent needs approval for a higher-risk action, it sends a
`requestPermission` **request** (it expects a response):

```json
{"jsonrpc":"2.0","id":"<req-id>","method":"requestPermission","params":{
  "sessionId":"<uuid>",
  "toolCall":{"toolCallId":"<id>","title":"shell: rm -rf ./build","status":"pending"},
  "options":[
    {"optionId":"allow_once","name":"Allow once","kind":"allow"},
    {"optionId":"remember","name":"Allow for session","kind":"allow"},
    {"optionId":"deny","name":"Deny","kind":"deny"}
  ]
}}
```

The client replies with the chosen outcome:

```json
{"jsonrpc":"2.0","id":"<req-id>","result":{"outcome":"selected","optionId":"allow_once"}}
```

or, to refuse:

```json
{"jsonrpc":"2.0","id":"<req-id>","result":{"outcome":"cancelled"}}
```

`optionId` is one of `allow_once`, `remember` (legacy alias
`allow_session`), or `deny`. Anything else, or a `cancelled` outcome, is
treated as a denial.

## Notes

- The process exits when stdin is closed.
- Each `session/new` creates an independent agent context; multiple
  sessions can be active within one process.
- The `cwd` (workspace) determines which config, skills, and MCP servers
  are active for that session.
### `session/set_mode`

Switches the session's permission posture. cmagent advertises two modes in
the `session/new` and `session/load` results:

```json
"modes": {
  "currentModeId": "default",
  "availableModes": [
    {"id":"default","name":"Ask","description":"Ask before running tool actions that need permission."},
    {"id":"auto","name":"Auto-approve","description":"Run tool actions without asking. The security policy still blocks denied actions."}
  ]
}
```

Request: `{"method":"session/set_mode","params":{"sessionId":"<id>","modeId":"auto"}}`.
Result is an empty object; the agent also emits a `session/update` with
`{"sessionUpdate":"current_mode_update","modeId":"auto"}`.

In `auto` mode, tool actions that would otherwise prompt are auto-approved
without a client round-trip. This only skips the interactive confirm —
hard-denied actions are blocked earlier in tool dispatch and never reach the
permission handler, so `auto` cannot run anything the security policy forbids.

## Notes (continued)

- Not implemented (optional; not required for editor interop):
  `session/resume` (the implemented `session/load` already restores a session
  WITH its history), `session/set_config_option`, `authenticate`, dynamic MCP
  registration, and the client-filesystem methods (`fs/read_text_file` /
  `fs/write_text_file`) — cmagent uses its own file tools. (`session/fork` is
  not part of the ACP spec.)
