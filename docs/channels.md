# Channels (messaging)

cmagent can run as a bot on chat platforms: it receives messages on a
channel, runs an agent turn, and replies — and agents can proactively
send messages out (notifications, files, interactive buttons). One agent
can serve many channels; each channel-bound conversation gets its own
persistent session.

Supported channels: **Lunkr, Telegram, Slack, Discord, WeChat (Weixin)**.

## Configuration

Each channel is configured per-account under `~/.cmagent/channels/`
(one config per platform, with one or more accounts). Typical fields:
which agent handles the channel, trigger policy (DMs, group mentions),
and whether the account may send.

Run `cmagent config` to set a channel up interactively, then start the
[gateway](gateway.md) (which hosts the channel adapters) or the relevant
runner.

## Receiving: trigger policy & audit

Each adapter decides per message whether to trigger an agent turn
(DM allowlist, group `require_mention`, per-group enable). Messages that
*don't* trigger are dropped with a recorded reason.

Optionally, an account can record **all** inbound messages — triggered
and dropped — into a global audit log
(`~/.cmagent/data/audit.db`, enable with `audit_log = true` in the
account config). Agents read it only through the `audit_query` tool, and
only a profile that lists that tool (the shipped `sys-auditor`) can — pair
it with a cron job for daily summaries.

## Sending: unified messaging tools

All agent-initiated messaging goes through two tools, so the agent uses
the same surface regardless of platform:

- **`messaging_query`** (Low risk) — read: `list_channels`,
  `describe_channel`, `search_contacts`, `list_chats`, `list_messages`,
  `download_attachment`. The agent calls `describe_channel` to learn what
  a given adapter supports before acting.
- **`messaging_send`** (Medium risk) — write: `send_message`,
  `send_file`, `edit_message`, `delete_message`, `send_buttons`,
  `notify`, plus platform-specific actions (`send_embed`, `open_modal`,
  `create_thread`, `add_friend`, …). An adapter that lacks an action
  returns a clean `not_supported` error.

### Guardrails

- **Send is opt-in.** A channel account must set
  `allow_outbound_send = true` before any send-class action works
  (default off; `cmagent doctor` errors if more than one account per
  channel enables it).
- **Channel scope.** A session whose id starts with a channel prefix
  (`telegram-`, `slack-`, …) is restricted to that channel for query and
  send. TUI / chat / gateway sessions have no scope and can address any
  configured channel.
- **`notify` shortcut.** Set `notify_recipient` (and optional
  `notify_name`) to pre-wire a target, then a long-running TUI task can
  `messaging_send { action: "notify", channel, text }` to ping you when
  it's done — the one cross-scope exception.

### Interactive buttons

`messaging_send { action: "send_buttons", wait_response: true,
timeout_seconds: N }` blocks until the user clicks and returns the
clicked value — for adapters that advertise `send_buttons.wait_response`
in `describe_channel` (Lunkr today). Otherwise buttons are
fire-and-forget.
