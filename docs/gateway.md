# Gateway Mode

`cmagent gateway` starts an HTTP server that exposes the agent over a REST
and WebSocket API. Use it to:

- Run cmagent on a server and connect from a remote machine via TUI
- Integrate with custom frontends or automation scripts
- Host the built-in web UI

## Quick start

```sh
# Start the gateway (default: 127.0.0.1:3100)
cmagent gateway

# Custom port and bind address
cmagent gateway --port 8080 --bind 0.0.0.0

# Connect the TUI to a remote gateway
cmagent tui --remote http://myserver:3100 --token <token>
```

The gateway prints its endpoints on start:

```
Gateway running at http://127.0.0.1:3100
  API:       http://127.0.0.1:3100/api/openapi.json
  WebSocket: ws://127.0.0.1:3100/ws
  Health:    http://127.0.0.1:3100/api/health
```

## User management

Each client authenticates with a bearer token. Tokens are created with
the `gateway user` subcommand:

```sh
# Add a user
cmagent gateway user add alice --role operator

# List users
cmagent gateway user list

# Remove a user
cmagent gateway user remove alice
```

Roles: `viewer` (read-only), `operator` (send messages), `admin` (manage users).

The bearer token is printed when the user is added. Pass it as an
`Authorization: Bearer <token>` header or as a `?token=<token>` query
parameter for WebSocket connections.

## System service

Install the gateway as a system service so it starts automatically:

```sh
cmagent gateway install   # install and enable
cmagent gateway start     # start the service
cmagent gateway stop      # stop the service
cmagent gateway restart   # restart the service
cmagent gateway status    # check service status
cmagent gateway uninstall # remove the service
```

## API reference

The full OpenAPI spec is served at `GET /api/openapi.json` when the gateway
is running.

### Key endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Health check (no auth) |
| POST | `/api/chat/send` | Send a message |
| GET | `/api/chat/events` | SSE stream of agent events |
| GET | `/api/chat/history` | Conversation history |
| GET/POST | `/api/sessions` | List or create sessions |
| PUT/DELETE | `/api/sessions/{id}` | Rename or delete a session |
| POST | `/api/sessions/{id}/resume` | Resume a session |
| POST | `/api/sessions/{id}/cancel` | Cancel running inference |
| GET | `/ws` | WebSocket (auth via `?token=`) |
| GET | `/api/status` | Agent and channel status |
| GET | `/.well-known/agent.json` | A2A agent card |
| POST | `/api/a2a` | A2A JSON-RPC 2.0 endpoint |

## Channel pairing

To connect a messaging channel (e.g. Telegram) to a gateway instance:

```sh
cmagent gateway pair telegram
```

This prints a one-time code that the channel adapter uses to complete pairing.

## Web UI

The gateway serves a built-in web frontend at `/`. Open it in a browser to
chat with the agent without the TUI.

## Desktop mode, and testing it from another machine

The workspace panel, `/logs` and the whole settings surface are gated on
the gateway having been started with `--desktop`. That flag is
**server**-side on purpose: if a client could set it, anyone holding a
token on a remote gateway could switch those on for themselves.

Desktop mode also pins the bind address to loopback whatever the config
says, and takes an ephemeral port unless given one.

### From a browser on another machine

`scripts/dev-gateway.sh` builds, serves in desktop mode, and prints the
assembled URL with its token:

```bash
# on the machine running cmagent
scripts/dev-gateway.sh --port 38987
```

```bash
# on the machine with the browser
ssh -N -L 38987:127.0.0.1:38987 user@that-host
```

Then open the URL the script printed, with the port it was given.

**Why a fixed port.** Desktop mode's port is ephemeral, so it changes
every run and an `ssh -L` would have to be re-forwarded each time.
Passing `--port` changes nothing about exposure: the bind address is
what decides that, and desktop mode keeps it on loopback.

**Why not `&` or `nohup`.** In desktop mode the gateway exits on stdin
EOF. That is the contract that stops a crashed shell leaving an orphaned
server -- and it means backgrounding it, where stdin is `/dev/null`,
makes it print its handshake line and die immediately. The script keeps
the terminal's stdin; Ctrl-C stops it.

### What this cannot test

Anything that belongs to the native shell rather than the served page:

- adding a workspace (a native folder chooser)
- the update flow and the native menu
- console-window behaviour on Windows
- **the directory the shell starts the gateway in** -- a macOS app
  launched from Finder inherits `/` as its working directory, which is
  the bug `select_gateway_working_dir` fixes. Reproducing it needs the
  packaged app, started the way a user starts it.

For those, run the shell itself: `scripts/dev-desktop.sh` (or
`dev-desktop.ps1`), which links a locally built cmagent beside it.

## Looking at the page without a screen

`scripts/dev-shot.sh` drives the running gateway in headless Chrome:
navigate, click, scroll, screenshot, and read anything out of the laid-out
DOM.

```bash
URL='http://127.0.0.1:38987/?token=...'          # what dev-gateway printed

scripts/dev-shot.sh "$URL" shot:home
scripts/dev-shot.sh "$URL" click:.sb-title-action shot:panel
scripts/dev-shot.sh "$URL" --size 1280x800 \
    click:.sb-title-action scroll:.session-body@0.9 shot:bottom
scripts/dev-shot.sh "$URL" eval:'document.querySelectorAll(".sx-card").length'
```

Screenshots land in `--out` (default `/tmp/cmagent-shot`). It fetches
`chrome-headless-shell` once into `~/.cache/cmagent`, or uses
`$CMAGENT_CHROME` if you already have a browser. No npm packages: the
DevTools protocol needs a WebSocket, and node 21+ has one built in.

**Why this is not a `test-web-*.js` guard.** Those read `app.js` and
`style.css` as text. They are good at "this function is called" and "this
rule exists", and blind to everything that only exists once a browser has
laid the page out. Three defects in the session panel were found by
looking and by nothing else:

- the panel was empty until a turn had run -- the gateway never called
  `sync_state()`, so every card reading `facts` drew nothing
- a restored dialog hung 82px off the right edge, because its saved
  position was clamped before its saved width arrived
- a card headed `0 files` above rows reading 6 and 62

Each one then got a guard, which is the right order: look to find it,
assert to keep it. `dev-shot.sh` is deliberately not in `check.sh` --
it downloads a browser and needs a server already running.

**A debug build serves `assets/web` from disk**, so edits show up on
reload. A release build embeds them and has to be rebuilt --
`dev-gateway.sh` builds release, so pass `--no-build` after
`cargo build` if you want the debug binary's live assets:

```bash
cargo build && sleep 3600 | ./target/debug/cmagent gateway --desktop --port 38988
```

(The `sleep` is stdin: see "Why not `&` or `nohup`" above.)
