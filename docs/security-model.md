# cmagent Security Model

Consolidated reference for the current `[security]` schema and runtime
gating. Reflects the 2026-04-22 Tier 3 refactor (commits `d3319df` ->
`16a72b2` -> `87aa5e0`). Supersedes older design docs that describe
`autonomy` / `max_tool_risk` / `allowed_paths` etc. in their pre-refactor
form.

## Three Gates

Every tool call the LLM emits traverses three gates, in order:

```
LLM emits a tool call
  |
  v
[Gate 1: Tool allowlist]  `tools = [...]` on the agent
  |   Not on the list -> model receives an error. Hard wall. No user prompt.
  v
[Gate 2: HardDeny]        shell-parser / policy checks
  |   bash -c "...", redirect to forbidden path, tilde/traversal, ...
  |   Even `prompt_threshold = "never"` cannot override. Model sees the error.
  v
[Gate 3: prompt_threshold + policy]   soft gate
  |   May surface a user-facing permission prompt.
  v
Execute
```

These three gates are independent and additive. The model cannot
"talk its way past" any of them.

## `[security]` Field Table

Nine fields, each owning one axis.

| Field | Type | Semantics | Default |
|---|---|---|---|
| `prompt_threshold` | `"medium"` \| `"high"` \| `"never"` | At which tool risk level do we ask the user before running? low-risk tools are always silent. | app: `medium` |
| `max_skill_risk` | `"low"` \| `"medium"` \| `"high"` | Risk ceiling for **skills** and **MCP** servers. Filters them in the wizard picker; skill attenuation at runtime caps what loaded skills can elevate. Does NOT gate built-in tool calls. | app: `high` |
| `forbidden_paths` | `Vec<String>` | Blacklist. Union-merged across presets + agent + app. | `[]` |
| `allowed_commands` | `Option<Vec<String>>` | Shell command whitelist. `Some([])` means "shell effectively disabled." Replace-merged. | inherit |
| `workspace_only` | `Option<bool>` | Restrict file ops to the workspace directory. | inherit |
| `sandbox_network` | `Option<bool>` | Block network egress inside the OS sandbox. | inherit |
| `extra_dirs` | `Vec<{path, mode}>` | Additional directory access. `mode` is any combination of `r` / `w` / `x`. Each entry **also** whitelists the path against `forbidden_paths`. | `[]` |
| `brain_readonly` | `Option<bool>` | When true, `brain` tool's `remember` / `forget` sub-actions are rejected even though `brain` itself is on the allowlist. Lets a persona carry a read-only reference memory. | `false` |
| `relaxed_shell` | `Option<bool>` | Downgrade shell-parser `NeedsConfirm` (typically "program not in allow-list") to `Allow`. HardDeny is still enforced. Intended for trusted operator contexts (the shipped `admin` agent). | `false` |

## Three Risk Axes (Not One)

A common source of confusion: "risk" appears on three different artifacts,
and the overrides target different axes.

| Source of risk | Where it lives | Who consumes it |
|---|---|---|
| **Tool** | `Tool::risk_level()` in code (fixed at compile time) | `prompt_threshold` uses it to decide whether to prompt. Does NOT decide whether the tool can be called -- that's the agent's `tools = [...]` allowlist. |
| **Skill** | `SKILL.md` YAML frontmatter: `risk_level: low/medium/high` | `max_skill_risk` filters the wizard picker; runtime `skill_attenuation` caps the effective risk ceiling a skill can bring to the turn. |
| **MCP server** | `mcp-catalog.json` entry `risk_level` (copied on install into `mcp/<id>/config.toml`) | `max_skill_risk` filters the wizard picker. Runtime execution is gated by the standard tool allowlist. |

"Tool risk" is only ever an input to `prompt_threshold`. It is not a
runtime execution gate. A tool on the agent's explicit allowlist
always runs after passing Gate 2 and Gate 3.

**Secondary prompt-visibility effect of `max_skill_risk`:** the
system prompt built for the LLM only includes tool specs whose risk
<= the effective ceiling (`min(agent.max_skill_risk,
skill_attenuation)`). This is a UX optimization (the model stays
focused on tools it can productively use) rather than a security
boundary -- Gate 1 is the actual enforcement. A model that
hallucinates a tool name outside the allowlist is rejected by Gate 1
regardless of what the prompt showed.

## Built-in Tool Risk Levels

These are fixed in code (`crates/cmagent-tool/src/builtin/`).

| Risk | Tools |
|---|---|
| Low | `file_read`, `list_dir`, `glob_search`, `content_search`, `history_search`, `brain`, `todo`, `update_plan`, `learn_rule`, `ask_user`, `diff_preview`, `tool_search`, `help`, `audit_query`, `messaging_query` — plus `browser_query`, `vision`, `screenshot`, `tts` when present |
| Medium | `file_write`, `file_edit`, `apply_patch`, `trash`, `http_request`, `web_fetch`, `web_search`, `lsp_query`, `messaging_send`, `sessions_send`, `browser_act`, MCP tool adapters |
| High | `shell`, `spawn_agent`, `plan_tasks`, `skill_manager`, `browser_eval` |

Low-risk tools are always silent regardless of `prompt_threshold`.

## `prompt_threshold` Semantics

Runtime rule (in `crates/cmagent-core/src/agent/mod.rs::check_security`):

```rust
let never_prompts = self.prompt_threshold == "never";
// ...HardDeny + NeedsConfirm checks run first, unaffected by threshold:
//    - shell parser (dangerous-command detection)
//    - file path policy (validate_path: traversal / tilde / forbidden /
//      out-of-workspace) for every file tool
// `never` suppresses PROMPTS, not these hard-policy walls.
if never_prompts { return Allow; }

let needs_risk_permission = match self.prompt_threshold.as_str() {
    "medium" => tool_risk >= RiskLevel::Medium,
    "high"   => tool_risk >= RiskLevel::High,
    _        => false,   // unknown values behave like "never"
};
```

- `medium` -> ask before medium + high risk tools
- `high` -> ask only before high-risk tools
- `never` -> never ask. HardDeny still fires: shell-parser
  `Deny`/`NeedsConfirm` AND file path policy (`validate_path`). `never`
  means "no prompt", not "no policy" -- an unattended profile cannot
  write/read outside the allowed paths even though it never prompts.

Low-risk is always silent. Threshold is meaningless for low-risk tools.

## Permission Prompt UX

When a tool call needs confirmation, the TUI shows a 3-option
panel:

```
[y] Approve once
[a] Approve and remember (workspace)
[n] Deny
```

(Plus `[Ctrl+C]` to deny and cancel the whole turn.)

`[a]` writes to the workspace allowlist at
`<workspace>/.cmagent/workspace.toml`:

```toml
[permissions]
tools = ["file_read", "file_write"]
shell_programs = ["cargo", "git", "python"]
shell_commands = ["docker-compose down"]
```

The granule recorded by `[a]` is decided automatically per tool:

- **shell tool** -> extracts every program name from the command
  line (pipeline stages, `&&` branches, `find -exec`, `xargs`) and
  appends them to `shell_programs`. A single approval covers an
  entire pipeline; future `cargo test` and `cargo build` both
  auto-approve.
- **non-shell tool** -> the tool name goes into `tools`. Future
  calls to that tool skip the prompt.

`shell_commands` is honoured at load time but **not written by the
UI** -- it's reserved for power users who want exact-match
approval and hand-edit the file. The UI deliberately never offers
"approve the entire `shell` tool" because that would silently
authorize every future command in this workspace.

At Agent construction, all three lists are loaded into the
in-memory `session_allowed_*` HashSets so a prior `[a]` approval
takes effect immediately on the next session -- no restart
required.

### `/permissions` slash command

In the TUI:

```
/permissions                          List the current allowlist
/permissions remove tool <name>       Drop a tool from `tools`
/permissions remove shell_program <name>
                                      Drop a program from `shell_programs`
```

Removing an entry also clears it from the in-memory session set so
the change is live without restart. `shell_commands` is read-only
from this command; hand-edit `workspace.toml` to remove pinned
exact commands.

## Messaging Tools: `messaging_query` + `messaging_send`

All cross-channel messaging goes through two unified tools instead of
per-channel `<kind>_send_message`/`<kind>_search_contacts`/etc:

- `messaging_query` (Low risk) -- action-dispatched read surface:
  `list_channels`, `describe_channel`, `search_contacts`, `list_chats`,
  `list_messages`, `download_attachment`.
- `messaging_send` (Medium risk) -- action-dispatched write surface:
  `send_message`, `send_file`, `edit_message`, `delete_message`,
  `send_buttons`, `notify`, plus platform-specific actions
  (`send_embed`, `open_modal`, `create_thread`, `add_friend`,
  `accept_friend`, `send_pat`). The adapter's `describe_channel`
  response tells the LLM which actions are supported.

**Channel scope.** When an agent runs inside a channel session (the
session id starts with `lunkr-`, `telegram-`, etc.), `messaging_query`
and most `messaging_send` actions are restricted to that channel.
`notify` is the sole cross-scope exception because it targets a
preconfigured operator recipient, not arbitrary users. TUI / chat /
ACP / web sessions have no scope and can address any configured
channel. See `crates/cmagent-tool/src/builtin/messaging.rs` for the
scope-check logic.

**Opt-in.** Per-account `allow_outbound_send = true` is the gate for
all send actions; without it, `messaging_send` returns a structured
`not_configured` error for that channel. `messaging_query` read
actions are ungated.

**Interactive buttons.** `send_buttons` accepts an optional
`wait_response: true` + `timeout_seconds` pair. Channels whose
adapter has a response channel (Lunkr's p2p bridge today) block
until the user clicks and return the clicked value in
`response`. Other channels advertise `wait_response: false` in
`describe_channel` and return `platform_rejected` if the agent
asks for it.

## `extra_dirs` Replaces Four Old Fields

Before Tier 3, path configuration was spread across four lists
(`allowed_paths`, `workspace.extra_dirs`, `sandbox_extra_read_paths`,
`sandbox_extra_write_paths`), each with its own semantics. Now it's one:

```toml
[security]
extra_dirs = [
  { path = "/tmp",           mode = "rw" },   # read + write
  { path = "/etc/ssl",       mode = "r"  },   # read only
  { path = "/var/log/agent", mode = "rw" },
]
```

`mode` is case-sensitive and can be any combination of `r` / `w` / `x`
in any order: `"r"`, `"rw"`, `"rx"`, `"rwx"`, `"x"`. Invalid modes
(empty string, unknown letters) default to "no access."

An entry implicitly whitelists the path against `forbidden_paths` --
putting a normally-forbidden path here is how you say "this agent is
trusted to touch it." The `SecurityPolicy` constructor derives its
`allowed_paths` list from the `path_permissions` it receives, so callers
don't duplicate the list.

## Shipped Profiles (Reference)

| Profile | prompt_threshold | max_skill_risk | brain_readonly | relaxed_shell | Intent |
|---|---|---|---|---|---|
| `chat` | `medium` | `low` | `true` | -- | Research persona: if you later add a shell tool, still get prompted. Brain is a read-only reference. |
| `coding` | `high` | `high` | -- | -- | Developer assistant: don't nag on every edit, still prompt before shell. |
| `admin` | `never` | `high` | -- | `true` | Full operator trust. |
| `sys-auditor` | `medium` | `high` | `true` | -- | Cron summary agent. Protects against accidental tool-list drift. |
| `sys-ralph-worker` | `never` | `high` | -- | -- | Unattended long-task worker; no UI to prompt. |
| preset `default` | `medium` | `high` | -- | -- | Safe default for new user agents. |
| preset `channel` | `medium` | `medium` | -- | -- | IM-bot baseline. |
| preset `chat` | `medium` | `low` | `true` | -- | `chat` agent baseline. |
| preset `coding` | `high` | `high` | -- | -- | `coding` agent baseline. |
| preset `sys-default` | `never` | `high` | -- | -- | sub-/sys-agent baseline (no human in loop). |

Values in the shipped configs reflect **intent**, not "what the current
tool list happens to need." If a user later edits a `chat` agent and
adds `shell` to its tools list, `prompt_threshold = medium` still
protects them -- the threshold is not derived from the tool list.

## Untrusted Tool Output (Indirect Prompt Injection)

Output from tools that return attacker-controllable external content --
`web_fetch`, `web_search`, MCP servers -- is treated as untrusted before it
reaches the model. Two layers, both in addition to the gates above:

1. **Architectural delimiter** (`crates/cmagent-tool/src/untrusted.rs`).
   The content is wrapped in an `<untrusted_tool_result>` block instructing
   the model to treat it as DATA, not instructions, on the LLM-bound message
   only (the activity tree still shows raw content). Anti-spoof: each wrap
   carries a fresh random `id` on both markers, and any forged delimiter in
   the content is neutralized, so a poisoned page cannot "close" the block
   early and smuggle in trusted-looking text. This is the primary defense --
   it changes interpretation rather than relying on catching every payload.
2. **Detect-only scan**
   (`cmagent_security::input_guard::scan_injection_signals`). Runs on the
   same untrusted results and flags high-confidence, near-zero-false-positive
   signals only: forged tool-call tags (`<tool_call>` etc.), LLM
   chat-template control tokens, and hidden/bidirectional Unicode. It
   **never blocks or alters** the result -- findings are recorded on the
   message (`ChatMessage.security_flags`, persistence-only, never sent to the
   provider), shown as an end-of-turn warning in both TUIs, and counted as a
   `[!N]` marker in the session browser. Noisy natural-language heuristics
   are deliberately excluded.

A related threat -- a compromised LLM gateway/router injecting a tool call
the model never emitted -- has no bespoke defense (we cannot distinguish it
from a genuine call without trusting the response). It folds into the same
surface as any unwanted tool call: the tool allowlist, the permission prompt,
and the non-overridable hard-policy walls (Invariants 2 and 3), which apply
even to unattended `never` profiles and on platforms without an OS sandbox.
In particular, an injected tool call cannot rewrite the agent's own profile
to escalate, poison a skill, or read the provider keys -- the control plane
is off-limits to tools regardless of how trusted the profile is.

## Invariants

1. **Tool allowlist is a hard wall.** `tools = ["file_read", ...]` means
   the agent can call only those tools, period. No preset, threshold,
   or session override can introduce tools that were not listed.
2. **HardDeny is non-overridable.** Hard-policy walls block at every
   `prompt_threshold` (including `never`): the shell parser (interpreter
   as program, redirect to forbidden path, dangerous patterns) and the
   file path policy (`validate_path`: traversal, null-byte, tilde,
   forbidden, out-of-workspace) for every file tool. `never` suppresses
   prompts, never these.
3. **The control plane is absolutely off-limits to tools.** The agent's
   generic file tools and shell redirects can never read or write under
   cmagent's own config dir (`control_plane_root`, usually `~/.cmagent`):
   agent profiles, skills, `providers/*.toml` (API keys), `config.toml`,
   data DBs. Unlike ordinary `forbidden_paths`, this is **not** exemptable
   by `extra_dirs` / `allowed_paths`, an admin/relaxed profile, or
   `never` -- it is checked before the allow-list. Self-escalation
   (rewriting one's own profile to widen `tools` / drop the threshold),
   persistent injection (poisoning a `SKILL.md`), and key theft are thus
   closed even for a fully-trusted agent or an injected tool call under
   it. Skill/agent management still works through their dedicated paths
   (`skill_manager`, `cmagent config`), which don't go through
   `validate_path`. The one sanctioned self-write exception is
   `learn_rule`: it appends a user-confirmed rule to exactly one file
   (`agents/<name>/LEARNED.md`) via its own write -- never `RULES.md`,
   `config.toml`, or any security field.
4. **Low-risk tools never prompt.** This is structural, not
   configurable.
5. **`max_skill_risk` caps skills/MCPs, not tools.** Tools are
   configured by explicit allowlist.
6. **`extra_dirs` is the only knob for extra path access.** No other
   field adds paths -- and it cannot reach the control plane (Invariant 3).

## Related Docs

- [sandboxing.md](sandboxing.md) -- OS sandbox backends (Layer 2): Landlock /
  bwrap / firejail / containers, how to install each, permission setup, and
  trade-offs.

## Related Files

- Runtime gate: `crates/cmagent-core/src/agent/mod.rs::check_security`
- Runtime thresholds: same file, `prompt_threshold` match
- Skill ceiling: `crates/cmagent-core/src/skill_attenuation.rs`
- Security policy: `crates/cmagent-security/src/policy.rs`
- Shell parser: `crates/cmagent-security/src/shell_parser/decide.rs`
- Wizard prompts: `src/commands/config/profile_edit.rs`
- Schema: `crates/cmagent-config/src/agent.rs` (`AgentSecurityOverride`,
  `ExtraDirConfig`) and `crates/cmagent-config/src/schema.rs`
  (`SecurityConfig`)
