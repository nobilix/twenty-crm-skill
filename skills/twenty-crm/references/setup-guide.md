# First-time setup

Load this when `preflight.sh` reports `STATUS=not_ready`, or whenever a user needs to connect a Twenty instance. It walks through the three things `setup.sh` asks for — **server URL**, **API key**, **token storage** — and where each comes from.

## At a glance

1. Install prerequisites: `restish`, `jq`, `curl`.
2. Find your **base URL** (the address you open Twenty at).
3. Create an **API key** in Twenty: Settings → APIs & Webhooks → Create API Key → name it → Save → **Copy** (shown once).
4. Run `setup.sh` with those two values and pick where to store the token.
5. Run `preflight.sh` to confirm `STATUS=ready`.

## 1. Prerequisites

```bash
restish --version    # https://rest.sh
jq --version
curl --version
```

If `restish` is missing: `bash scripts/install-restish.sh` (uses Homebrew, else `go install`, else prints the binary download URL).

## 2. Base URL

The base URL is **the same origin you use to reach Twenty in the browser** — `setup.sh` appends `/rest` automatically.

| Deployment | Base URL |
| --- | --- |
| Self-hosted | The address of your Twenty app, e.g. `https://crm.your-company.com` |
| Twenty Cloud | `https://api.twenty.com` |

No trailing slash needed — setup strips it. If you get the URL wrong, setup fails fast: it validates by fetching `<url>/rest/open-api/core` before saving anything.

## 3. API key

In the Twenty web app:

1. **Settings → APIs & Webhooks**.
2. Click **Create API Key**.
3. Give it a **name** (this name shows up as the author on records the skill creates — pick something recognizable like `agent` or `claude-code`, not just `automation`).
4. Hit **Save**.
5. **Copy** the key immediately — it's shown only once. If you lose it, create a new one.

The key is a long JWT-style string (it contains dots). Treat it like a password.

## 4. Run setup

### Interactive (recommended — key never enters chat)

```bash
bash scripts/setup.sh
```

Prompts for instance name, URL, API key (hidden input), and token storage.

> **Run this in your own terminal window, not through the agent.** The key is typed as hidden input straight into the script, so it never lands in the chat transcript, the agent's context, or any tool log.

### Non-interactive (agent-driven, when the user handed over the values)

```bash
bash scripts/setup.sh --non-interactive \
  --name <name> --url <url> --token-from {keychain|env|file} --token <key>
```

**Instance name** is a short lowercase label (`[a-z0-9-]+`) you'll use in commands — e.g. `myco` → `restish twenty-myco-core ...`. Register as many instances as you like (prod, staging, a cloud workspace) and they coexist.

## 5. Token storage — pick one

| Mode | Best for | Where it lives |
| --- | --- | --- |
| `keychain` | macOS workstation (default) | macOS Keychain (account `twenty-<name>`, service `api`) |
| `file` | Linux / WSL / no system keyring | `~/.config/twenty-cli/tokens/<name>`, `chmod 600` |
| `env` | CI, Docker, agent runners | Environment variable `TWENTY_<NAME>_KEY` |

`keychain` is macOS-only. On **Windows use WSL** and choose `file` or `env`.

> **Use your OS secret manager if you have one (recommended, not required).** On macOS that's the Keychain (`keychain` mode) — the token is encrypted at rest and unlocked with your login. `setup.sh` writes and reads it for you; you never run `security` by hand. No keyring (Linux/WSL)? `file` mode (`chmod 600`) is a fine fallback.

At runtime, `$TWENTY_API_KEY` overrides whatever is stored — handy for ad-hoc keys without reconfiguring.

## 6. Verify

```bash
bash scripts/preflight.sh
# STATUS=ready
# DEFAULT=<name>
# INSTANCES=<name>
# URL_<name>=<base-url>
```

Then a real round-trip:

```bash
restish twenty-<name>-core find-many-people --limit 1 -f body.totalCount -r
```

## Troubleshooting

- **HTTP 401 during setup** — wrong or revoked key. Create a fresh one (step 3).
- **`not valid OpenAPI` / connection error** — wrong base URL, or the server isn't reachable from here. Confirm the URL opens in a browser.
- **`restish` hangs at 100% CPU** — only happens with an un-slimmed spec; setup always slims. If you edited specs by hand, re-run `setup.sh` or `refresh-schema.sh`. See `architecture.md`.
- **Token file gives 401 but looks right** — likely CRLF line endings from a Windows editor. The skill strips them (`tr -d '\r\n'`), but if you hand-wrote the file with trailing whitespace, re-save it with a trailing-newline-free or Unix-LF format.
