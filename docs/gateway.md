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
