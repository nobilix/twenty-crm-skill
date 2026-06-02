# twenty-crm — an Agent Skill for Twenty CRM

An [Agent Skill](https://agentskills.io) that lets AI coding agents read and modify data in [Twenty CRM](https://twenty.com) — people, companies, opportunities, tasks, notes, and custom objects — on **any** Twenty deployment (self-hosted or `api.twenty.com`).

[![skills.sh](https://skills.sh/b/nobilix/twenty-crm-skill)](https://skills.sh/nobilix/twenty-crm-skill)

> [!NOTE]
> Built and tested against Twenty v1.15. The skill auto-downloads your workspace's OpenAPI spec at setup time, so custom objects, custom fields, and customized enums are picked up automatically.

## What this gives your agent

- **List, search, filter, create, update, delete** records via a generated CLI (built on [Restish](https://rest.sh) over Twenty's per-tenant REST API).
- **Multi-instance** — register `prod`, `staging`, a Cloud workspace, and a self-hosted one side by side; pick per command.
- **Secure credentials** — token stored in macOS Keychain, environment variable, or a `chmod 600` file; runtime `$TWENTY_API_KEY` always overrides.
- **Schema-aware** — operates on whatever your workspace looks like, including custom objects and renamed pipeline stages. The full unmodified OpenAPI spec is kept locally for the agent to consult.
- **Quiet setup contract** — preflight prints a structured `KEY=VALUE` report so the agent can either pick up an existing config or guide the user (or itself) through `--non-interactive` setup.

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

1. Install Restish (one-time):

   ```bash
   brew install danielgtaylor/restish/restish     # macOS
   go install github.com/rest-sh/restish@latest   # Linux/Go
   ```

   Or run `bash skills/twenty-crm/scripts/install-restish.sh` to do it for you.

2. Get an API key from Twenty: **Settings → APIs & Webhooks → + Create key**. Copy it immediately — it's shown once.

3. Configure your instance (interactive):

   ```bash
   bash skills/twenty-crm/scripts/setup.sh
   ```

   The script asks for an instance name, server URL, the API key, and where to store the token (Keychain / env var / file). It validates the token, downloads the OpenAPI spec, and registers two Restish APIs (`twenty-<instance>-core` and `twenty-<instance>-meta`).

4. Confirm:

   ```bash
   bash skills/twenty-crm/scripts/preflight.sh
   # STATUS=ready
   # DEFAULT=<instance>
   # INSTANCES=<instance>
   # URL_<instance>=<base-url>
   ```

5. Use it from your agent:

   ```text
   How many opportunities are in the PROPOSAL stage right now?
   Create a task "Follow up with Acme" due next Monday, attached to Sergio Cardenas.
   List the 10 most recent contacts added by Karina.
   ```

## How it works

The full operating reference lives in [`skills/twenty-crm/SKILL.md`](skills/twenty-crm/SKILL.md). Detailed references that load on demand:

- [`references/setup-guide.md`](skills/twenty-crm/references/setup-guide.md) — first-time setup: server URL, creating an API key, token storage
- [`references/filter-dsl.md`](skills/twenty-crm/references/filter-dsl.md) — filter, order-by, pagination DSL
- [`references/api-shape.md`](skills/twenty-crm/references/api-shape.md) — built-in objects, key fields, conventions (money in micros, soft delete, polymorphic targets)
- [`references/restish-usage.md`](skills/twenty-crm/references/restish-usage.md) — Restish call patterns, projection, troubleshooting
- [`references/architecture.md`](skills/twenty-crm/references/architecture.md) — why setup is wired the way it is (slim spec / schema stubbing / external-tool auth helper)

## State and locations

The skill stores all per-instance state under `$XDG_CONFIG_HOME/twenty-cli/` (default `~/.config/twenty-cli/`). Override with `TW_CONFIG_DIR=<path>`. Nothing is hardcoded; you can configure as many Twenty deployments as you like.

| File / location                                          | Purpose                                          |
| -------------------------------------------------------- | ------------------------------------------------ |
| `~/.config/twenty-cli/instances.json`                    | Instance registry (URL, token source, slim args) |
| `~/.config/twenty-cli/specs/<name>/{core,metadata}*.json` | Downloaded OpenAPI specs (full and slim)         |
| `~/.config/twenty-cli/tokens/<name>`                     | Only when `--token-from file`                    |
| macOS Keychain                                           | Only when `--token-from keychain`                |
| Restish's `apis.json`                                    | API registrations written by `setup.sh`          |

## Contributing

PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). The skill is intentionally small; the bulk of the value is in the SKILL.md operating playbook and the per-tenant OpenAPI spec it pulls from your workspace.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [Twenty](https://twenty.com) for the CRM and the per-tenant OpenAPI surface that makes this skill possible.
- [Restish](https://rest.sh) by [@danielgtaylor](https://github.com/danielgtaylor) for the HTTP CLI.
- [Anthropic](https://anthropic.com) for the [Agent Skills](https://agentskills.io) standard.
