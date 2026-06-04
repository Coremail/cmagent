# Interactive commands

In the TUI and the chat REPL, a line that starts with `/` is a **command**
handled locally — it is not sent to the model. Skills can add their own
commands too; those are covered separately in
[skill-slash-commands.md](skill-slash-commands.md). This page documents
the built-in ones.

## Built-in commands

| Command | What it does |
|---|---|
| `/help` | List available commands. |
| `/clear` | Clear the conversation context (history is archived, not lost). |
| `/compact` | Compact the context now instead of waiting for the automatic threshold. |
| `/new` | Start a fresh session. |
| `/session [list\|<id>]` | List sessions, or switch to one by id. |
| `/rename <name>` | Rename the current session. |
| `/undo` / `/redo` | Step the conversation back / forward one turn. |
| `/retry` | Re-send your last message for a fresh response. |
| `/status` (`/stats`) | Show session status (model, token usage, counts). |
| `/config` | Open the configuration wizard. |
| `/model [id]` | Show or switch the active model. |
| `/provider [id]` | Show or switch the active provider. |
| `/agent [name]` | Switch the active agent profile. |
| `/permissions [...]` | View or adjust this session's permission settings. |
| `/verbose [on\|off]` | Toggle the live tool-activity display (no arg = toggle). |
| `/reload-skills` | Reload skills from disk without restarting. |
| `/plan [...]` | The session plan roadmap — see [Plans](#plans-plan). |
| `/todo` (`/todos`) `[list\|clear]` | The session todo checklist — see [Todos](#todos-todo). |
| `/goal [text]` | Set or show the session goal. |
| `/memory` (`/brain`) `[...]` | Open the memory browser / run brain operations. See [memory.md](memory.md). |
| `/btw <text>` | Ask an ephemeral, read-only side question that doesn't alter the main thread. |
| `/init` | Generate or consolidate the project's `AGENTS.md` — see [Project instructions](#project-instructions-init). |
| `/debug [text]` | Open the request inspector (system prompt, context, tools, key-masked HTTP request, compaction preview). See [Full-screen viewers](#full-screen-viewers). Refused in channel sessions. |
| `/quit` (`/exit`, `/q`) | Exit. |

Unknown `/names` fall through to skill command matching.

## Project instructions: `/init`

cmagent reads a project-root `AGENTS.md` (if present) into the agent's
context at session start — the cross-tool standard for "instructions for
AI agents working in this repo". Only that one file is read: no walk-up,
no nested files, and no fallback to `CLAUDE.md` / `GEMINI.md` / Cursor /
Copilot (toggle with `[general] load_project_agents`).

`/init` is how you create or refresh that file. It gathers what's already
known about the project and asks the model to consolidate it into one
coherent `AGENTS.md`:

- any existing `AGENTS.md` (improved in place, not blindly overwritten);
- instruction files other tools left behind — `CLAUDE.md`, `GEMINI.md`,
  `.cursorrules` / `.cursor/rules/*.mdc`,
  `.github/copilot-instructions.md`, `.clinerules`;
- **the conversation so far** — what you've told the agent and what it's
  already done (a primary source when the repo is still sparse);
- key manifests, the README, and a bounded, gitignore-aware file tree.

It **merges** these (dedupes, resolves conflicts) rather than
concatenating, and is deliberately anti-filler: sections with no real
information are omitted, there's no length target. If there's nothing to
go on — an empty directory with no instruction files and no conversation
— it generates **nothing** and tells you so.

`/init` writes **only** `AGENTS.md` (never the source files), asks you to
confirm first, and backs up any existing `AGENTS.md` before replacing it.
The new file is loaded into the running session immediately. Other tools'
files are read as input but never modified.

## Mentioning files with `@`

Type `@` in the input to open a **file browser** rooted at the
workspace. It lists the current directory's entries — directories first
(shown with a trailing `/`), then files (with their size) — sorted by
name.

| Key | Action |
|---|---|
| `↑` / `↓` | Move the selection |
| `Enter` / `Tab` | Open the highlighted directory, or pick the highlighted file |
| `←` / `Backspace` (or the `../` row) | Go up one directory |
| `Esc` | Close the browser and keep typing the path by hand |

Picking a file inserts `@<relative/path>` at the cursor — the same as if
you had typed it. You can mention several files in one message.

**On send, every `@<path>` that resolves to a real file in the workspace
is expanded**: the file's contents are appended to your message inside a
`<system-reminder>` block so the model sees them without a separate read:

```text
review @src/main.rs and @README.md

<system-reminder>
<file path="src/main.rs">
...contents...
</file>
<file path="README.md">
...contents...
</file>
</system-reminder>
```

Details and limits:

- Only relative, in-workspace paths are expanded. An `@word` that isn't a
  real file (e.g. `@alice`) is left as plain text, so normal prose is
  never altered.
- Up to **10 files** per message; each is read up to **128 KiB**
  (truncated past that, marked `truncated="true"`).
- A mentioned **directory** or **binary/image** file is noted but not
  inlined (e.g. `<file path="logo.png" note="binary/image (not inlined)"/>`).
- Expansion is idempotent, so `/retry` doesn't double-append.

## Copying output to the clipboard

To grab a reply as markdown without a manual text selection:

- **In the chat:** press **`Ctrl+Y`** to copy the **last assistant reply**
  (raw markdown), or click the small **`⧉`** button at the top-right of
  the transcript. A status line confirms ("copied N chars").
- **In the Activity viewer (`Ctrl+O`):** press **`Ctrl+Y`** (or click the
  `⧉` in the detail pane) to copy the **currently-selected entry** —
  a response, a thinking block, or a tool call's args/diff/output.
- **In the other full-screen viewers** (Memory, Workspace, Debug — see
  [Full-screen viewers](#full-screen-viewers)): drag to select text in the
  detail pane, then **`Ctrl+Y`** copies the selection, or click its `⧉`
  box to copy the selection-or-everything.

The copy uses the OS clipboard with an OSC 52 fallback, so it also works
over SSH / tmux. (Drag-to-select in the transcript still copies an
arbitrary span, as before.)

## Full-screen viewers

Beyond the chat, cmagent has four full-screen TUI viewers. They share one
detail pane with the same selection/copy/scroll controls (listed once
below), so once you know one you know all four.

| Viewer | Open with | Shows |
|---|---|---|
| **Activity** | `Ctrl+O` | The live tool-activity log for the session — each response, thinking block, and tool call (args / diff / output). |
| **Memory** | `/memory` | The brain: layers, categories, and entries, with full content + detail. See [memory.md](memory.md). |
| **Workspace** | `/session` → "⚙ Manage sessions…" | Workspaces, their sessions (incl. archived), conversation turns, and the full content of any turn. Delete / rename / filter sessions and turns from here. |
| **Debug** | `/debug` | A snapshot of the system prompt, context, tool schemas, the (key-masked) HTTP request, and a compaction preview — for inspecting what the model actually sees. Refused in channel sessions (see note below). |

**Shared controls** (in every viewer):

| Key / action | Effect |
|---|---|
| `Tab` / `Shift+Tab` | Switch the active panel |
| `↑` `↓` | Navigate the active list, or scroll the detail pane when it's focused |
| `PgUp` / `PgDn` / `Home` / `End` | Scroll the detail pane |
| drag (mouse) | Select text in the detail pane |
| `Ctrl+Y` | Copy the detail selection to the clipboard |
| click `⧉` (top-right of the detail) | Copy the selection, or everything if nothing is selected |
| `q` / `Esc` | Close the viewer |

Each viewer adds its own keys on top (e.g. Memory's `e` to edit, `d` to
delete; Workspace's `r` to rename, `/` to filter) — its footer shows the
panel-specific hints.

**`/debug` and channel sessions.** The Debug inspector shows the system
prompt and live context, so it is restricted to **operator surfaces**
(TUI, chat, ACP, web). In a **channel session** (Telegram, Slack, Discord,
WeChat, Lunkr) the agent refuses `/debug` — a remote channel user can't
dump the operator's prompt or conversation. The API key in the snapshot is
masked (`sk-…1234`) in all cases, so it is never exposed even locally.

## Steering a running turn: `/steer` and `/queue`

These two are special: they apply **only while the agent is busy** (a
turn is running). They let you react to what the agent is doing without
waiting for it to finish:

- **`/steer <text>`** — inject `text` into the **current** run. The agent
  picks it up at the next tool-call boundary (it drains pending steer
  messages between steps), so use it to correct or redirect mid-turn:
  "stop, the file is under `src/` not `lib/`".
- **`/queue <text>`** — hold `text` and submit it as a **new turn** the
  moment the current run finishes. Several queued lines are merged into
  one follow-up. Use it to line up the next instruction while the agent
  works.

Each is echoed back so you can see it registered (`↪ steer: …` /
`⏳ queued: …`).

When you type while the agent is busy **without** a `/steer` or `/queue`
prefix, the input is routed according to the default busy-input mode,
`general.busy_input_mode` in `config.toml` (default `steer`). Set it to
`queue` to make plain input queue instead of steer; the explicit
`/steer` / `/queue` prefixes always override the default per message.

## Plans: `/plan`

`/plan` manages the session's plan roadmap. The agent normally builds and
updates the plan itself through the `update_plan` tool; these subcommands
let you inspect and steer it:

| Form | Effect |
|---|---|
| `/plan` (or `/plan show` / `/plan list`) | Show the active plan. |
| `/plan <text>` | **Append** step(s) to the plan from free text. Each line — or `;`-separated segment — becomes a `Pending` step; leading `1.` / `-` / `*` markers are stripped. Existing steps and their statuses are kept (unlike `update_plan`'s `set`, which replaces). Creates a plan if none is active. |
| `/plan clear` | Clear the active plan. |
| `/plan run [N]` | Run the plan-driver loop for up to `N` iterations (`1`–`50`, default `10`): the agent works the plan step by step until it's done or the cap is hit. |

## Todos: `/todo`

`/todo` (alias `/todos`) shows the session's todo checklist, which the
agent maintains via the `todo` tool:

| Form | Effect |
|---|---|
| `/todo` (or `/todo list`) | Show the checklist: each item's done mark, the turn that created it, its text, and an `X/Y completed` summary. |
| `/todo clear` | Remove all todos (the Activity panel hides immediately). |

The checklist is a lightweight, in-session scratchpad; for durable plans
across runs use `/plan`, and for facts that should survive sessions use
`/memory`.
