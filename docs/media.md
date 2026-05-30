# Media (Vision, TTS, STT)

cmagent has three optional media capabilities, all backed by the
`cmagent-media` crate over **OpenAI-compatible** HTTP APIs:

| Capability | What it adds | Config file | Surfaced as |
|---|---|---|---|
| **Vision** | the agent can describe / read images | `~/.cmagent/vision.toml` | the `vision` tool |
| **TTS** (text-to-speech) | the agent can synthesise speech | `~/.cmagent/tts.toml` | the `tts` tool + Telegram voice replies |
| **STT** (speech-to-text) | inbound voice messages are transcribed | `~/.cmagent/stt.toml` | channel feature (no tool) |

Each is independent: configure only the ones you want. None is on by
default. The easiest way to set one up is the wizard, which probes the
backend and writes the file for you:

```sh
cmagent config vision     # or: cmagent config tts | cmagent config stt
```

You can also edit the files by hand (formats below). A file is only
honoured when its required keys are present — at minimum `base_url` and
`model`. The wizard writes a few extra display/conversion keys
(`provider`, `backend`, `output_type`, `telegram_ready`); those are
harmless if absent — only the keys called out as "read by the runtime"
below actually drive behaviour.

API keys live in `~/.cmagent/.env` (or your shell), referenced by
*name* via `api_key_env` — never the secret itself. See
[configuration-guide.md](configuration-guide.md#env-file).

## Vision — `~/.cmagent/vision.toml`

Registers the `vision` tool (risk `Low`): given an image path, it returns
a text description from a vision-capable chat model. The image is sent
through the normal provider factory, so any backend that accepts image
input works (`openai`, `anthropic`, `glm`, …).

```toml
provider    = "openai"                       # display only
backend     = "openai"                        # provider factory backend
base_url    = "https://api.openai.com/v1"     # required
model       = "gpt-4o"                         # required, must accept images
api_key_env = "OPENAI_API_KEY"                 # env var name holding the key
```

Read by the runtime: `base_url`, `model`, `backend`, `api_key_env`.
The tool registers only when `base_url` and `model` are both set.

## TTS — `~/.cmagent/tts.toml`

Registers the `tts` tool (risk `Low`) — text in, an audio file out via
the OpenAI-compatible `/audio/speech` endpoint — and powers Telegram's
voice replies.

```toml
provider        = "openai"                     # display only
backend         = "openai"                     # display only
base_url        = "https://api.openai.com/v1"  # required
model           = "tts-1"                       # required
voice           = "alloy"                       # default: "default"
response_format = "mp3"                         # default: "mp3" (e.g. mp3 | wav | opus)
api_key_env     = "OPENAI_API_KEY"
```

Read by the runtime: `base_url`, `model`, `api_key_env`, `voice`,
`response_format`. The tool registers only when `base_url` and `model`
are set.

Delivering a voice message on a channel may require re-encoding to the
platform's codec (Telegram wants OGG/Opus, WeChat wants SILK); that
conversion uses **ffmpeg**, so install ffmpeg if you want voice replies.

## STT — `~/.cmagent/stt.toml`

Speech-to-text is **not** an agent tool. It runs on the inbound path of
the channels that support voice (Telegram, WeChat, Lunkr): a received
voice message is transcribed via the OpenAI-compatible
`/audio/transcriptions` endpoint before the agent's turn, so the agent
reads text. See [channels.md](channels.md#voice-messages-stt--tts).

```toml
provider          = "openai"                     # display only
backend           = "openai"                     # display only
base_url          = "https://api.openai.com/v1"  # required
model             = "whisper-1"                   # required
api_key_env       = "OPENAI_API_KEY"
max_duration_secs = 120                            # skip clips longer than this (default: 120)
```

Read by the runtime: `base_url`, `model`, `api_key_env`,
`max_duration_secs`. Transcription converts the audio to a format the
API accepts (WAV), which needs **ffmpeg** on PATH.

## Checking status

`cmagent config` (with no section) prints whether TTS and Vision are
configured (and the provider/model each points at). If a configured
feature needs format conversion, make sure `ffmpeg` is on your `PATH` —
without it, voice send/transcription falls back to whatever the API
accepts natively, or fails.
