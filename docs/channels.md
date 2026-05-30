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

## Per-channel capabilities

Adapters differ in what they implement. `messaging_query
{ action: "describe_channel", channel }` returns the live truth for a
given install (including the size/length constraints the agent should
respect); the table below is the shipped baseline. A `—` action returns
a clean `not_supported` error.

| Capability | Lunkr | Telegram | Slack | Discord | WeChat |
|---|:---:|:---:|:---:|:---:|:---:|
| Adapter kind | bot / user¹ | bot | bot | bot | bot |
| `send_message` | ✓ (plain) | ✓ (markdown, ≤4096) | ✓ (`mrkdwn`) | ✓ (≤2000) | ✓ |
| `send_file` | ✓ (≤10 files) | ✓ (≤50 MB) | ✓ | ✓ (≤25 MB, ≤10) | ✓ |
| `edit_message` | ✓ | — | — | — | — |
| `delete_message` | ✓² | — | — | — | — |
| `send_buttons` (`wait_response`) | ✓ (blocks, 300 s) | — | — | — | — |
| `send_embed` | — | — | — | ✓ (≤25 fields) | — |
| `open_modal` | — | — | ✓³ | — | — |
| `create_thread` | — | — | — | ✓ | — |
| `search_contacts` | ✓ | — | — | — | — |
| `list_chats` | ✓ | — | — | — | — |
| `list_messages` | ✓ | — | — | — | — |
| `download_attachment` | ✓ | — | — | — | — |
| `notify` | per-config⁴ | per-config⁴ | per-config⁴ | per-config⁴ | per-config⁴ |

¹ Lunkr runs as a bot account, or in "user" (clone) role impersonating
the operator; clone role cannot self-send (Lunkr rejects sending to the
operator's own uid). Lunkr is the only full-service adapter — history,
directory, edit, and interactive buttons all work.
² Lunkr delete is emulated by editing the message to empty content;
observers see an edit-history mark.
³ Slack `open_modal` needs a `trigger_id` (valid ~3 s) issued when a user
interacts; the agent can't synthesise one.
⁴ `notify` is available on any channel where the account sets
`notify_recipient` (see the notify shortcut above); it is the one
cross-scope action.

**Other quirks worth knowing** (also surfaced in `describe_channel`):

- **Telegram** — the bot can't initiate a chat with a user who hasn't
  messaged it first; Bot API rate limit is 30 messages/sec.
- **Slack** — the bot must be invited to a channel before it can post;
  DMs by user id work directly.
- **Discord** — the bot must be invited to a guild before posting there;
  DMs require the user and bot to share a guild; `create_thread` needs
  the `CREATE_PUBLIC_THREADS` permission.
- **WeChat** — the bundled iLink adapter implements only `send_message` /
  `send_file`; `add_friend` / `accept_friend` / `send_pat` exist on the
  platform but aren't exposed. The iLink `context_token` expires quickly,
  so a cold outbound send may be rejected.

## Voice messages (STT / TTS)

Some channels handle voice in addition to text:

- **Inbound voice → text (STT).** Telegram, WeChat, and Lunkr transcribe
  incoming voice messages before the agent sees them, when speech-to-text
  is configured.
- **Outbound text → voice (TTS).** Telegram can reply with a voice
  message when text-to-speech is configured.

Both are optional and configured separately from the channel — see
[media.md](media.md) for `stt.toml` / `tts.toml`.
