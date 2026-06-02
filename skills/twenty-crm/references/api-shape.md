# Twenty API shape — what's where

## Two APIs, same data

Twenty exposes two REST surfaces, both registered as separate Restish APIs:

| Surface  | Restish name                | Base                  | Purpose                                                                           |
| -------- | --------------------------- | --------------------- | --------------------------------------------------------------------------------- |
| Core     | `twenty-<instance>-core`    | `<url>/rest/`         | CRUD on records: People, Companies, Opportunities, Tasks, Notes, custom objects   |
| Metadata | `twenty-<instance>-meta`    | `<url>/rest/metadata/`| Workspace schema: create/modify/delete objects, fields, views, webhooks, API keys |

Use Core for anything the user calls "data". Use Metadata to introspect or modify the schema (add a custom field, list available objects, register a webhook).

## Per-tenant schemas

The OpenAPI spec is **generated per workspace** — custom objects and fields appear automatically. After adding a custom object, run `bash scripts/refresh-schema.sh [<instance>]` to pick it up. Restish caches parsed specs as CBOR; the refresh script clears that cache.

## Operation naming (from OpenAPI → Restish kebab-case)

For each resource, the spec defines (slim defaults shown — `--full` exposes more):

```
create-one-<resource>          POST   /<plural>
delete-many-<resource>         DELETE /<plural>?filter=...   (bulk delete)
delete-one-<resource>          DELETE /<plural>/{id}
find-many-<resource>           GET    /<plural>?filter=...&limit=&order_by=...
find-one-<resource>            GET    /<plural>/{id}
update-many-<resource>         PATCH  /<plural>?filter=...   (bulk update)
update-one-<resource>          PATCH  /<plural>/{id}
```

The `<resource>` segment in the operation name is camelCase plural for `find-many` (e.g. `find-many-companies`, `find-many-people`) and singular for `create-one` / `find-one` (e.g. `create-one-company`).

## Slim default object set

Default `--objects` filter at setup time keeps just the canonical CRM model:

- `people`, `companies`, `opportunities`, `tasks`, `notes`
- `taskTargets`, `noteTargets` — join tables linking tasks/notes to records
- `workspaceMembers` — user accounts (for `assignedToId`/`createdById` lookups)

All other groups (Attachments, Blocklists, CalendarChannels, CalendarEvents, ConnectedAccounts, Dashboards, Favorites, FavoriteFolders, MessageChannels, Messages, MessageThreads, MessageParticipants, MessageFolders, TimelineActivities, Workflows, WorkflowRuns, WorkflowVersions, WorkflowAutomatedTriggers) are dropped by default but available with `bash scripts/setup.sh --full ...` or `--objects <comma-list>`.

Always-dropped (regardless of mode): `/{x}/duplicates`, `/{x}/merge` paths.

## Built-in objects: key fields

Look these up authoritatively in `~/.config/twenty-cli/specs/<instance>/core.full.json` under `components.schemas.<Object>ForResponse` — but here's what you'll see most often.

### Person (`people`)
- `id` (uuid), `name.firstName`, `name.lastName`, `jobTitle`
- `emails.primaryEmail`, `emails.additionalEmails[]`
- `phones.primaryPhoneNumber`, `phones.primaryPhoneCallingCode`, `phones.primaryPhoneCountryCode`
- `linkedinLink.primaryLinkUrl`, `xLink.primaryLinkUrl`
- `city`, `companyId` (FK → Company), `createdById`
- `position` (numeric, list ordering), `createdAt`, `updatedAt`, `deletedAt`

### Company (`companies`)
- `id`, `name`, `domainName.primaryLinkUrl`, `linkedinLink.primaryLinkUrl`, `xLink.primaryLinkUrl`
- `employees`, `annualRecurringRevenue.amountMicros`, `annualRecurringRevenue.currencyCode`
- `address.addressStreet1`, `address.addressCity`, `address.addressCountry`, etc.
- `idealCustomerProfile` (boolean), `accountOwnerId` (FK → workspaceMember)
- `position`, `createdAt`, `updatedAt`, `deletedAt`

### Opportunity (`opportunities`)
- `id`, `name`, `stage` (string enum — values are workspace-specific, look up the actual list from the spec: `jq '.components.schemas.OpportunityForResponse.properties.stage.enum' ~/.config/twenty-cli/specs/<instance>/core.full.json` — Twenty's defaults shifted between versions and admins customize them)
- `amount.amountMicros`, `amount.currencyCode`
- `closeDate`, `pointOfContactId` (FK → Person), `companyId` (FK → Company)
- `position`, `createdAt`, `updatedAt`, `deletedAt`

### Task (`tasks`) and Note (`notes`)
- `id`, `title`, `bodyV2.markdown` (rich text), `bodyV2.blocknote` (block format)
- Task only: `dueAt` (nullable), `status` (enum: `TODO` | `IN_PROGRESS` | `DONE`), `assigneeId` (FK → workspaceMember, nullable)
- `position`, `createdAt`, `updatedAt`, `deletedAt`
- Linkage to records is via `taskTargets` / `noteTargets` (see below)
- Most scalar fields on most objects are nullable in practice — when filtering "open tasks", users often forget that DONE tasks may also have `dueAt: null` and TODO tasks may have no assignee. Don't assume non-null without checking.

### TaskTarget / NoteTarget
Polymorphic join. `personId` OR `companyId` OR `opportunityId` (etc.) is set; the other FKs are NULL. To attach a task to a person:

```
POST /taskTargets   { "taskId": "<task-uuid>", "personId": "<person-uuid>" }
```

A single task can have many targets — that's how it spans a company + multiple people.

### WorkspaceMember (`workspaceMembers`)
- `id`, `name.firstName`, `name.lastName`, `userEmail`
- `colorScheme`, `locale`, `timeZone`
- Created automatically when a user joins; not directly creatable.

## Money values

All currency amounts use **micros** (millionths of the unit). `1000` USD = `amount.amountMicros: 1000000000`, `currencyCode: "USD"`. Always set both.

## Soft delete

Most objects support soft delete. `delete-one-<resource>` sets `deletedAt`. The slim spec drops `/restore/*` paths — re-run setup with `--keep-restore` to expose them, or PATCH `deletedAt: null` directly via `update-one-*`.

## Auth and rate limits

- All requests need `Authorization: Bearer <token>` — handled transparently by `scripts/auth-helper.sh` (called by Restish per request).
- 100 requests/minute per token.
- Batch endpoints (POST /batch/<plural>) up to 60 per call — opt in with `--keep-batch` at setup time.
