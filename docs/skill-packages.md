# Skill Packages and Claude Code Plugin Compatibility

cmagent skills live under `~/.cmagent/skills/`. A directory there is
recognised in one of two layouts, automatically:

## Flat layout

The directory itself is a skill.

```
~/.cmagent/skills/
└── my-skill/
    ├── SKILL.md              # required
    ├── scripts/              # optional, callable via ${SKILL_ROOT}
    ├── refs/                 # optional, anything else the skill needs
    └── hooks.json            # optional, Claude Code-style hooks
```

## Nested layout (package containing multiple skills)

The directory is a package; each subdirectory under `skills/` is a skill.

```
~/.cmagent/skills/
└── superpowers/                  # package directory
    ├── package.json              # package metadata (read but not required)
    ├── hooks/hooks.json          # package-level hooks (optional)
    ├── scripts/                  # package-level scripts (optional)
    └── skills/
        ├── brainstorming/
        │   ├── SKILL.md
        │   ├── hooks.json        # skill-level hooks (optional)
        │   └── scripts/          # skill-level scripts (optional)
        └── systematic-debugging/
            └── SKILL.md
```

Each nested skill is registered with a qualified name `<package>/<leaf>`,
so `superpowers/brainstorming` does not collide with a flat skill named
`brainstorming`.

**No deeper nesting**: `<package>/skills/<x>/skills/...` is not recursed.

**Mixed layouts**: if a directory has both `SKILL.md` and `skills/`,
the flat skill wins and the nested `skills/` is logged as ignored.

## Path variables

These variables are substituted inside SKILL.md body and inside
hooks.json `command` strings at load time:

| Variable | Resolves to |
|---|---|
| `${SKILL_ROOT}` | The directory holding the skill's own `SKILL.md` |
| `${CLAUDE_PLUGIN_ROOT}` | The package directory (one level above `skills/<x>/` for nested skills; same as `${SKILL_ROOT}` for flat skills) |

So an inline command in a Claude Code skill body like:

```markdown
Run `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd session-start` to bootstrap.
```

resolves to a real path the LLM can hand to the shell tool.

## hooks.json bridge

cmagent reads `hooks.json` from two canonical locations per package:

- `<pkg>/hooks/hooks.json` — Claude Code's canonical location
- `<pkg>/hooks.json` — shorthand

Plus per-nested-skill `<pkg>/skills/<x>/hooks.json`.

### Event mapping

| Claude Code | cmagent |
|---|---|
| `SessionStart` | `on_session_start` |
| `Stop` | `on_session_end` |
| `PreToolUse` | `before_tool_call` |
| `PostToolUse` | `on_after_tool_call` |
| `UserPromptSubmit` | `on_message_received` |
| `Notification`, `PreCompact`, `SubagentStop` | _not yet supported, hook is silently skipped_ |

### Matcher

For `PreToolUse` / `PostToolUse`, the `matcher` field is a regex matched
against the tool name. Example:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "shell|file_write",
      "hooks": [{"type": "command", "command": "log-write.sh"}]
    }]
  }
}
```

The hook fires only when the tool name matches the regex. Invalid regex
falls back to firing unconditionally with a warning.

For `SessionStart`, Claude Code uses the matcher for subtype filtering
(`startup|clear|compact`); cmagent ignores this matcher and fires on
every session start because it does not yet distinguish those subtypes.

### Hook script environment

The runner exposes these environment variables to the hook command:

- `HOOK_EVENT` — the cmagent event name (e.g. `on_after_tool_call`)
- `HOOK_SESSION_ID` — current session id
- `HOOK_TOOL_NAME` — set for tool events
- `HOOK_DURATION_MS` / `HOOK_IS_ERROR` — set for `on_after_tool_call`
- `HOOK_CONTENT` — first 4 KB of input content for modifying hooks

## HARD-GATE convention

Claude Code's `superpowers` plugin uses `<HARD-GATE>...</HARD-GATE>`
blocks inside SKILL.md to mark non-negotiable constraints, e.g.:

```markdown
<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any
project, or take any implementation action until you have presented a
design and the user has approved it.
</HARD-GATE>
```

cmagent extracts every such block from active skills and renders them
in a `# CRITICAL CONSTRAINTS` section placed at the top of the system
prompt (right after the agent identity, before tools and security).
The original tags stay inline in the skill body so the surrounding
context remains readable; the top-of-prompt copy is the unmissable
second pass.

There is no runtime enforcement — gates rely on the model obeying the
prompt. This mirrors Claude Code's behavior, which also treats
`<HARD-GATE>` as prompt convention rather than a security boundary.

## Dependencies

Skills shipped as Claude Code plugins commonly require a runtime
(`bash`, `node`, `python`) or runtime packages (Node modules, Python
packages). cmagent surfaces these in two places.

### Declared in SKILL.md

```yaml
requires:
  bins: [bash, node, jq]      # checked against PATH
  npm:
    - ./tests/brainstorm-server   # runs `npm install` in each dir
  pip:
    - ./requirements.txt          # runs `pip install -r <path>`
  setup:
    - ./scripts/setup.sh          # custom scripts, run with bash, in order
```

`bins` blocks the skill from loading when a required binary is
missing (existing behavior). The other three drive `cmagent skill
setup`.

### Auto-detected

For skills without a declared `requires` block — typical for plugins
copied from Claude Code — the planner scans the package directory:

| File present | Step planned |
|---|---|
| `package.json` at package root | `npm install` |
| `requirements.txt` at package root | `pip install -r requirements.txt` |
| `setup.sh` or `install.sh` at package root | `bash <script>` |

If the manifest declares a given step type (even with an empty list),
detection for that type is disabled. So `requires.npm: []` means "do
not run any npm install for this skill".

### `cmagent skill setup`

```sh
cmagent skill setup superpowers          # run pending steps for one skill
cmagent skill setup --all                # all skills with pending deps
cmagent skill setup superpowers --dry-run  # show what would run
cmagent skill setup superpowers --yes      # skip confirmation
```

Each run:
1. Plans steps (declared + detected).
2. Compares against `~/.cmagent/skills/<name>/.cmagent-installed`.
   Steps whose target file hasn't changed since the last successful
   run are skipped silently.
3. Prints the remaining commands and asks `Proceed? [y/N]`.
4. Runs each step; on first failure within a skill, stops further
   steps for that skill and moves on.
5. Reports any required binaries still missing from PATH, with
   platform-specific install hints.

### `cmagent doctor`

```
Skill dependencies
  \u26A0 superpowers: npm pending, bin missing: jq
  \u2139 Run `cmagent skill setup --all` to install (1 skill(s) need it)
```

Doctor walks every directory under `~/.cmagent/skills/`, runs the
same planner, and surfaces:
- Pending install steps (anything not satisfied by the sentinel).
- Missing required binaries (`requires.bins`).

It does not run installs itself — that requires confirmation. The
output is a checklist the user can act on with one command.

## Activation

cmagent uses **deterministic** skill selection: a skill is auto-activated
only when its `activation` keywords / tags / regex patterns match the
user message. Manually-invoked skills (`/<name>`) require
`user-invocable: true` in the frontmatter.

Skill packages copied from Claude Code typically have no `activation`
block. They will load and remain available but will not auto-trigger;
either add `activation` keywords / tags to the SKILL.md frontmatter, or
set `user-invocable: true` and call them with `/<package>/<leaf>`.

See [skill-slash-commands.md](skill-slash-commands.md) for the
user-invocable contract.

## Installing a Claude Code plugin

A Claude Code plugin like `superpowers` drops in with one command:

```sh
# Find the plugin source (downloaded by Claude Code into a cache):
ls ~/.claude/plugins/cache/claude-plugins-official/superpowers/

# Copy the version directory into cmagent's skills folder:
cp -r ~/.claude/plugins/cache/claude-plugins-official/superpowers/5.1.0 \
      ~/.cmagent/skills/superpowers
```

cmagent will:

- Register 14 skills as `superpowers/brainstorming`,
  `superpowers/systematic-debugging`, etc.
- Load the `SessionStart` hook from `superpowers/hooks/hooks.json`.
- Substitute `${CLAUDE_PLUGIN_ROOT}` to `~/.cmagent/skills/superpowers/`.
- Surface every `<HARD-GATE>` block at the top of the prompt when the
  containing skill is active.

To activate a skill: either edit its frontmatter to add `activation`
keywords / `user-invocable: true`, or invoke explicitly with
`/<package>/<leaf>` in the TUI.
