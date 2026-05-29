# Ralph Loop

The Ralph Loop runs a long task as a series of short, independent agent
iterations. Each iteration reads the current workspace state, takes one
small step, updates a status file, and exits. The loop continues until the
agent signals completion or a maximum iteration count is reached.

Use Ralph for tasks that are too large for a single conversation: large
refactors, language ports, multi-step migrations, bulk file generation.

## Quick start

```sh
# 1. Create a task and open the prompt file
cmagent ralph new "Refactor authentication module"
# Prints: created task abc123
# Edit ~/.cmagent/ralph/abc123/prompt.md

# 2. Run the loop (foreground)
cmagent ralph run abc123

# 3. Monitor progress
cmagent ralph status abc123
cmagent ralph tail abc123

# 4. Stop early
cmagent ralph stop abc123
```

## Writing prompt.md

The prompt is read verbatim at the start of every iteration. Write it as a
complete, self-contained instruction:

```markdown
## Goal
Port all HTTP client calls in src/http/ from the `reqwest` library to `ureq`.

## Rules
- Change one file per iteration.
- Update STATUS.md after each file with the file path and a one-line summary.
- Write `done` to STATUS.md when all files are ported.

## Context
- Target directory: src/http/
- Do not change public function signatures.
```

The agent writes `STATUS.md` in the task directory after each iteration.
When it writes a line starting with `done`, the loop terminates.

## Commands

```sh
cmagent ralph new "<title>"         # create a task, print task ID
cmagent ralph run <id> [--detach]   # run the loop (--detach: background)
cmagent ralph resume <id>           # resume a stopped loop
cmagent ralph stop <id>             # signal the loop to stop after current iter
cmagent ralph status <id>           # show iteration count and last status line
cmagent ralph tail <id>             # stream the current iteration log
cmagent ralph list                  # list all tasks
cmagent ralph edit <id>             # open prompt.md in $EDITOR
cmagent ralph rm <id>               # delete a task and its files
```

## Task files

Each task lives under `~/.cmagent/ralph/<task-id>/`:

| File | Description |
|---|---|
| `prompt.md` | Goal and rules, read every iteration |
| `STATUS.md` | Agent-written progress notes |
| `task.toml` | Task metadata (title, max_iter, created_at) |
| `iter-NNNN.log` | Full output of each iteration |
| `iter-NNNN.meta` | Iteration timing and stop reason |
| `done` | Sentinel file written when complete |
| `stop` | Sentinel file written by `ralph stop` |

## Configuration

Task configuration in `task.toml`:

```toml
title = "Refactor authentication module"
max_iter = 50          # default: 50
agent = "sys-ralph-worker"
```

The default agent (`sys-ralph-worker`) has access to file, shell, and search
tools and is configured to never prompt for permission. To use a different
agent, edit `task.toml` before running.

## Design notes

- Each iteration is a fresh `Agent` instance with no memory of the previous
  iteration. The agent's only link between iterations is the filesystem
  (code it wrote, STATUS.md it updated).
- Ralph is human-triggered only. The agent has no tool to start a Ralph task.
