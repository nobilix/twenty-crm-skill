# How the skill is built (and why)

Load this when you need to debug setup, understand why something is structured the way it is, or extend the skill.

## The runtime: ocli

The skill drives [`ocli`](https://github.com/EvilFreelancer/openapi-to-cli) (`openapi-to-cli`), a Node CLI that generates commands from an OpenAPI spec. We pin a known-good version (`openapi-to-cli@0.1.15`; the pin lives in `lib.sh` as `TW_OCLI_PKG`). Bump it deliberately after re-testing the round-trip — the dependency is single-maintainer with no git tags.

Why ocli (and not Restish, which earlier versions used): ocli resolves the spec **eagerly at `profiles add` time** with a cycle guard, so Twenty's circular `$ref`s (`Person → Company → People[] → Person`) resolve in a fraction of a second and are cached as inlined JSON. No hang, so **no spec-slimming/stubbing is needed** — the full per-tenant spec is used as-is. The cost is a Node.js runtime dependency.

## What `setup.sh` does, in order

1. Validate that `--url` is present; strip a trailing slash. Prompt for URL + key when interactive.
2. Pick the profile name: reuse the one already in `config.json` (idempotent re-setup); else `twenty`; else, if another ocli tool already owns `twenty`, fall back to `twenty-crm` / `twenty-N`.
3. `umask 077`, then download `<url>/rest/open-api/core` with the bearer token to a temp file (this also validates the token — atomic `mktemp`+`mv`, asserts HTTP 200 + `.openapi`).
4. `ocli profiles add <name> --api-base-url <url>/rest --openapi-spec <temp> --api-bearer-token <key>` — creates/overwrites the profile in `~/.ocli` and makes it current. The temp spec is deleted; ocli keeps its own resolved cache.
5. `--with-metadata` only: repeat for `<url>/rest/metadata` as `<name>-meta`, then `ocli use <name>` to leave the core profile active.
6. `chmod 600 ~/.ocli/profiles.ini` (a fallback; `umask 077` already makes new files `600`).
7. Write `~/.config/twenty-cli/config.json` = `{ "profile": "<name>" }` (+ `"metadata_profile"` when applicable).

`refresh-schema.sh` repeats steps 3–6 arg-free, reading the profile from `config.json` and the URL + token back out of `~/.ocli/profiles.ini`.

## Why `cd "$HOME"` before every ocli write (`tw_ocli`)

ocli's config resolution (`config.ts:resolveConfig`) checks `$PWD/.ocli/profiles.ini`, then `~/.ocli/profiles.ini`, and **defaults to `$PWD/.ocli` when neither exists yet**. So a naive `ocli profiles add` run from the agent's working directory would create `./.ocli` *inside that directory* (e.g. the repo), not `~/.ocli`. `lib.sh:tw_ocli` runs ocli with `cwd = $HOME`, where `$PWD/.ocli` *is* `~/.ocli` — so every write lands in `~/.ocli` regardless of where the script was invoked. The agent's read commands run bare from its own cwd and fall through to `~/.ocli` as long as that cwd has no local `.ocli` (preflight warns if it does).

## Why curl pre-downloads the spec

ocli fetches a spec with a plain `axios.get` and **no auth header**, but Twenty's `/rest/open-api/core` requires `Authorization`. So `--openapi-spec <live-url>` would 403. `tw_fetch_spec` downloads it with the token to a temp file and hands ocli the file. After that, ocli serves API calls from its cached resolved spec, so the temp file (and its `openapi_spec_source` path) don't need to persist.

## The config split: `~/.ocli` vs `~/.config/twenty-cli`

- **`~/.ocli/`** is ocli's own, shared by any ocli-based tool on the machine. It holds the token, base URL, and resolved spec. We don't fork or wrap it — no `OCLI_HOME`/`--config` exists in ocli — we just write into it with a distinctive profile name. This is why the profile is `twenty`, not `default` (`default` is the one name guaranteed to collide).
- **`~/.config/twenty-cli/config.json`** is the skill's only state: a pointer recording the profile name(s). It decouples scripts from a hardcoded name and lets `ocli use` / preflight find the target. The base URL and token are read back from `~/.ocli/profiles.ini` (single source of truth), so we never duplicate secrets.

## No per-call profile; cohabitation

There is no `--profile` flag on data commands; the active profile is the global `~/.ocli/current`, set by `ocli use` (and by `profiles add`). If a second ocli tool flips `current`, our bare `ocli people_get` fails cleanly (a foreign profile has no `people_get`, or "No current profile configured") rather than returning wrong data. SKILL.md's self-heal is one line: `ocli use <PROFILE>` and retry. We don't proactively flip `current` on every preflight — that would disrupt a concurrent tool.

## Token storage

Plaintext in `~/.ocli/profiles.ini`, hardened to `600`. ocli has no call-time auth injection and no keychain integration, so the earlier three-source model (keychain/env/file) and the `$TWENTY_API_KEY` override are gone — re-run `setup.sh` to rotate. Accepted tradeoff; documented in the risk note.

## Numeric-field limitation

ocli types each body value from the string passed on the CLI: `true`/`false`/`null` and `{`/`[`-prefixed JSON are parsed; everything else is a string. So a bare `--employees 42` is sent as `"42"` and Twenty rejects it. Numbers nested in a JSON object flag (`--amount '{"amountMicros":…}'`) are preserved. See `api-shape.md` / `ocli-usage.md`.

## File responsibilities

- **`lib.sh`** — sourced by the others. Paths (`TW_*`), the `TW_OCLI_PKG` pin, `tw_die`/`tw_require`, `tw_ocli` (run ocli from `$HOME`), `tw_config_get` (read our JSON), `tw_ini_get` (read a value from ocli's INI), `tw_fetch_spec` (authenticated spec download).
- **`setup.sh`** — interactive + `--non-interactive` configuration; the only writer of `config.json` and the ocli profile(s).
- **`refresh-schema.sh`** — arg-free re-download + re-resolve of the spec(s) for the configured profile.
- **`preflight.sh`** — read-only readiness check; emits `STATUS`/`PROFILE`/`URL`/`METADATA`; warns on a cwd `.ocli` shadow. Never modifies state.

## State locations

- `~/.ocli/profiles.ini` — base URL + plaintext bearer token (mode 600), one `[section]` per profile
- `~/.ocli/current` — active profile name
- `~/.ocli/specs/<profile>.json` — ocli's resolved (inlined) spec cache
- `~/.config/twenty-cli/config.json` — our pointer: `{ profile, metadata_profile? }`

Override our dir with `TW_CONFIG_DIR=<path>` (used by tests, alongside a throwaway `$HOME` so ocli's home is a scratch dir too).
