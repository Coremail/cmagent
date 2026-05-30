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

## Supported language servers

cmagent resolves a server by file extension. The command and arguments
below are fixed (defined in `crates/cmagent-lsp/src/servers.rs`) — they
are **not** user-configurable today; install the binary on `PATH` and
cmagent uses it as-is. `cmagent lsp list` prints this table with live
install status.

| Language | Server (command) | File types | Install |
|---|---|---|---|
| Rust | `rust-analyzer` | `.rs` | `rustup component add rust-analyzer` |
| Python | `pyright-langserver` | `.py` `.pyi` | `npm i -g pyright` |
| TypeScript / JavaScript | `typescript-language-server` | `.ts` `.tsx` `.js` `.jsx` `.mjs` `.cjs` | `npm i -g typescript-language-server typescript` |
| Go | `gopls` | `.go` | `go install golang.org/x/tools/gopls@latest` |
| C / C++ | `clangd` | `.c` `.h` `.cpp` `.hpp` `.cc` `.cxx` | `apt install clangd` / `brew install llvm` |
| Java | `jdtls` | `.java` | `brew install jdtls` / eclipse.org/jdtls |
| C# | `csharp-ls` | `.cs` | `dotnet tool install --global csharp-ls` |
| Ruby | `ruby-lsp` | `.rb` | `gem install ruby-lsp` |
| PHP | `intelephense` | `.php` | `npm i -g intelephense` |
| Kotlin | `kotlin-language-server` | `.kt` `.kts` | `brew install kotlin-language-server` |
| Scala | `metals` | `.scala` `.sc` | `cs install metals` / `brew install metals` |
| Lua | `lua-language-server` | `.lua` | `brew install lua-language-server` |
| Haskell | `haskell-language-server-wrapper` | `.hs` | `ghcup install hls` |
| Elixir | `elixir-ls` | `.ex` `.exs` | github.com/elixir-lsp/elixir-ls |
| Dart | `dart language-server` | `.dart` | included with the Dart SDK |
| Swift | `sourcekit-lsp` | `.swift` | included with Xcode / the Swift toolchain |
| Shell | `bash-language-server` | `.sh` `.bash` `.zsh` | `npm i -g bash-language-server` |
| YAML | `yaml-language-server` | `.yml` `.yaml` | `npm i -g yaml-language-server` |
| Terraform | `terraform-ls` | `.tf` `.tfvars` | `brew install hashicorp/tap/terraform-ls` |
| Zig | `zls` | `.zig` | github.com/zigtools/zls |
| Markdown | `marksman` | `.md` | `brew install marksman` |
| Vue | `vue-language-server` | `.vue` | `npm i -g @vue/language-server` |
| Svelte | `svelteserver` | `.svelte` | `npm i -g svelte-language-server` |
| Astro | `astro-ls` | `.astro` | `npm i -g @astrojs/language-server` |
| OCaml | `ocamllsp` | `.ml` `.mli` | `opam install ocaml-lsp-server` |
| Gleam | `gleam lsp` | `.gleam` | included with the Gleam compiler |
| Clojure | `clojure-lsp` | `.clj` `.cljs` `.cljc` `.edn` | `brew install clojure-lsp/brew/clojure-lsp-native` |
| Nix | `nixd` | `.nix` | `nix profile install nixpkgs#nixd` |
| LaTeX | `texlab` | `.tex` `.bib` | `cargo install texlab` |
| Dockerfile | `docker-langserver` | `.dockerfile` | `npm i -g dockerfile-language-server-nodejs` |
| Prisma | `prisma-language-server` | `.prisma` | `npm i -g @prisma/language-server` |
| F# | `fsautocomplete` | `.fs` `.fsx` `.fsi` | `dotnet tool install --global fsautocomplete` |
| Deno | `deno lsp` | (project-configured) | `curl -fsSL https://deno.land/install.sh \| sh` |
| Typst | `tinymist` | `.typ` | `cargo install tinymist` |

`cmagent lsp list` is the source of truth for this table; run it to see
exact install commands and which servers are already on your `PATH`.

## Indexing, on-disk cache, and per-server setup

A language server indexes asynchronously on first use. The very first
query in a session — especially `definition` — can come back empty while
indexing is still in flight; retrying a few seconds later resolves it.
There is no manual "index" step; it happens automatically. cmagent keeps
the server alive for the whole session, so this cold cost is paid once
per session, not per query — but the server process is shut down when the
session ends.

**cmagent pushes no settings to the server.** It sends the standard
`initialize` request with your real workspace root as `rootUri` plus a
fixed capability set, sends no `initializationOptions`, and answers every
`workspace/configuration` request with `null` ("use your default"). So
whether an index survives between sessions is decided entirely by the
**server**, from its own defaults plus any project-level config files it
reads from the workspace root. Because none of this is configurable
through cmagent, tune it via the server's own config / environment.

What that means in practice for the heavier servers:

| Server | On-disk index? | What you may need to do |
|---|---|---|
| `rust-analyzer` | **No persistent semantic index** — analysis lives in RAM and is rebuilt every session (this is the main cold-start cost on large crates). It does reuse Cargo's `target/` build cache. | Nothing to configure; the re-index on each new session is inherent. Keep `target/` to avoid recompiling. |
| `clangd` | **Yes** — a persistent background index under `.cache/clangd/` in the project; background indexing is on by default, so later sessions are fast. | Provide a `compile_commands.json` at the project root (e.g. `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`, or `bear -- make`); without it clangd can't index reliably. |
| `gopls` | **Yes** — an on-disk cache in the OS cache dir, reused across sessions automatically. | None. |
| `jdtls` (Java) | **Yes** — writes a per-workspace data/index directory on first open; the first session is slow, later ones reuse it. | None for indexing; large projects just need to finish the first index. |
| `metals` (Scala) | **Yes** — writes `.bloop/` and `.metals/` to the project. | Let it import the build once (it does this on first open); a clean checkout re-imports. |

### A note on rust-analyzer "disk cache"

You will see advice to enable `rust-analyzer.cachePriming` (or set it in a
`rust-analyzer.toml`) to "cache the index to `target/` so restarts only
do an incremental update." That is a misconception worth clearing up:

- **rust-analyzer has no persistent semantic index by design.** Not
  persisting caches is a deliberate, long-standing choice; reusing the
  index across restarts is a recurring but still-unimplemented feature
  request. Every fresh process — and cmagent starts one per session —
  rebuilds the analysis in RAM from scratch.
- **`cachePriming` does not write an index to disk.** It only controls
  whether that in-memory index is built *eagerly* at startup (default)
  or *lazily* on the first request. It changes *when* the cold cost is
  paid within a session, not *whether* it carries over to the next one.
- **What actually lives in `target/`** is Cargo's build-artifact cache
  from the `cargo check` that rust-analyzer runs for diagnostics — that
  is reused across sessions and is why you should keep `target/`. It
  speeds up diagnostics, not symbol indexing.

That said, the *channel* is real and useful: a `rust-analyzer.toml` at
the workspace root (or crate root) is **read by the server itself** —
"so that you do not need a rust-analyzer-capable LSP client" — which is
exactly cmagent's situation (it sends no settings). So you *can* tune
rust-analyzer's behaviour through that file even though cmagent passes
nothing; just don't expect `cachePriming` to make restarts skip
indexing. (The `rust-analyzer.toml` feature is still marked unstable
upstream, and only workspace/crate-scoped keys in it are honoured.)

For everything else, the server's own documentation describes its caching
behavior; cmagent neither helps nor hinders it.
