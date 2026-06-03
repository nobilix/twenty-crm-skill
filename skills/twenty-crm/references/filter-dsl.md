# Twenty REST filter, ordering, and pagination DSL

This is the query DSL used in the `--filter`, `--order_by`, `--limit`, `--starting_after`, `--ending_before`, and `--depth` flags on every list (`<resource>_get`) command. The syntax is identical for all objects; what changes is the field names available on each object (look those up in the resolved spec at `~/.ocli/specs/<profile>.json`, via `ocli <resource>_get --help`, or the metadata profile).

## Filtering

Format: `field[COMPARATOR]:value`

Multiple conditions joined by comma are AND-ed at the root:

```
filter=status[eq]:"open",createdAt[gte]:"2024-01-01"
```

### Comparators

| Comparator     | Meaning                                | Example                                  |
| -------------- | -------------------------------------- | ---------------------------------------- |
| `eq`           | equals                                 | `status[eq]:"open"`                      |
| `neq`          | not equals                             | `status[neq]:"closed"`                   |
| `in`           | in list                                | `id[in]:["id-1","id-2"]`                 |
| `containsAny`  | array/multi-select contains any        | `tags[containsAny]:["sales","priority"]` |
| `is`           | NULL / NOT_NULL / true / false         | `deletedAt[is]:NULL`                     |
| `gt` `gte`     | greater (or equal) than                | `amount.amountMicros[gte]:100000000`     |
| `lt` `lte`     | less (or equal) than                   | `closeDate[lte]:"2026-12-31"`            |
| `startsWith`   | string starts with                     | `name.firstName[startsWith]:"Jo"`        |
| `like` `ilike` | SQL LIKE (case-sensitive / -insensit.) | `name[ilike]:"%inc%"`                    |

### Composite fields

Use dot notation: `field.subField[COMPARATOR]:value`. Twenty has many composite fields:

- `name.firstName`, `name.lastName` (Person)
- `emails.primaryEmail`, `phones.primaryPhoneNumber` (Person, Company)
- `domainName.primaryLinkUrl`, `linkedinLink.primaryLinkUrl` (Company)
- `amount.amountMicros`, `amount.currencyCode` (Opportunity)
- `address.addressCity`, `address.addressCountry` (Company, Person)

### Boolean composition

Beyond root-AND, explicit operators wrap conditions:

```
filter=or(status[eq]:"open",assigneeId[is]:NULL)
filter=and(status[eq]:"open",or(priority[eq]:"high",dueAt[lte]:"2026-05-10"))
filter=not(status[eq]:"archived")            # not wraps exactly one condition
```

### Value formatting

- Strings and ISO dates: **must be quoted** — `"foo"`, `"2024-01-01"`
- Numbers: **unquoted** — `100`, `0.5`
- Booleans: **unquoted** — `true`, `false`
- NULL/NOT_NULL with `is`: **unquoted** — `NULL`, `NOT_NULL`
- Lists for `in`/`containsAny`: `["a","b","c"]`
- **Dates/times are UTC.** Twenty stores and filters in UTC; convert the user's local time first (`preflight` reports their `TZ` / `NOW`). For ranges, compute UTC bounds with `node` — see `api-shape.md` → "Dates and times".

## Ordering

Format: `order_by=field1,field2[DIRECTION]`

Directions: `AscNullsFirst` (default), `AscNullsLast`, `DescNullsFirst`, `DescNullsLast`.

```
order_by=createdAt
order_by=name.lastName,createdAt[DescNullsLast]
order_by=amount.amountMicros[DescNullsLast]
```

## Pagination

Cursor-based; `limit` defaults to 60, max 200 (the prose in `info.description` says 60 — stale; actual schema enforces 200).

```
# First page
GET /people?limit=60

# Next page
GET /people?limit=60&starting_after=<endCursorFromPreviousPage>

# Previous page
GET /people?limit=60&ending_before=<startCursorFromCurrentPage>
```

Response includes `pageInfo: { hasNextPage, hasPreviousPage, startCursor, endCursor }` plus top-level `totalCount`. Loop manually: while `hasNextPage` is true, pass the previous page's `endCursor` as `--starting_after`.

## Depth (relation expansion)

`depth` query parameter (enum: `0` or `1`, default `1`) controls relation expansion:

- `0` — primary object only; relations represented by their FK ids (`companyId`, `assigneeId`, …)
- `1` (default) — one level of related objects inlined (e.g. `Person.company` is a full Company object, not just `companyId`)

Use `depth=0` when listing many records to keep payloads small and stay under rate limits.

## Rate limits and batching

- ~100 requests per minute per token
- Batch create up to 60 records per call via the `batch_<plural>` command.

## ocli flag mapping

The flag name is the query parameter's spec name (snake_case), passed verbatim:

| HTTP query param      | ocli flag                  |
| --------------------- | -------------------------- |
| `?limit=60`           | `--limit 60`               |
| `?filter=...`         | `--filter '...'`           |
| `?order_by=...`       | `--order_by '...'`         |
| `?depth=0`            | `--depth 0`                |
| `?starting_after=...` | `--starting_after '...'`   |
| `?ending_before=...`  | `--ending_before '...'`    |

A plain-string `--filter 'stage[eq]:"X"'` is URL-encoded into the query verbatim. Use `ocli <resource>_get --help` to see exactly which flags a command exposes.
