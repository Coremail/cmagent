# Code intelligence (LSP)

The `lsp_query` tool drives real language servers (rust-analyzer,
pyright, gopls, clangd, …) so the agent can navigate and refactor code
semantically instead of by text matching. Servers are spawned on demand,
keyed by file extension, and kept alive for the session.

## Actions

`lsp_query { action, file_path, ... }`:

| Action | Purpose |
|---|---|
| `definition` | Jump to where a symbol is defined (`line` / `character`, 1-based). |
| `references` | Find every reference to the symbol at a position. |
| `hover` | Type signature and docs at a position. |
| `symbols` | A token-lean **outline** of the file: every symbol with its line span (`L42-50`). Read this to grasp a large file's shape cheaply, then re-read only the ranges you need with `file_read`. |
| `rename` | Rename a symbol **across the whole project** and apply the edits (pass `apply: false` to preview). |
| `rename_file` | Move/rename a file **and update every import / `mod` / re-export** that points at it (`willRenameFiles`), then move it. |

`rename` / `rename_file` write files, so `lsp_query` is a `Medium`-risk
tool; every file an edit touches still passes the path-write security
check.

## Installing language servers

cmagent ships configuration for ~34 language servers but installs none —
you install the ones for languages you use.

```sh
cmagent lsp list          # all supported servers, install status, install command
cmagent doctor            # probes on-PATH servers and reports if they actually start
```

`cmagent doctor`'s **Language servers (LSP)** section starts each on-PATH
server through the same code the runtime uses, so it catches a server
that is present but not runnable — most commonly `rust-analyzer` as a
rustup proxy when the component was never installed (`rustup component
add rust-analyzer`).

When the agent reads a workspace, `cmagent doctor` also suggests servers
for languages it sees in your files but that aren't installed.

## Indexing note

A language server indexes asynchronously on first use. The very first
query in a session — especially `definition` — can come back empty while
indexing is still in flight; retrying a few seconds later resolves it.
There is no manual "index" step; it happens automatically. (cmagent
keeps the server alive for the whole session, so this cold cost is paid
once per session, not per query.)
