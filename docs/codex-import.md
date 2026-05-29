# Importing credentials from the Codex CLI

If you already use the [OpenAI Codex CLI](https://github.com/openai/codex),
cmagent can re-use the credentials it stored locally so you don't
have to manage a second OpenAI account or copy keys around.

The codex CLI stores its credentials at `~/.codex/auth.json` (or
`$CODEX_HOME/auth.json`). Depending on how you logged in, the file
holds **either** an OpenAI API key **or** ChatGPT-account OAuth
tokens. cmagent supports both, with different trade-offs.

## TL;DR

```bash
# Option A: codex logged in with an API key
cmagent config provider
  -> Import from Codex CLI (~/.codex/auth.json)
# A standard OpenAI provider is created. Bills against your API key.

# Option B: codex logged in with a ChatGPT account
cmagent config provider
  -> Import from Codex CLI (~/.codex/auth.json)
  -> [accept ToS notice]
# An openai_codex provider is created. Bills against your ChatGPT
# subscription via chatgpt.com/backend-api/codex.
```

`cmagent doctor` reports the current state of both
`~/.codex/auth.json` and cmagent's own token store, so you can see at
a glance whether import will work.

## How the wizard detects the flow

`cmagent config provider` -> `Import from Codex CLI` reads
`~/.codex/auth.json` (or `$CODEX_HOME/auth.json`) and classifies it:

| auth.json contains            | cmagent does                                            |
|-------------------------------|---------------------------------------------------------|
| non-empty `OPENAI_API_KEY`    | API-key import path -- standard openai backend          |
| `tokens` object only          | OAuth import path -- new `openai_codex` backend         |
| neither / corrupt             | Surfaces a diagnostic. Re-run `codex login`             |
| absent                        | Suggests installing codex first                         |

When both fields are populated the API key wins, since it's the
simpler path and avoids the OAuth refresh treadmill.

## Path A: API key

Wire format: standard OpenAI `/v1/chat/completions`. Behaves
identically to any other API-key OpenAI account.

What the wizard does:
1. Reads the key from `~/.codex/auth.json`.
2. Asks for a config name (default `openai-codex`).
3. Saves the key into `<base>/.env` as `OPENAI_CODEX_API_KEY`.
4. Writes a provider config at `<base>/providers/openai-codex.toml`
   with `backend = "openai"`, `base_url = "https://api.openai.com/v1"`,
   `model = "gpt-4o-mini"`.

Edit the file directly (or use `cmagent config provider -> Edit`) to
change the model.

## Path B: ChatGPT-account OAuth

**Before importing, read the ToS notice the wizard prints.**

The codex CLI is OpenAI's official ChatGPT-account client. Using a
non-codex client (such as cmagent) with these tokens may violate
OpenAI's terms of service in some jurisdictions. Requests are billed
against your ChatGPT subscription, not the OpenAI API, and access can
be rate-limited or revoked by OpenAI at any time. The wizard asks
for explicit acknowledgement before proceeding.

### What gets created

1. cmagent **copies** the tokens (`access_token`, `refresh_token`,
   `id_token`, `account_id`) from `~/.codex/auth.json` into its own
   store at `<base>/data/codex_auth.json`. This file is mode 0600 on
   Unix, written atomically.

   Why a copy? `~/.codex/auth.json` is owned by the codex CLI, which
   refreshes it concurrently. Two clients fighting over the same
   refresh token tend to invalidate each other. cmagent maintains an
   independent store so neither client breaks the other -- if codex
   ever rotates the refresh token under us, you simply re-import.

2. A provider config at `<base>/providers/openai-codex.toml`:

   ```toml
   backend = "openai_codex"
   base_url = "https://chatgpt.com/backend-api/codex"
   model = "gpt-5.5"
   description = "OpenAI Codex (ChatGPT account, imported via codex CLI)"

   [auth]
   method = "oauth"

   [features]
   tool_calling = true
   vision = true
   thinking = true
   max_context_tokens = 200000

   [thinking]
   protocol = "openai"
   reasoning_effort = "medium"
   ```

### How requests work end-to-end

The `openai_codex` provider:

1. Loads tokens from `<base>/data/codex_auth.json` at startup.
2. Before every request, checks whether the access_token's JWT `exp`
   claim is within 60s of expiry; if so, refreshes via
   `https://auth.openai.com/oauth/token` using the codex CLI's
   published public client id (`app_EMoamEEZ73f0CkXaXp7hrann`).
   Successful refreshes are persisted back to disk.
3. Translates cmagent's chat-style messages into Responses API
   `input` items (`function_call`, `function_call_output`, plain
   `{role, content}`). System messages collapse into the `instructions`
   field.
4. POSTs to `/responses` with these required Cloudflare-mitigation
   headers (chatgpt.com refuses anything that doesn't look like a
   first-party codex client):

   - `Authorization: Bearer <access_token>`
   - `originator: codex_cli_rs`
   - `User-Agent: codex_cli_rs/<version> cmagent`
   - `ChatGPT-Account-ID: <extracted from id_token JWT claim>`
   - `OpenAI-Beta: responses=experimental`

5. Streams the response: parses SSE events
   (`response.output_text.delta`,
   `response.function_call_arguments.delta`,
   `response.output_item.added`, `response.completed` /
   `response.incomplete` / `response.failed`).
6. On a 401 the provider refreshes once and retries the request.

## Verifying it works

```bash
cmagent doctor
# look for:
#   Codex CLI: ChatGPT-account OAuth tokens at ~/.codex/auth.json
#   cmagent codex tokens: ~/.cmagent/data/codex_auth.json (access_token fresh)
```

Then run a one-shot prompt:

```bash
cmagent --provider openai-codex -m "say hi"
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `auth.json not found` | codex CLI not installed or never logged in | Run `codex login`, then re-run import |
| `relogin required: auth.openai.com returned 400` | refresh_token expired or consumed by another client | `codex login` again, then re-run import |
| `cf-mitigated` 403 from chatgpt.com | account id missing or originator header stripped | Re-import to refresh tokens; check that the id_token still contains a valid `chatgpt_account_id` claim |
| `parse responses body` errors | OpenAI changed a field name in the Responses API | Open an issue with the failing response; the parser uses `#[serde(other)]` for unknown items so most additions land gracefully |

## Switching back to API key

```bash
codex logout
codex login --api-key sk-...
# in cmagent: re-run the import; it will detect the API-key shape
```

The old `openai_codex` provider config can be removed via
`cmagent config provider -> Remove`. The token store at
`<base>/data/codex_auth.json` can be deleted by hand once that
provider is gone.
