# ocli patterns for Twenty

[`ocli`](https://github.com/EvilFreelancer/openapi-to-cli) (`openapi-to-cli`) generates a CLI from your workspace's OpenAPI spec. The skill creates one ocli **profile** (default name `twenty`) holding the base URL + bearer token, plus the metadata profile (`twenty-meta`) when set up with `--with-metadata`. ocli sends `Authorization: Bearer <token>` itself.

## Anatomy of a call

```
ocli people_id_patch --id <uuid> --jobTitle "CTO"
     └─────┬──────┘  └────┬───┘ └──────┬───────┘
      command name    path param    body field (→ JSON body)
```

The active profile is global (`~/.ocli/current`); commands are **not** prefixed by the profile name. ocli prints the raw HTTP response body to stdout — pipe to `jq`.

## Command naming — `<path>_<method>`

ocli builds each command from the HTTP path + method, **ignoring `operationId`**:

- `GET /people` → `people_get`     · `POST /people` → `people_post`
- `GET /people/{id}` → `people_id_get`   · `PATCH /people/{id}` → `people_id_patch`   · `DELETE /people/{id}` → `people_id_delete`
- bulk (no id): `PATCH /people` → `people_patch`   · `DELETE /people` → `people_delete`
- metadata profile: `GET /objects` → `objects_get`, `GET /fields` → `fields_get`, etc.

Twenty's metadata spec has no `operationId`s — irrelevant here, since names come from the path. Construct the name from the convention rather than dumping all commands.

### Discovery

```bash
ocli commands              # list every command + description (long)
ocli people_get --help     # query params / path params / body fields for one command
```

`ocli commands -q "<text>"` exists but ranks poorly (a BM25 search) — prefer the naming convention + `--help`. Authoritative field shapes are in the resolved spec at `~/.ocli/specs/<profile>.json`.

## Request building

- **Query params** → flags by their spec name (snake_case): `--filter`, `--order_by`, `--limit` (default 60), `--depth` (`0`|`1`, default 1), `--starting_after`, `--ending_before`. See `filter-dsl.md`.
- **Path params** → `--id <uuid>`.
- **Request body** → one flag per top-level field (`ocli <cmd> --help` lists them). Unknown flags also pass through to the body, so **custom fields** work: `--myCustomField value`.

### Value rules (important)

ocli decides each body value's JSON type from the **string you pass**, not the schema:

| You pass | Sent as | Use for |
| --- | --- | --- |
| `--jobTitle "CEO"` | string `"CEO"` | scalar strings, enums, UUIDs, ISO dates |
| `--idealCustomerProfile true` | boolean `true` | `true` / `false` / `null` |
| `--name '{"firstName":"Jane"}'` | parsed JSON object | composite fields, arrays — numbers **inside** are preserved |
| `--employees 42` | string `"42"` ⚠️ | — see below |

**Numeric limitation:** a bare numeric flag is transmitted as a string, and Twenty rejects it (`Invalid number value '42' for field "employees"`). There is no flag form that sends a bare number. Numbers nested in a JSON object flag (e.g. `--amount '{"amountMicros":25000000000,"currencyCode":"USD"}'`) are fine because the whole value is JSON-parsed. So:

- Money / composite numeric fields → pass as JSON. ✅
- Top-level integer fields (`employees`, `position`) → can't be set via ocli; omit them or set in the UI.

### Composite/nested fields are JSON

```bash
ocli people_post \
  --name   '{"firstName":"Ada","lastName":"Lovelace"}' \
  --emails '{"primaryEmail":"ada@example.com"}' \
  --phones '{"primaryPhoneNumber":"+15551234","primaryPhoneCountryCode":"US"}' \
  --jobTitle 'Engineer'
```

## Output → jq

ocli prints the raw body, so use `jq` (not a projection flag):

```bash
ocli companies_get --limit 10 | jq '.data.companies[] | {name, domain: .domainName.primaryLinkUrl}'
ocli people_get --limit 1 | jq '.totalCount'
ocli people_id_get --id <uuid> | jq -r '.data.person.emails.primaryEmail'
```

Wrappers: list → `.data.<plural>` + `.totalCount` + `.pageInfo`; get → `.data.<singular>`; create → `.data.create<Singular>`; update-one → `.data.update<Singular>`; update-many → `.data.update<Plural>`; delete → `.data.delete<Singular>`. Metadata `objects_get` → `.data` is a flat array (older Twenty nested it under `.data.objects`).

## Profiles and selection

```bash
ocli profiles list                 # names, one per line
ocli profiles show twenty          # base URL etc. (token shown as “(set)”)
ocli use twenty                    # set the active profile
```

There is **no per-call `--profile` flag** — selection is the global `~/.ocli/current`. Setup leaves the core profile active. If another ocli tool flips `current`, a data command fails cleanly ("No current profile configured", or a command-not-available error). Fix: `ocli use <PROFILE>` (the name from preflight) and retry.

## Access and secrets

- **Plaintext token.** The bearer token is stored in `~/.ocli/profiles.ini`, hardened to mode `600` (setup runs under `umask 077`). It is not printed by normal commands; `ocli profiles show` masks it. Treat `profiles.ini` like a password file. If it ever leaks, rotate the API key in Twenty and re-run setup.
- **Sandboxed / restricted agents** (e.g. Codex with a managed profile): ocli must be able to **read and write `~/.ocli/`** (profiles + the spec cache) and reach the network. node must be on `PATH`. A sandbox that blocks the home dir or network typically surfaces as a bare error; grant access to `~/.ocli` or run the CRM calls outside the sandbox.
- **cwd shadow.** ocli resolves config from `$PWD/.ocli` first, then `~/.ocli`. A stray `.ocli` directory in the working directory will hide the global profile. `preflight` warns when `$PWD/.ocli` exists; remove it or run from another directory.

## Troubleshooting

- **`Invalid number value '…'`** — a numeric field was sent as a string (see Value rules). Nest it in a JSON object flag, or omit it.
- **HTTP 401 / 403** — token expired or revoked. Recreate the API key in Twenty, then re-run setup (it rewrites the token).
- **`No current profile configured` / command not available** — the active profile isn't ours. `ocli use <PROFILE>` and retry.
- **`Missing required options: --id`** — that command needs a path param; check `--help`.
- **Custom field / object missing from `--help`** — the cached spec is stale. `node scripts/twenty.mjs refresh`.
- **Rate-limited (429)** — ~100 req/min per token. Slow down; prefer `--depth 0` and projections to keep payloads small.
