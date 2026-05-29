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
