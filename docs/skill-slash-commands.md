# Skill Slash Commands

Skills can be exposed as slash commands so users can invoke them directly
instead of relying on automatic keyword/tag activation.

## Opt-in with `user-invocable`

Add `user-invocable: true` to a SKILL.md frontmatter to register it as
`/<skill-name>`:

```yaml
---
name: git-helper
version: "1.0.0"
description: Git workflow assistant
user-invocable: true
activation:
  keywords: [git, commit, branch]
---

You are a Git expert...
```

Invoking `/git-helper` (or `/git_helper` -- hyphens and underscores are
equivalent) force-activates the skill for that turn and sends any trailing
text as the user message:

```
/git-helper how do I squash the last 3 commits?
```

This is equivalent to sending the message with the skill always active,
regardless of whether the keywords would have matched.

## Arguments

A skill can say where the trailing text goes, using the placeholders from
the [Agent Skills](https://agentskills.io) standard:

| Placeholder     | Expands to                                          |
|-----------------|-----------------------------------------------------|
| `$ARGUMENTS`    | everything typed after the command, verbatim         |
| `$ARGUMENTS[N]` | the Nth argument, **0-based** (`$ARGUMENTS[0]` is the first) |
| `$N`            | the same, shorter: `$0`, `$1`, ...                   |
| `$name`         | a name declared in `arguments`, mapped by position   |

Quoting is shell-style, so `"hello world" second` is two arguments. To
write a literal `$` before one of these, escape it with a single
backslash: `\$1.00`.

```yaml
---
name: migrate-component
description: Migrate a component between frameworks
user-invocable: true
argument-hint: "[component] [from] [to]"
arguments: [component, from, to]
---

Migrate the $component component from $from to $to.
Preserve all existing behaviour and tests.
```

`/migrate-component SearchBar React Vue` then reaches the model with the
names already filled in.

`argument-hint` is shown beside the command in the completion menu. It is
documentation for whoever is typing; nothing validates against it.

Where the arguments end up depends on the body:

- **The body has a placeholder** -- the arguments go there, and the user
  message for the turn is a short instruction to run the skill. Sending
  them twice would just say the same thing twice.
- **The body has no placeholder** -- nothing is substituted and the
  arguments arrive as the user message, which is the behaviour slash
  commands always had.

Only the skill you invoked is substituted. Another skill that scored its
way into the same turn keeps its own text: nobody typed anything at it.

## Optional: `paths` -- limit automatic activation

```yaml
---
name: rust-migration
description: Guidance for the 0.4 API migration
paths: crates/**/*.rs, src/**/*.rs
---
```

A skill with `paths` set offers itself automatically only in turns that
name a matching file. cmagent has no editor with a file open, so "the
files being worked on" means the paths mentioned in the message.

This only ever narrows: a skill with `paths` appears in fewer turns than
it would have, never more. Typing `/rust-migration` ignores the limit --
an explicit request is not a guess that needs narrowing.

Patterns are comma-separated (a path may contain spaces) or a YAML list.
A pattern that does not compile is skipped rather than silencing the
skill.

## Optional: `disallowed-tools` -- give up capability

```yaml
---
name: audit-only
description: Read the codebase and report; change nothing
disallowed-tools: shell, write_file, edit_file
---
```

While the skill is active its listed tools are removed from what the model
is offered, and refused if it names one anyway. Removing them from the
prompt alone would be a hint; the refusal is what makes it a wall.

This needs no approval, unlike `requests:` in the other direction: a skill
may always give up capability it would otherwise have had. The withholding
lasts for the turns the skill is active and applies to every skill active
in that turn, taken together.

## Optional: `context: fork` -- run the body as a sub-agent

```yaml
---
name: audit-deps
description: Review dependencies and report
user-invocable: true
context: fork
---

Read every dependency in the manifest and report anything unmaintained.
```

The body becomes an isolated sub-agent's prompt; its ANSWER is what
reaches the conversation. The sub-agent does not see the conversation and
has no memory -- it is this agent again with a clean context, narrowed
the way every sub-agent is.

**Only when you invoke it by name.** cmagent picks skills by keyword
match, not by a model reading a description, so a forked skill would
spawn a sub-agent every time one of its words appeared -- paid for in
tokens and latency over a word someone happened to type. Activated by
keyword instead, the body runs in this conversation and the turn says so.

**Blocking, always.** `background` is not implemented: cmagent has no
route for a sub-agent's answer to arrive later. The spec falls back to
blocking in five cases of its own, so this is its conservative branch.

If the fork fails, the reason appears where the body would have been --
the rest of the turn is still worth having.

## Optional: `license` and `compatibility` -- what the author declares

```yaml
---
name: pdf-forms
description: Fill and merge PDF forms
license: Apache-2.0
compatibility: Requires python3, poppler-utils, and network access
---
```

Both are Agent Skills **standard** fields, unlike everything else on this
page. They carry no behaviour; they are shown where someone decides to
install the skill (`cmagent skill install`) and in `cmagent skill info`.

`compatibility` is **not** parsed into a requirement. The standard makes
it free text, so reading structure out of it would be cmagent inventing a
contract the author never agreed to. Put a checkable requirement in
`requires:`, which gates activation; put the prose here for the person.

## Optional: `shell` -- which interpreter runs `` !`command` ``

```yaml
---
name: winbuild
description: Build and report the toolchain
shell: powershell
---

Toolchain: !`Get-Command cl | Select-Object -ExpandProperty Source`
```

Accepts `bash` or `powershell`. It applies only to the `` !`command` ``
lines in the skill body, not to anything the model runs through the
`shell` tool.

**An absent field is NOT `bash`.** The Agent Skills standard defaults to
bash; cmagent keeps its platform shell -- `cmd` on Windows, `sh`
elsewhere -- because that is what it has run since the feature existed,
and changing an unstated default would silently change what every
already-written skill executes. Say `shell: bash` to get bash.

A named shell that is not installed is reported in place of the command's
output rather than substituted. Running an author's line under an
interpreter they did not write it for produces something that looks like
an answer, which is the worse failure.

## Optional: `hooks` -- run a command at a defined moment

```yaml
---
name: strict-tests
description: Run the suite before claiming anything is done
hooks:
  - name: verify
    events: ["before_tool_call"]
    matcher: "^shell$"
    command: "./scripts/precheck.sh"
---
```

Uses the same `{name, events, command, matcher, timeout_ms}` shape as
`~/.cmagent/hooks/*.toml`, and the hooks are registered only while the
skill is active -- the set is replaced at every turn, so a skill that
stops matching stops firing.

**A hook is not the same authority as `requests.allowed_commands`.** That
one says "the model may use `python3` *when it calls the shell tool*"; a
hook runs by itself, at a moment the skill chose, with nobody deciding in
between. So they carry a separate grant:

| Skill | What happens |
|---|---|
| You wrote it (`trusted`) | Its hooks register |
| Installed, hooks approved and unchanged | They register |
| Installed, not approved or changed since | They do NOT register, and the turn says which and why |

The grant records the hook **definitions**, not a yes. A skill that
updates and changes what a hook runs asks again, rather than inheriting
consent for something nobody saw. Renaming one, or changing its timeout,
does not re-ask -- re-asking over cosmetics only trains people to click
through.

`cmagent skill grant <name>` shows each hook as its own line ("registers a
hook: runs `X` at `Y`"), because what has to be judged is the moment and
the command together.

## Optional: `command-dispatch` for direct tool calls

When `command-dispatch: tool` is set together with `command-tool: <name>`,
the slash command bypasses the LLM entirely and calls the named built-in
tool directly with the args as JSON input:

```yaml
---
name: audit-log
version: "1.0.0"
description: Query the channel audit log
user-invocable: true
command-dispatch: tool
command-tool: audit_query
activation:
  keywords: [audit, log]
---

...prompt body still required but only shown to the LLM on non-direct calls...
```

Then `/audit-log {"action":"stats"}` calls `audit_query` with
`{"action":"stats"}` and returns the result immediately -- no LLM token
is consumed.

The args string must be valid JSON. When args are omitted, `{}` is passed.

## Priority: built-ins always win

If a skill name collides with a built-in command (`/help`, `/clear`,
`/model`, etc.), the built-in takes precedence and the skill command is
silently dropped from registration.

## Name sanitization and deduplication

The slash command name is derived from the skill `name` field:
- Lowercased
- Non-alphanumeric characters replaced with `_`
- Truncated to 32 characters
- Trailing/leading underscores stripped

Two skills that sanitize to the same name get `_2`, `_3`, ... suffixes.
Both `/git-helper` and `/git_helper` resolve to the same command.

## Visibility

- `cmagent skill list` shows a `SLASH CMD` column with `/<name>` for
  user-invocable skills.
- `cmagent skill info <name>` shows `Slash cmd: /<name>` and the dispatch
  mode if set.
- `/help` inside a session lists all active skill commands under
  "Skill Commands".

## Default is opt-out

Skills without `user-invocable: true` are not registered as slash commands.
Automatic keyword/tag activation still works normally for all skills.
