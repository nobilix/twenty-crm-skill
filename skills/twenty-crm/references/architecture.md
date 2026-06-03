# How the skill is built (and why)

Load this when you need to debug setup, understand why something is structured the way it is, or extend the skill.

## The runtime: ocli

The skill drives [`ocli`](https://github.com/EvilFreelancer/openapi-to-cli) (`openapi-to-cli`), a Node CLI that generates commands from an OpenAPI spec. We pin a known-good version (`openapi-to-cli@0.1.15`; the pin lives in `twenty.mjs` as `OCLI_PKG`). Bump it deliberately after re-testing the round-trip — the dependency is single-maintainer with no git tags.

Why ocli (and not Restish, which earlier versions used): ocli resolves the spec **eagerly at `profiles add` time** with a cycle guard, so Twenty's circular `$ref`s (`Person → Company → People[] → Person`) resolve in a fraction of a second and are cached as inlined JSON. No hang, so **no spec-slimming/stubbing is needed** — the full per-tenant spec is used as-is.

## One script: `twenty.mjs`

All three commands live in a single Node script, `scripts/twenty.mjs`, run as `node scripts/twenty.mjs <setup|preflight|refresh>`. It uses only Node's standard library — `fetch` for the spec download, native JSON, a tiny INI reader — and shells out to `ocli` as a subprocess. Nothing to install beyond Node, ocli, and jq; no bundled dependencies.

## What `setup` does, in order

1. Resolve `--url` and `--token` (prompt on a real terminal, the key hidden; else take `--non-interactive` flags or piped lines). Strip a trailing slash from the URL.
2. Pick the profile name: reuse the one already in `config.json` (idempotent re-setup); else `twenty`; else, if another ocli tool already owns `twenty`, fall back to `twenty-crm` / `twenty-N`.
3. `process.umask(0o077)`, then `addProfile()` for the core profile: download `<url>/rest/open-api/core` with the bearer token (validates HTTP 200 + an `openapi` field), write it to a temp file, and `ocli profiles add <name> --api-base-url <url>/rest --openapi-spec <temp> --api-bearer-token <key>`. ocli keeps its own resolved cache; the temp file is deleted.
4. `--with-metadata` only: the same for `<url>/rest/metadata` as `<name>-meta`, then `ocli use <name>` to leave the core profile active.
5. `chmod 600 ~/.ocli/profiles.ini` (a fallback; `umask 077` already makes new files `600`).
6. Write `~/.config/twenty-cli/config.json` = `{ "profile": "<name>" }` (+ `"metadata_profile"` when applicable).

`refresh` repeats steps 3–5 arg-free, reading the profile from `config.json` and the URL + token back out of `~/.ocli/profiles.ini`. Both commands share one `addProfile()` helper.

## Why ocli runs from `$HOME`

ocli's config resolution (`config.ts:resolveConfig`) checks `$PWD/.ocli/profiles.ini`, then `~/.ocli/profiles.ini`, and **defaults to `$PWD/.ocli` when neither exists yet**. So a naive `ocli profiles add` from the agent's working directory would create `./.ocli` *inside that directory* (e.g. the repo), not `~/.ocli`. `twenty.mjs` runs every ocli call with `{ cwd: os.homedir() }`, where `$PWD/.ocli` *is* `~/.ocli` — so writes always land in `~/.ocli`. The agent's own read commands run bare from its cwd and fall through to `~/.ocli` as long as that cwd has no local `.ocli` (preflight warns if it does).

## Why we pre-download the spec

ocli fetches a spec with no auth header, but Twenty's `/rest/open-api/core` requires `Authorization` — so `--openapi-spec <live-url>` would 403. `twenty.mjs` `fetch`es it with the token and hands ocli a local temp file. After that ocli serves API calls from its cached resolved spec, so the temp file (and the recorded `openapi_spec_source` path) don't need to persist.

## The config split: `~/.ocli` vs `~/.config/twenty-cli`

- **`~/.ocli/`** is ocli's own, shared by any ocli-based tool on the machine. It holds the token, base URL, and resolved spec. We don't fork or wrap it — no `OCLI_HOME`/`--config` exists in ocli — we just write into it with a distinctive profile name. This is why the profile is `twenty`, not `default` (`default` is the one name guaranteed to collide).
- **`~/.config/twenty-cli/config.json`** is the skill's only state: a pointer recording the profile name(s). The base URL and token are read back from `~/.ocli/profiles.ini` (single source of truth), so we never duplicate secrets.

## No per-call profile; cohabitation

There is no `--profile` flag on data commands; the active profile is the global `~/.ocli/current`, set by `ocli use` (and by `profiles add`). If a second ocli tool flips `current`, our bare `ocli people_get` fails cleanly (a foreign profile has no `people_get`, or "No current profile configured") rather than returning wrong data. SKILL.md's self-heal is one line: `ocli use <PROFILE>` and retry. We don't proactively flip `current` on every preflight — that would disrupt a concurrent tool.

## Token storage

Plaintext in `~/.ocli/profiles.ini`, hardened to `600`. ocli has no call-time auth injection and no keychain integration, so the earlier three-source model (keychain/env/file) and the `$TWENTY_API_KEY` override are gone — re-run setup to rotate. Accepted tradeoff; documented in the risk note.

## Numeric-field limitation

ocli types each body value from the string passed on the CLI: `true`/`false`/`null` and `{`/`[`-prefixed JSON are parsed; everything else is a string. So a bare `--employees 42` is sent as `"42"` and Twenty rejects it. Numbers nested in a JSON object flag (`--amount '{"amountMicros":…}'`) are preserved. See `api-shape.md` / `ocli-usage.md`.

## Inside `twenty.mjs`

- **`ocli(args)`** — run ocli from `$HOME` (config resolves to `~/.ocli`); dies with ocli's stderr on failure.
- **`fetchSpec` / `addProfile`** — authenticated spec download + (re)create a profile; shared by setup and refresh, for both the core and metadata profiles.
- **`iniGet(section, key)` / `readConfig()`** — thin readers for ocli's INI and our JSON.
- **`profilesFrom(cwd)`** — the profile names ocli resolves from a cwd; captures the whole list, so the `ocli | grep -q` SIGPIPE trap the bash version hit can't recur.
- **`cmdSetup` / `cmdPreflight` / `cmdRefresh`** — the three subcommands. preflight is read-only; it emits `STATUS`/`PROFILE`/`URL`/`METADATA`/`TZ`/`NOW` and warns on a cwd `.ocli` shadow.

## State locations

- `~/.ocli/profiles.ini` — base URL + plaintext bearer token (mode 600), one `[section]` per profile
- `~/.ocli/current` — active profile name
- `~/.ocli/specs/<profile>.json` — ocli's resolved (inlined) spec cache
- `~/.config/twenty-cli/config.json` — our pointer: `{ profile, metadata_profile? }`

Override our dir with `TW_CONFIG_DIR=<path>` (used by tests, alongside a throwaway `$HOME` so ocli's home is a scratch dir too).
