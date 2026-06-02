# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/nobilix/twenty-crm-skill/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.2.0
[0.1.0]: https://github.com/nobilix/twenty-crm-skill/releases/tag/v0.1.0
