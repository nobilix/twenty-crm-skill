# twenty-crm — an Agent Skill for Twenty CRM

An [Agent Skill](https://agentskills.io) that lets AI coding agents read and modify data in [Twenty CRM](https://twenty.com) — people, companies, opportunities, tasks, notes, and custom objects — on **any** Twenty deployment (self-hosted or Twenty Cloud).

[![skills.sh](https://skills.sh/b/nobilix/twenty-crm-skill)](https://skills.sh/nobilix/twenty-crm-skill)

> [!NOTE]
> The skill auto-downloads your workspace's OpenAPI spec at setup time, so custom objects, custom fields, and customized enums are picked up automatically. Verified end-to-end against a live Twenty Cloud workspace.

## What this gives your agent

- **List, search, filter, create, update, delete** records via a CLI generated from your workspace's per-tenant REST API by [`ocli`](https://github.com/EvilFreelancer/openapi-to-cli).
- **Schema-aware** — operates on whatever your workspace looks like, including custom objects and renamed pipeline stages. The full resolved OpenAPI spec is cached locally for the agent to consult.
- **One CRM by default** — a single ocli profile, no instance prefixes. Got more than one? Copy the skill or add another ocli profile (see below).
- **Quiet setup contract** — preflight prints a structured `KEY=VALUE` report so the agent can pick up an existing config or guide the user (or itself) through `--non-interactive` setup.

## Compatible agents

Works with any client that follows the [Agent Skills standard](https://agentskills.io) — Claude Code, Cursor, OpenAI Codex, VS Code Copilot, Goose, OpenCode, and [many more](https://agentskills.io#clients).

## Install

### `skills.sh` (any compatible agent)

```bash
npx skills add nobilix/twenty-crm-skill
```

### Claude Code (plugin marketplace)

```text
/plugin marketplace add nobilix/twenty-crm-skill
/plugin install twenty-crm@twenty-crm-skill
```

### Manual

Copy `skills/twenty-crm/` into one of your client's skill directories:

- Claude Code: `~/.claude/skills/twenty-crm/` (personal) or `.claude/skills/twenty-crm/` (project)
- VS Code: `.agents/skills/twenty-crm/`
- Cursor, Codex, etc.: see your client's docs

## Quick start

1. Install prerequisites (one-time): Node.js ≥18, `ocli`, `jq`.

   ```bash
   npm i -g openapi-to-cli@0.1.15     # the CLI generator (pinned)
   ```

2. Get an API key from Twenty: **Settings → APIs & Webhooks → + Create key**. Copy it immediately — it's shown once.

3. Configure your instance (interactive):

   ```bash
   node skills/twenty-crm/scripts/twenty.mjs setup
   ```

   It asks for the server URL and the API key, validates the key, downloads the OpenAPI spec, and creates an ocli profile (default name `twenty`).

4. Confirm:

   ```bash
   node skills/twenty-crm/scripts/twenty.mjs preflight
   # STATUS=ready
   # PROFILE=twenty
   # URL=<base-url>
   ```

5. Use it from your agent:

   ```text
   How many opportunities are in the PROPOSAL stage right now?
   Create a task "Follow up with Acme" due next Monday, attached to Sergio Cardenas.
   List the 10 most recent contacts added by Karina.
   ```

## How it works

The full operating reference lives in [`skills/twenty-crm/SKILL.md`](skills/twenty-crm/SKILL.md). Detailed references that load on demand:

- [`references/setup-guide.md`](skills/twenty-crm/references/setup-guide.md) — first-time setup: prerequisites, server URL, creating an API key
- [`references/filter-dsl.md`](skills/twenty-crm/references/filter-dsl.md) — filter, order-by, pagination DSL
- [`references/api-shape.md`](skills/twenty-crm/references/api-shape.md) — built-in objects, key fields, conventions (money in micros, soft delete, polymorphic targets)
- [`references/ocli-usage.md`](skills/twenty-crm/references/ocli-usage.md) — ocli call patterns, command naming, output→jq, troubleshooting
- [`references/architecture.md`](skills/twenty-crm/references/architecture.md) — why setup is wired the way it is (the `twenty.mjs` CLI, ocli profiles, the `~/.ocli` vs `config.json` split, the run-from-`$HOME` rule)

## State and locations

| File / location                          | Purpose                                                        |
| ---------------------------------------- | -------------------------------------------------------------- |
| `~/.ocli/profiles.ini`                   | ocli profile: base URL + **plaintext** bearer token (mode 600) |
| `~/.ocli/current`                        | ocli's active profile                                          |
| `~/.ocli/specs/<profile>.json`           | ocli's resolved (inlined) spec cache                           |
| `~/.config/twenty-cli/config.json`       | the skill's pointer: the ocli profile name(s)                  |

`~/.ocli` is ocli's standard home, shared by any ocli-based tool; the skill uses a distinctively named profile (default `twenty`) to coexist. Override the skill's own dir with `TW_CONFIG_DIR=<path>`.

### More than one Twenty?

The default is a single CRM. To work with several, either copy the skill directory, or add another ocli profile manually (`ocli profiles add <other> --api-base-url <url>/rest --openapi-spec <file> --api-bearer-token <key>`) and switch with `ocli use <name>`.

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The skill is intentionally small; the bulk of the value is in the SKILL.md operating playbook and the per-tenant OpenAPI spec it pulls from your workspace.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [Twenty](https://twenty.com) for the CRM and the per-tenant OpenAPI surface that makes this skill possible.
- [`ocli` / openapi-to-cli](https://github.com/EvilFreelancer/openapi-to-cli) by [@EvilFreelancer](https://github.com/EvilFreelancer) for generating the CLI from the spec.
- [Anthropic](https://anthropic.com) for the [Agent Skills](https://agentskills.io) standard.
