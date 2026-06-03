---
name: twenty-crm
description: Read and modify Twenty CRM data — people, companies, opportunities, tasks, notes, custom objects — on any Twenty deployment (self-hosted or cloud). Includes a one-time setup that connects the instance and stores the API token. Use when the user wants to look up, search, filter, count, create, update, or delete CRM records; review their pipeline or contacts; bulk-edit via filter; introspect or change the workspace schema (objects, fields, webhooks); or set up CLI access to a Twenty instance. Triggers on "twenty", "the CRM", a `crm.*` URL, or mentions of people/companies/opportunities/deals/leads/pipeline in a CRM context.
license: MIT
compatibility: macOS or Linux. Requires Node.js ≥18, ocli (openapi-to-cli), and jq.
metadata:
  version: "0.3.0"
---

# Twenty CRM

Reusable across any Twenty deployment. The skill drives [`ocli`](https://github.com/EvilFreelancer/openapi-to-cli) — a CLI generated from your workspace's OpenAPI spec. Per-instance state is an ocli profile under `~/.ocli/`; the skill keeps only a one-line pointer in `~/.config/twenty-cli/config.json`. Nothing is hardcoded.

## Step 0: preflight (always)

```bash
node scripts/twenty.mjs preflight
```

- `STATUS=ready` → proceed. Output also gives `PROFILE=<name>` (the ocli profile, usually `twenty`), `URL=<base-url>` (use it to build UI links), and `METADATA=<name>` if the metadata profile was set up.
- non-zero exit → not configured. Stderr prints the two things setup needs (URL, API key) and the two setup paths below; pick by context. For the full walkthrough load `references/setup-guide.md`.

**`not_ready` is not sticky.** Setup happens in the user's own terminal, so a config that didn't exist this turn may exist the next. If you reported `not_ready` and the user comes back with any CRM request, **re-run preflight first** — don't repeat the "not configured" message from memory.

## Setup

Idempotent — re-running updates the existing profile. New here? `references/setup-guide.md` has the full step-by-step (where the URL comes from, how to create the API key).

You need: the URL you open Twenty at — self-hosted `https://crm.your-company.com` or cloud `https://your-workspace.twenty.com` (the workspace subdomain, **not** `api.twenty.com` — that host has no UI, so record links break); setup appends `/rest`. Plus an API key from **Settings → APIs & Webhooks → + Create key**.

**Recommend the user run setup in their own terminal** — the API key is typed as hidden input, so it never lands in the chat transcript. Tell them why, and give them:

```
node <skill-path>/scripts/twenty.mjs setup
```

That's the safe default. Only if the user *themselves* puts the URL + key in chat (or explicitly asks you to run it) use the non-interactive form:

```
node <skill-path>/scripts/twenty.mjs setup --non-interactive --url <url> --token <key>
```

Add `--with-metadata` to also create the schema-admin profile (rarely needed; see Metadata below). After setup, run preflight to confirm `STATUS=ready`.

## Operating on data

One ocli profile is active (its name is `PROFILE=` from preflight, usually `twenty`). You call commands **bare** — `ocli <command> [--flags]` — and ocli prints the **raw JSON response body**, which you pipe to `jq`.

**Command names are `<path>_<method>`** (the `{id}` path segment becomes `_id`). There is no per-resource alias — construct names from the convention:

| Operation | Command |
| --- | --- |
| list / search | `people_get`, `companies_get`, `opportunities_get` … |
| get one | `people_id_get --id <uuid>` |
| create | `people_post --<field> …` |
| update one | `people_id_patch --id <uuid> --<field> …` |
| update many (by filter) | `people_patch --filter … --<field> …` |
| delete one (soft) | `tasks_id_delete --id <uuid>` |

Discover what's available:

```bash
ocli commands                 # every command (long — prefer constructing the name)
ocli people_post --help       # one command's flags (request-body fields included)
```

Exact field names, types, and enum values live in the resolved spec at `~/.ocli/specs/<PROFILE>.json` — read it directly when you need them (e.g. `jq '.paths["/opportunities"].post...' ~/.ocli/specs/twenty.json`), or just use `--help`.

> If a command errors that the profile is wrong / "No current profile configured" (another ocli tool changed the active profile), run `ocli use <PROFILE>` (the name from preflight) and retry.

### Response shape

A list (`<plural>_get`) returns `{ "data": { "<plural>": [...] }, "pageInfo": {...}, "totalCount": N }`. Get/create/update/delete wrap the record under a verb key: `data.person`, `data.createCompany`, `data.updateOpportunity`, `data.deleteTask`, and bulk update under `data.update<Plural>`.

### Common operations

```bash
# COUNT
ocli people_get --limit 1 | jq '.totalCount'
ocli opportunities_get --filter 'stage[eq]:"SCREENING"' --limit 1 | jq '.totalCount'

# LIST + ORDER + PROJECT
ocli companies_get --limit 10 --order_by 'createdAt[DescNullsLast]' \
  | jq '.data.companies[] | {name, domain: .domainName.primaryLinkUrl}'

# FILTER (composite/nested fields use dot paths; see references/filter-dsl.md)
ocli people_get --filter 'emails.primaryEmail[ilike]:"%@acme.com"' \
  | jq '.data.people[] | {name: .name.firstName, email: .emails.primaryEmail, companyId}'

# GET ONE
ocli people_id_get --id <uuid> --depth 0 | jq '.data.person'   # depth 0 = no relation expansion
```

**Create / update — per-field flags.** Scalars take plain values; **nested/composite fields take a JSON string**; booleans use `true`/`false`:

```bash
# nested name/emails are JSON; jobTitle is a plain scalar
ocli people_post --name '{"firstName":"Jane","lastName":"Doe"}' \
  --jobTitle 'CEO' --emails '{"primaryEmail":"jane@acme.com"}' \
  | jq '.data.createPerson.id'

# money lives inside a JSON object → its numbers are preserved
ocli opportunities_post --name 'Acme expansion' --stage PROPOSAL \
  --amount '{"amountMicros":25000000000,"currencyCode":"USD"}' --companyId '<uuid>' \
  | jq '.data.createOpportunity.id'

ocli companies_post --name 'Acme Inc' --domainName '{"primaryLinkUrl":"acme.com"}' --idealCustomerProfile true

# update one / many
ocli opportunities_id_patch --id <uuid> --stage WON
ocli companies_patch --filter 'idealCustomerProfile[eq]:true' --accountOwnerId '<member-uuid>'

# delete (soft — sets deletedAt)
ocli tasks_id_delete --id <uuid>
```

> **Numeric limitation:** ocli sends a bare numeric flag as a *string*, which Twenty rejects (`Invalid number value`). Numbers **nested inside a JSON object flag** (like `amountMicros` above) are fine. A top-level integer field such as `employees` or `position` can't be set via ocli — omit it, or tell the user to set it in the UI. See `references/api-shape.md`.

### Dates & times

Twenty stores datetimes in **UTC**; the UI shows them in the user's timezone — so a naive `…T10:00:00Z` lands shifted. Preflight reports the user's `TZ=` and `NOW=`. **When the user gives a wall-clock time ("10am", "tomorrow 9:00"), read it in their timezone and convert to UTC before sending.** `node` does it (uses the machine's zone, DST-aware):

```bash
node -e 'console.log(new Date("2026-06-04T10:00").toISOString())'   # 10:00 local → 2026-06-04T06:00:00.000Z in UTC+4
```

Use that as `--dueAt` (include the time — a bare date parses as UTC midnight). Confirm the time back in local terms. Ranges and remote-agent details: `references/api-shape.md`.

**Link tasks/notes to records** (polymorphic join — one row per attachment; fields are `target*Id`):

```bash
TASK_ID=$(ocli tasks_post --title 'Follow up' --status TODO | jq -r '.data.createTask.id')
ocli taskTargets_post --taskId "$TASK_ID" --targetPersonId  '<person-uuid>'
ocli taskTargets_post --taskId "$TASK_ID" --targetCompanyId '<company-uuid>'
```

Confirm the exact link field names with `ocli taskTargets_post --help` (older Twenty versions used `personId`/`companyId`).

### Metadata (introspect/modify schema — opt-in)

Only if setup ran with `--with-metadata` (preflight shows `METADATA=`). The metadata profile is separate, so toggle the active profile around it:

```bash
ocli use <METADATA>        # e.g. ocli use twenty-meta
ocli objects_get | jq -r '.data[] | select(.nameSingular=="company") | .fields[] | {name, type, label}'
ocli use <PROFILE>         # switch back to core, e.g. ocli use twenty
```

Metadata `objects_get` returns `.data` as a **flat array** of objects (each with an embedded `fields[]`), plus `totalCount`/`pageInfo`. (Custom objects and fields also surface automatically in the **core** spec — e.g. a custom `pet` object becomes `pets_get` — so most schema lookups don't need the metadata profile at all.)

### Always link back to the UI

When you create/update a record, or surface a single record by id, append the UI URL so the user can click through:

```
<base-url>/object/<nameSingular>/<id>     # single record  (e.g. /object/company/<id>)
<base-url>/objects/<namePlural>           # list/board     (e.g. /objects/companies)
```

Use the `URL=` line from preflight as the base — never reconstruct it. Built-in `nameSingular`: `person`, `company`, `opportunity`, `task`, `note`. For task/note targets, link to the parent record (person/company/opportunity), not the join row.

### When to load reference files

| Need                                                             | Load                          |
| ---------------------------------------------------------------- | ----------------------------- |
| First-time setup: find the URL, create an API key               | `references/setup-guide.md`   |
| Constructing a `--filter` / `--order_by` / pagination cursor     | `references/filter-dsl.md`    |
| Field names on built-in objects, money/soft-delete conventions   | `references/api-shape.md`     |
| ocli call patterns, output→jq, troubleshooting (401, profile, …) | `references/ocli-usage.md`    |
| How setup is wired (ocli profiles, the config split, why)        | `references/architecture.md`  |

## After a Twenty upgrade or schema change

```bash
node scripts/twenty.mjs refresh
```

Re-downloads the spec and refreshes ocli's resolved-spec cache. Run after Twenty version bumps or when the user adds/changes a custom object or field.

## State

- `~/.ocli/` — ocli's own config (owned by ocli): `profiles.ini` (base URL + **plaintext** bearer token, hardened to `600`), `current` (active profile), `specs/<profile>.json` (resolved spec cache). Shared by any ocli tool on the machine; our profile is named distinctively (default `twenty`) to avoid collisions.
- `~/.config/twenty-cli/config.json` — our only state: the profile name(s). Override the dir with `TW_CONFIG_DIR`.
