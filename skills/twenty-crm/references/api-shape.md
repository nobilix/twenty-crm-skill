# Twenty API shape — what's where

## Two surfaces, same data

| Surface  | ocli profile        | Base                   | Purpose                                                                           |
| -------- | ------------------- | ---------------------- | --------------------------------------------------------------------------------- |
| Core     | `<profile>` (`twenty`)   | `<url>/rest/`          | CRUD on records: People, Companies, Opportunities, Tasks, Notes, custom objects   |
| Metadata | `<profile>-meta` (opt-in) | `<url>/rest/metadata/` | Workspace schema: create/modify/delete objects, fields, views, webhooks, API keys |

Use Core for anything the user calls "data". The metadata profile is created only with `setup --with-metadata`; most schema lookups don't need it because custom objects/fields already appear in the core spec.

## Per-tenant schemas

The OpenAPI spec is **generated per workspace** — custom objects and fields appear automatically (a custom `pet` object becomes the `pets_*` commands). After adding a custom object/field, run `node scripts/twenty.mjs refresh` to re-pull and re-cache.

## Operation naming

Commands are `<path>_<method>` (full detail in `ocli-usage.md`):

```
people_post          POST   /people                 create one
people_get           GET    /people?filter=…&limit= list / search
people_id_get        GET    /people/{id}            get one
people_id_patch      PATCH  /people/{id}            update one
people_patch         PATCH  /people?filter=…        bulk update
people_id_delete     DELETE /people/{id}            delete one (soft)
people_delete        DELETE /people?filter=…        bulk delete
batch_people         POST   /batch/people           create up to 60
```

The full spec is exposed (no path filtering); every object and its `/duplicates`, `/restore`, batch, etc. paths have commands.

## Built-in objects: key fields

Look these up authoritatively in the resolved spec `~/.ocli/specs/<profile>.json`, or with `ocli <command> --help` — but here's what you'll see most often.

### Person (`people`)
- `id` (uuid), `name.firstName`, `name.lastName`, `jobTitle`
- `emails.primaryEmail`, `emails.additionalEmails[]`
- `phones.primaryPhoneNumber`, `phones.primaryPhoneCallingCode`, `phones.primaryPhoneCountryCode`
- `linkedinLink.primaryLinkUrl`, `xLink.primaryLinkUrl`
- `city`, `companyId` (FK → Company), `createdBy`
- `position` (numeric, list ordering), `createdAt`, `updatedAt`, `deletedAt`

### Company (`companies`)
- `id`, `name`, `domainName.primaryLinkUrl`, `linkedinLink.primaryLinkUrl`, `xLink.primaryLinkUrl`
- `employees` (numeric), `annualRecurringRevenue.amountMicros`, `annualRecurringRevenue.currencyCode`
- `address.addressStreet1`, `address.addressCity`, `address.addressCountry`, etc.
- `idealCustomerProfile` (boolean), `accountOwnerId` (FK → workspaceMember)
- `position`, `createdAt`, `updatedAt`, `deletedAt`

### Opportunity (`opportunities`)
- `id`, `name`, `stage` (string enum — **values are workspace-specific**; read the actual list from the spec or an existing record, e.g. `ocli opportunities_get --limit 1 | jq -r '.data.opportunities[0].stage'`. Twenty's defaults shifted between versions and admins customize them.)
- `amount.amountMicros`, `amount.currencyCode`
- `closeDate`, `pointOfContactId` (FK → Person), `companyId` (FK → Company)
- `position`, `createdAt`, `updatedAt`, `deletedAt`

### Task (`tasks`) and Note (`notes`)
- `id`, `title`, `bodyV2.markdown` (rich text), `bodyV2.blocknote` (block format)
- Task only: `dueAt` (nullable), `status` (enum: `TODO` | `IN_PROGRESS` | `DONE`), `assigneeId` (FK → workspaceMember, nullable)
- `position`, `createdAt`, `updatedAt`, `deletedAt`
- Linkage to records is via `taskTargets` / `noteTargets` (below)
- Most scalar fields are nullable in practice — when filtering "open tasks", remember DONE tasks may also have `dueAt: null` and TODO tasks may have no assignee.

### TaskTarget / NoteTarget
Polymorphic join. Exactly one `target*Id` is set; the others are NULL. **On current Twenty the fields are `target*Id`** (confirm with `ocli taskTargets_post --help`; older versions used `personId`/`companyId`):

```bash
# attach a task to a person
ocli taskTargets_post --taskId "<task-uuid>" --targetPersonId "<person-uuid>"
# attach a note to a company
ocli noteTargets_post --noteId "<note-uuid>" --targetCompanyId "<company-uuid>"
```

A single task can have many targets — that's how it spans a company + multiple people.

### WorkspaceMember (`workspaceMembers`)
- `id`, `name.firstName`, `name.lastName`, `userEmail`, `colorScheme`, `locale`, `timeZone`
- Created automatically when a user joins; not directly creatable. Use for `assigneeId`/`accountOwnerId` lookups.

## Composite fields and numbers

Composite fields are objects — pass them as a **JSON string** flag, which ocli parses (so nested numbers survive):

```bash
--name   '{"firstName":"Jane","lastName":"Doe"}'
--amount '{"amountMicros":25000000000,"currencyCode":"USD"}'   # 25,000 USD
```

**Money uses micros** (millionths): `1000` USD → `amountMicros: 1000000000`; always set `currencyCode` too.

**Top-level numeric fields can't be set via ocli.** A bare `--employees 42` is sent as the string `"42"` and Twenty rejects it (`Invalid number value`). Numbers nested inside a JSON object flag (like `amountMicros`) are fine. For a plain integer field (`employees`, `position`), omit it or set it in the UI. See `ocli-usage.md`.

## Dates and times

Twenty stores every datetime in **UTC** (ISO-8601, e.g. `2026-06-04T06:00:00.000Z`) and the web UI renders it in the **workspace member's timezone**. So a value written as `…T10:00:00Z` displays shifted by the member's offset — a frequent "why is the time wrong?" bug.

**`preflight` reports the user's `TZ` and `NOW`** (local zone + current local time) — resolve dates from there, on the fly. Nothing is persisted, so it never goes stale (travel, DST, a changed setting). `node` (required by ocli) does the conversion using the machine's zone:

```bash
# SET: user's local wall-clock → UTC for dueAt etc.  (handles DST + relative math)
node -e 'console.log(new Date("2026-06-04T10:00").toISOString())'                                           # absolute: 10:00 local
node -e 'const d=new Date(); d.setDate(d.getDate()+1); d.setHours(9,0,0,0); console.log(d.toISOString())'   # relative: tomorrow 09:00 local
# READ BACK in local time to confirm to the user (matches the UI)
node -e 'console.log(new Date("2026-06-04T06:00:00.000Z").toLocaleString("en-GB",{timeZone:Intl.DateTimeFormat().resolvedOptions().timeZone,dateStyle:"medium",timeStyle:"short"}))'
```

Include the time component: `new Date("2026-06-04")` is parsed as **UTC** midnight, but `new Date("2026-06-04T00:00")` as **local** midnight.

- **Display zone** (when the agent is *not* on the user's machine, or to match the UI exactly): the member's `timeZone`, an IANA name like `Asia/Tbilisi` — `ocli workspaceMembers_get | jq -r '.data.workspaceMembers[].timeZone'`. Convert in that zone, e.g. `new Date(iso).toLocaleString("sv",{timeZone:"<zone>"})`.
- **Filtering by range** ("due today", "created this week") needs UTC bounds — compute local-midnight → UTC:
  ```bash
  START=$(node -e 'const d=new Date(); d.setHours(0,0,0,0); console.log(d.toISOString())')
  END=$(node -e   'const d=new Date(); d.setHours(0,0,0,0); d.setDate(d.getDate()+1); console.log(d.toISOString())')
  ocli tasks_get --filter "dueAt[gte]:\"$START\",dueAt[lt]:\"$END\""
  ```
- Datetime fields include `dueAt`, `createdAt`, `updatedAt`, `deletedAt`, `closeDate`, and any custom DATE / DATE_TIME field — all UTC.

> Why not store the zone in `config.json`? A stored copy drifts (travel, DST, a changed Twenty setting), and preflight already surfaces the live value. The only thing worth persisting would be an explicit fixed-zone **override** — the "future flags" slot `config.json` leaves room for. Not added until needed.

## Soft delete

Most objects support soft delete. `<resource>_id_delete` sets `deletedAt`. To restore, PATCH it back (`<resource>_id_patch --id <uuid> --deletedAt null`) or use the object's `/restore` command if present. Filter out soft-deleted with `deletedAt[is]:NULL` (and find them with `deletedAt[is]:NOT_NULL`).

## Auth and rate limits

- Every request needs `Authorization: Bearer <token>` — ocli sends it from the profile automatically.
- ~100 requests/minute per token. Keep payloads small with `--depth 0` and `jq` projections.
- Batch create up to 60 per call via `batch_<plural>`.
