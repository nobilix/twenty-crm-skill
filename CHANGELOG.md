# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.4] — 2026-06-02

### Changed

- Interactive `setup.sh` now picks the token-storage default by OS: macOS keeps Keychain as the recommended default; Linux/WSL defaults to the `chmod 600` file and no longer offers Keychain (it's macOS-only). Previously the default was always Keychain, so on Linux/WSL pressing Enter led straight to a "keychain only on macOS" dead end.

## [0.2.3] — 2026-06-02

### Security

- `auth-helper.sh` now carries a header warning that it prints the bearer token to stdout (by design, for restish); `references/restish-usage.md` documents not running it by hand — or `restish -v` — in a logged/shared session, and to rotate the key if a token leaks.

### Added

- `references/restish-usage.md` "Access and secrets" note for sandboxed/restricted agents (e.g. Codex): restish needs token-store read and cache-dir write access; symptoms and workarounds documented.

## [0.2.2] — 2026-06-02

### Fixed

- Metadata API examples in SKILL.md were incorrect. Verified against a live workspace and corrected: commands are `get-rest-metadata-objects` / `get-rest-metadata-fields` (the metadata spec has no `find-many-*` operationIds); metadata endpoints reject `--limit` and `--filter` query params; responses carry `body.data.{objects,fields}` + `pageInfo` but no `totalCount`; and `restish -f` is not jq, so the previous `(fields | length)` projection silently returned null. Replaced with tested examples that slice/filter client-side via jq.

## [0.2.1] — 2026-06-02

### Fixed

- Cloud record links pointed at the API host (`https://api.twenty.com/objects/...`), which serves no UI. Setup now expects the URL you open Twenty at — your workspace subdomain (`https://your-workspace.twenty.com`) on cloud — which serves both the REST API and working record links. One URL format now applies to cloud and self-hosted alike; prompts and docs updated accordingly.
- `setup.sh` now clears Restish's parsed-spec (CBOR) cache when (re)registering an instance, so changing an instance's URL takes effect immediately instead of failing against a stale cached spec.

## [0.2.0] — 2026-06-02

### Added

- `references/setup-guide.md` — step-by-step first-time setup: finding the server URL (cloud vs self-hosted), creating an API key, and choosing token storage, with a security note on running setup in your own terminal.

### Changed

- `preflight.sh` not-ready report now lists the three things setup needs (URL, API key, token storage) and links to `setup-guide.md`.
- `setup.sh` URL prompt shows both cloud and self-hosted examples; completion message suggests natural-language agent queries instead of raw `restish` commands.
- SKILL.md: `not_ready` is treated as non-sticky — the agent re-runs preflight on the next CRM request in case the user just completed setup in their terminal.

## [0.1.0] — 2026-05-12

### Added

- Initial release as a standalone Agent Skill.
- Restish-based CLI generation from Twenty's per-tenant OpenAPI spec (core + metadata).
- Mandatory schema-stubbing (`{"type":"object"}`) to break circular `$ref` cycles that hang Restish's parser.
- Three token sources — macOS Keychain, env var, `chmod 600` file — with runtime `$TWENTY_API_KEY` override.
- Two-path setup: interactive (`bash setup.sh`) and agent-friendly (`--non-interactive` with flags).
- `auth-helper.sh` as a Restish `external-tool` auth provider, so the bearer token is never written into `apis.json`.
- Structured `preflight.sh` output (`KEY=VALUE`) so agents can detect missing config and surface a guided setup report.
- `refresh-schema.sh` that respects each instance's persisted slim configuration.
- References: `filter-dsl.md`, `api-shape.md`, `restish-usage.md`, `architecture.md`.

[Unreleased]: https://github.com/nobilix/twenty-crm-skill/compare/v0.2.4...HEAD
[0.2.4]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.4
[0.2.3]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.3
[0.2.2]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.2
[0.2.1]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.1
[0.2.0]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.0
[0.1.0]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.1.0
