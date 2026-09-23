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

### Telling someone you are working on it

On a channel that can show a draft, the reply appears as a placeholder
and fills in, so there is something to look at while the agent thinks.
Where there is no draft -- WeChat, Lunkr, or any account with
`stream_mode = "off"` -- there is nothing at all between the question
and the finished answer, and a slow turn is indistinguishable from a
broken one.

Two per-account settings fill that gap:

```toml
[accounts.config]
ack_delay_secs = 4                                  # 0 = off (the default)
ack_texts = ["one moment", "let me look", "checking"]
```

After `ack_delay_secs` seconds of a turn still running, one of
`ack_texts` is sent. Both are in the desktop settings screen under the
account's Behaviour section.

What it does NOT do, each on purpose:

- **Nothing when the answer is quick.** The message is raced against
  the reply, so a turn that finishes in two seconds sends none. That is
  what makes it safe to leave on.
- **Nothing on a channel that shows a draft.** Gated on whether a draft
  was actually created, not on the platform, so a Telegram account with
  streaming off gets one and the same account with streaming on does
  not.
- **Nothing without `ack_texts`.** A delay on its own sends nothing
  rather than a built-in sentence: whatever goes out carries the
  operator's name, in their language.
- **One per turn, and never a stream of them.** Three messages while
  the agent works get three answers, not three reminders.
- **It is not part of the conversation.** The agent never sees it. In
  its own context the model would find itself having already answered.
- **Off unless asked for.** This sends an unsolicited message from your
  account; no existing deployment starts doing that because the code
  shipped.

### From a shell: `cmagent im`

The same two tools, driven from a terminal instead of by the agent:

```sh
cmagent im list                       # channels configured on this machine
cmagent im describe -t telegram       # what that adapter supports

# reading
cmagent im chats    -t telegram [--query work] [--limit 20]
cmagent im messages -t telegram --chat <chat-id> [--limit 20]
cmagent im contacts -t lunkr --query "zhang"
cmagent im members  -t slack --chat <channel-id>
cmagent im download -t telegram --ref <attachment-ref> [--save-to out.pdf]

# sending
cmagent im send   -t telegram --to <chat-id> --text "build is green"
cmagent im file   -t lunkr --to <uid> --path report.pdf
cmagent im notify -t telegram --text "the migration finished"
```

Every command takes `--json` for the raw tool payload, which is what to
parse in a script; without it the output is formatted for reading.

No provider, no agent, no LLM call: the registry is built from the
channel configs on disk, so it is a fast one-shot command. Useful in a
script or a Makefile -- "ping me when this finishes" without an agent in
the loop.

It is a second FRONT-END, not a second implementation. It builds the
same registry and hands the same tool the same argument object, so every
guardrail above applies unchanged: `allow_outbound_send` still gates
sending, an adapter that lacks an action still answers `not_supported`,
and an action added to `messaging_send` shows up here for free. A CLI
that called the adapters directly would have had to restate all of
that -- and `allow_outbound_send` would have become a setting the agent
honours and the CLI ignores.

`cmagent im send --help` lists the rest of the flags.

Nine send-class actions are deliberately absent -- `edit_message` and
`delete_message` need the id of a message this process does not
remember, `send_buttons`'s useful form blocks waiting for a click,
`open_modal` and `create_thread` attach to a live interaction a shell
does not have, and `add_friend` / `accept_friend` / `send_pat` are
interactive Lunkr features. Each is listed with its reason in
`DECLINED_ACTIONS` (`src/commands/im.rs`), and a test fails when an
action is added to either tool until it is either exposed here or
declined there: the read half of this CLI was missing for a month
because nothing enumerated the set.

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
