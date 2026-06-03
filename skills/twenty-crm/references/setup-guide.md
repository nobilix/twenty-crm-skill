# First-time setup

Load this when `preflight` reports `STATUS=not_ready`, or whenever a user needs to connect a Twenty instance. It walks through what `setup` needs — **server URL** and **API key** — and the prerequisites.

## At a glance

1. Install prerequisites: Node.js ≥18, `ocli`, `jq`.
2. Find your **base URL** (the address you open Twenty at).
3. Create an **API key** in Twenty: Settings → APIs & Webhooks → Create API Key → name it → Save → **Copy** (shown once).
4. Run `setup` with those two values.
5. Run `preflight` to confirm `STATUS=ready`.

## 1. Prerequisites

```bash
node --version       # ≥ 18  (https://nodejs.org)
ocli --version       # if missing: npm i -g openapi-to-cli@0.1.15
jq --version
```

`ocli` ([openapi-to-cli](https://github.com/EvilFreelancer/openapi-to-cli)) is a Node package; install it globally with the pinned version above. (Its `--version` prints `0.1.0` even when the npm package is `0.1.15` — a known quirk; trust `npm ls -g openapi-to-cli`.)

## 2. URL

Always use **the address you open Twenty at in the browser** — `setup` appends `/rest`. That single origin serves both the REST API and the clickable record links the agent shows you.

| Deployment   | URL                                                          |
| ------------ | ------------------------------------------------------------ |
| Self-hosted  | Your Twenty app address, e.g. `https://crm.your-company.com` |
| Twenty Cloud | Your workspace subdomain, e.g. `https://your-workspace.twenty.com` |

> **Cloud: use your workspace subdomain, not `https://api.twenty.com`.** The shared `api.twenty.com` host answers REST calls but has no UI — so record links like `https://api.twenty.com/objects/companies` won't open. Your workspace URL serves the API *and* produces working links.

No trailing slash needed. If you get the URL wrong, setup fails fast: it validates by fetching `<url>/rest/open-api/core` before saving anything.

## 3. API key

In the Twenty web app:

1. **Settings → APIs & Webhooks**.
2. Click **Create API Key**.
3. Give it a **name** (this shows up as the author on records the skill creates — pick something recognizable like `agent` or `claude-code`).
4. **Save**, then **Copy** the key immediately — it's shown only once.

The key is a long JWT-style string (it contains dots). Treat it like a password.

## 4. Run setup

### Interactive (recommended — key never enters chat)

```bash
node scripts/twenty.mjs setup
```

Prompts for the URL and the API key (hidden input).

> **Run this in your own terminal window, not through the agent.** The key is typed as hidden input straight into the script, so it never lands in the chat transcript or any tool log.

### Non-interactive (agent-driven, when the user handed over the values)

```bash
node scripts/twenty.mjs setup --non-interactive --url <url> --token <key>
```

Add `--with-metadata` to also create the schema-admin profile (`<name>-meta`) — only needed for changing the workspace schema (objects/fields/webhooks), which is rare.

## 5. Where the token lives

Setup creates an `ocli` **profile** (default name `twenty`) under `~/.ocli/`. The base URL and bearer token live in `~/.ocli/profiles.ini`, **in plaintext**, hardened to mode `600` (setup runs under `umask 077`). The skill itself records only the profile name in `~/.config/twenty-cli/config.json`.

To **rotate** the key: create a new one in Twenty and re-run `setup` (it overwrites the token). There is no separate keychain/env option — the token lives in the ocli profile.

## 6. Verify

```bash
node scripts/twenty.mjs preflight
# STATUS=ready
# PROFILE=twenty
# URL=<base-url>
```

Then a real round-trip:

```bash
ocli people_get --limit 1 | jq '.totalCount'
```

## Troubleshooting

- **HTTP 401 during setup** — wrong or revoked key. Create a fresh one (step 3) and re-run.
- **`not valid OpenAPI` / connection error** — wrong base URL, or the server isn't reachable from here. Confirm the URL opens in a browser.
- **`ocli profile 'twenty' not found`** — setup hasn't run (or ran elsewhere). Run `setup`.
- **preflight warns about a local `.ocli`** — a `.ocli` directory in your current folder shadows `~/.ocli`. Remove it or run from another directory (see `ocli-usage.md`).
- **`Invalid number value`** when creating a record — a numeric field was passed as a bare flag; ocli sends it as a string. Nest it in a JSON object flag or omit it (see `api-shape.md`).
