# How the skill is built (and why)

Load this when you need to debug setup, understand why something is structured the way it is, or extend the skill.

## What `setup.sh` does, in order

1. Validate `--name` (regex `^[a-z0-9-]+$`) and normalize `--url` (strip trailing slash).
2. Resolve the API key: explicit `--token`, else read from the chosen source if it already exists.
3. Fetch full OpenAPI specs (`/rest/open-api/core` and `/rest/open-api/metadata`) with the bearer token. Atomic write via mktemp + mv. This doubles as token validation.
4. Run `slim-spec.sh` over both specs; write side-by-side as `core.json` (slim) + `core.full.json` (raw), same for metadata.
5. Persist the token via the chosen source: keychain (`security add-generic-password -U`), file (`umask 077` then write, mode 600), or env (no-op — user exports the var).
6. Atomically update `~/.config/twenty-cli/instances.json` with `{base_url, token_source, slim}`. Also sets `default` if it's the first instance or `--set-default` was passed.
7. Atomically update Restish's `apis.json` with two entries: `twenty-<name>-core` and `twenty-<name>-meta`. Each points at the slim spec file and configures `auth: external-tool` to invoke `auth-helper.sh <name>`.

## Why the slim spec + schema stubbing

Twenty's per-tenant OpenAPI has circular `$ref` cycles between schemas (`Person → Company → People[] → Person`). Restish's parser expands schemas eagerly during startup and never terminates on these cycles — `restish` hangs at 100% CPU and grows past 1 GB RSS in seconds.

Workaround in `slim-spec.sh`: replace every `components.schemas.X` with `{"type":"object"}`. The CLI surface (operations, parameters, descriptions) is unaffected; only request/response field validation in `--help` is dropped. The full spec stays available at `core.full.json` for the agent to read whenever it needs exact field shapes or enum values.

Path filtering (default 8 objects: people/companies/opportunities/tasks/notes + targets + workspaceMembers) is a separate concern — purely about CLI ergonomics, not parser correctness. `--full` keeps all paths; both modes still stub schemas.

## Why `external-tool` auth instead of inline token

Restish's other auth modes write the bearer token into `apis.json` in plaintext. `external-tool` calls a script per request and reads its stdout for header injection. We use it to:

- Keep the token out of any config file under `~/Library/Application Support/restish/` or `~/.config/restish/`.
- Source the token from wherever the user prefers (keychain / env / file) without Restish having to know.
- Let `$TWENTY_API_KEY` override transparently for CI and ad-hoc cases.

The cost is one extra process + token read per HTTP request. On macOS, `security find-generic-password` dominates (~tens of ms); for batch work, an `env` token source avoids that.

## Why three token sources

Different environments have different "right" answers:

- **`keychain`** — single-user macOS workstations. Native, no extra deps, locked when screen locks.
- **`env`** — CI, Docker, agent runners. Set once via secrets manager.
- **`file`** — Linux/WSL boxes without a system keyring; also useful when the user's tooling already mounts secret files.

The runtime override `$TWENTY_API_KEY` shortcuts all three when present, so a user can temporarily switch tokens (e.g. test a key with reduced scope) without reconfiguring.

## Why `preflight.sh` emits structured output

Agents (and humans) consume preflight's stdout. Format is one `KEY=VALUE` per line so it parses with a one-line `awk` / `grep` and the agent doesn't have to call jq on the JSON config to find the default instance or its base URL. `URL_<name>=<base-url>` is what powers the "always link back to UI" rule in SKILL.md.

When config is broken or missing, preflight exits non-zero and writes a structured report on stderr describing both setup paths (user-driven and agent-driven). This is the contract that lets the skill self-bootstrap from a fresh checkout.

## File responsibilities

- **`lib.sh`** — sourced by every other script. Exports paths (`TW_*`), token resolution, atomic-jq, spec fetch.
- **`auth-helper.sh`** — invoked per HTTP request by Restish. Drains stdin, resolves token, prints one-line JSON.
- **`setup.sh`** — interactive + non-interactive configuration. The only entry point that writes to `instances.json` and `apis.json`.
- **`refresh-schema.sh`** — re-download + re-slim specs for an existing instance, clear Restish CBOR cache. Reads slim args from the persisted `instances.json` so it produces the same shape `setup.sh` did.
- **`slim-spec.sh`** — pure JSON transformer (schema-stub mandatory, path-filter optional). No `lib.sh` dependency; can be run standalone.
- **`preflight.sh`** — read-only check; never modifies state.
- **`install-restish.sh`** — optional bootstrap; brew or `go install`.

## State locations

- `~/.config/twenty-cli/instances.json` — instance registry
- `~/.config/twenty-cli/specs/<name>/{core,metadata}{,.full}.json` — downloaded specs
- `~/.config/twenty-cli/tokens/<name>` — only when `token_source.type == file`
- `~/Library/Application Support/restish/apis.json` (Mac) or `~/.config/restish/apis.json` (Linux) — Restish API registrations
- `~/Library/Caches/restish/twenty-<name>-{core,meta}.cbor` (Mac) or `~/.cache/restish/...` (Linux) — Restish's parsed-spec cache; cleared by `refresh-schema.sh`
- macOS Keychain entries (when `token_source.type == keychain`): account `twenty-<name>` / service `api` by default

Override the config dir with `TW_CONFIG_DIR=<path>` (useful for tests; the lib reads it at source time).
