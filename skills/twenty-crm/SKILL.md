---
name: twenty-crm
description: Read and modify Twenty CRM data — people, companies, opportunities, tasks, notes, custom objects — on any Twenty deployment (self-hosted or cloud). Includes a one-time setup that registers the instance and stores credentials securely. Use when the user wants to look up, search, filter, count, create, update, or delete CRM records; review their pipeline or contacts; bulk-edit via filter; introspect or change the workspace schema (objects, fields, webhooks); or set up CLI access to a Twenty instance. Triggers on "twenty", "the CRM", a `crm.*` URL, or mentions of people/companies/opportunities/deals/leads/pipeline in a CRM context.
license: MIT
compatibility: macOS or Linux. Requires restish (https://rest.sh), jq, and curl. Optional macOS Keychain for token storage. Bash 3.2+.
metadata:
  version: "0.2.2"
---

# Twenty CRM

Reusable across any Twenty deployment. Per-instance config lives in `~/.config/twenty-cli/`; nothing is hardcoded.

## Step 0: preflight (always)

```bash
bash scripts/preflight.sh
```

- `STATUS=ready` → proceed. Output also lists `DEFAULT=`, `INSTANCES=`, and one `URL_<name>=<base-url>` per instance — use these to build UI links.
- non-zero exit → not configured. Stderr prints the three things setup needs (URL, API key, token storage) and the two setup paths below; pick by context. For the full walkthrough (where to get the URL and how to create the API key), load `references/setup-guide.md`.

**`not_ready` is not sticky.** Setup happens in the user's own terminal, so a config that didn't exist this turn may exist the next. If you reported `not_ready` and the user comes back with any CRM request, **re-run preflight first** — assume they may have just completed setup, don't repeat the "not configured" message from memory.

## Setup

Idempotent — re-running updates an existing instance. New here? `references/setup-guide.md` has the full step-by-step (where the URL comes from, how to create the API key, token-storage trade-offs).

To configure, you need: instance name (lowercase, e.g. `myco`), the URL you open Twenty at — self-hosted `https://crm.your-company.com` or cloud `https://your-workspace.twenty.com` (the workspace subdomain, **not** `api.twenty.com` — that host has no UI, so record links break); setup appends `/rest`. Plus an API key from **Settings → APIs & Webhooks → + Create key**, and one of three token storage modes — `keychain` (macOS, default account `twenty-<name>` / service `api`), `env` (var `TWENTY_<NAME>_KEY`), or `file` (`~/.config/twenty-cli/tokens/<name>`, mode 600). At runtime, `$TWENTY_API_KEY` overrides everything.

### Path A — user-driven (preferred when an API key is involved)

Keeps the key out of chat. Tell the user:

```
bash <skill-path>/scripts/setup.sh
```

### Path B — agent-driven (only when the user asked you to handle it)

```
bash <skill-path>/scripts/setup.sh --non-interactive \
  --name <name> --url <url> --token-from {keychain|env|file} --token <key>
```

For source-specific overrides and slim/full options, see `setup.sh --help`. After setup, run preflight to confirm `STATUS=ready`.

## Operating on data

Restish exposes two registered APIs per instance:

- `twenty-<instance>-core` — records (people, companies, opportunities, tasks, notes, taskTargets, noteTargets, workspaceMembers; default slim set)
- `twenty-<instance>-meta` — workspace schema (objects, fields, views, webhooks, API keys)

Discover what's available:

```bash
restish twenty-<instance>-core --help                      # operations grouped by resource
restish twenty-<instance>-core find-many-people --help     # one operation's flags
```

Authoritative field schemas (request and response shapes) live in `~/.config/twenty-cli/specs/<instance>/core.full.json` — read directly when you need exact field names, types, or enum values. The slim spec used by Restish has stubbed schemas, which is required to break circular `$ref` cycles that hang Restish's parser; operation paths and parameters are intact.

### Common operations

Substitute `<instance>` with the name from `preflight.sh` output. Records are wrapped in `body.data.<plural>`; top-level `body.totalCount` and `body.pageInfo` are always present.

**Count:**
```bash
restish twenty-<instance>-core find-many-people --limit 1 -f body.totalCount -r
restish twenty-<instance>-core find-many-opportunities --filter 'stage[eq]:"PROPOSAL"' --limit 1 -f body.totalCount -r
```

**List & search:**
```bash
restish twenty-<instance>-core find-many-companies --limit 10 \
  --order-by 'createdAt[DescNullsLast]' \
  -f 'body.data.companies[].{name, domain: domainName.primaryLinkUrl, employees}'

restish twenty-<instance>-core find-many-people \
  --filter 'emails.primaryEmail[ilike]:"%@acme.com"' \
  -f 'body.data.people[].{name, email: emails.primaryEmail, company: companyId}'

restish twenty-<instance>-core find-many-opportunities \
  --filter 'stage[neq]:"WON",amount.amountMicros[gte]:10000000000' \
  --order-by 'closeDate' \
  -f 'body.data.opportunities[].{name, stage, amount: amount.amountMicros, closeDate}'
```

**Get one:**
```bash
restish twenty-<instance>-core find-one-person <uuid>
restish twenty-<instance>-core find-one-company <uuid> --depth 0     # skip relation expansion
```

**Create** (money fields use **micros** — 25 000 USD = `25000000000`):
```bash
restish twenty-<instance>-core create-one-company \
  '{"name":"Acme Inc","domainName":{"primaryLinkUrl":"acme.com"},"employees":50}'

restish twenty-<instance>-core create-one-opportunity \
  '{"name":"Acme expansion","stage":"PROPOSAL","amount":{"amountMicros":25000000000,"currencyCode":"USD"},"companyId":"<uuid>"}'
```

**Update / bulk update:**
```bash
restish twenty-<instance>-core update-one-opportunity <uuid> '{"stage":"WON"}'

restish twenty-<instance>-core update-many-companies \
  --filter 'idealCustomerProfile[eq]:true' \
  '{"accountOwnerId":"<workspace-member-uuid>"}'
```

**Delete** (soft — sets `deletedAt`):
```bash
restish twenty-<instance>-core delete-one-task <uuid>
```

**Link tasks/notes to records** (polymorphic — one join per attachment):
```bash
TASK_ID=$(restish twenty-<instance>-core create-one-task \
  '{"title":"Follow up","status":"TODO","dueAt":"2026-05-15T00:00:00Z"}' \
  -f 'body.data.createTask.id' -r)

restish twenty-<instance>-core create-one-task-target '{"taskId":"'$TASK_ID'","personId":"<uuid>"}'
restish twenty-<instance>-core create-one-task-target '{"taskId":"'$TASK_ID'","companyId":"<uuid>"}'
```

**Metadata (introspect schema, including custom objects):**

The metadata API differs from core: commands are named `get-rest-metadata-<resource>` (no `find-many-*` aliases — confirm with `restish twenty-<instance>-meta --help`), the endpoints take **no query params** (`--limit` / `--filter` are rejected), and responses carry `body.data.{objects,fields}` + `body.pageInfo` but **no** `body.totalCount`. Fetch the full set and slice client-side. Each object embeds its own `fields[]`.

```bash
# List objects (flat projection works with restish -f)
restish twenty-<instance>-meta get-rest-metadata-objects \
  -f 'body.data.objects[].{name: nameSingular, custom: isCustom}'

# Anything computed or filtered (field counts, a single object's fields):
# restish -f is not jq — pipe to jq, starting at .data (the raw body).
restish twenty-<instance>-meta get-rest-metadata-objects \
  | jq '.data.objects[] | {name: .nameSingular, fields: (.fields | length)}'

restish twenty-<instance>-meta get-rest-metadata-objects \
  | jq -r '.data.objects[] | select(.nameSingular=="company") | .fields[] | {name, type, label}'
```

### Always link back to the UI

When you create or update a record, or surface a single record by id, append the UI URL so the user can click through:

```
<base-url>/object/<nameSingular>/<id>     # single record  (e.g. /object/note/<id>, /object/company/<id>)
<base-url>/objects/<namePlural>           # list/board     (e.g. /objects/companies)
```

Use the `URL_<instance>=` line from preflight as the base — never reconstruct it. Built-in `nameSingular` values: `person`, `company`, `opportunity`, `task`, `note`. For custom objects, look up `nameSingular` via the metadata API. For taskTargets/noteTargets, link to the parent (person/company/opportunity), not the join.

### When to load reference files

| Need                                                             | Load                            |
| ---------------------------------------------------------------- | ------------------------------- |
| First-time setup: find the URL, create an API key, store a token | `references/setup-guide.md`     |
| Constructing a `--filter` / `--order-by` / pagination cursor     | `references/filter-dsl.md`      |
| Field names on built-in objects, money/soft-delete conventions   | `references/api-shape.md`       |
| Restish shorthand, output formats, troubleshooting (401/hang/…)  | `references/restish-usage.md`   |
| How setup is wired (slim spec, auth helper, file roles, why)     | `references/architecture.md`    |

## After a Twenty upgrade or schema change

```bash
bash scripts/refresh-schema.sh [<instance>]    # default: configured default
```

Re-downloads core + metadata specs and clears Restish's CBOR cache. Run after Twenty version bumps or when the user adds/changes a custom object or field.

## State

All persistent state lives in `~/.config/twenty-cli/` (override with `TW_CONFIG_DIR`): `instances.json`, `specs/<instance>/`, optional `tokens/<instance>`. Restish's own config (`apis.json`) and CBOR cache live in the standard OS locations and are written by `setup.sh` / cleared by `refresh-schema.sh`.
