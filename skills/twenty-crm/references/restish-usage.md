# Restish patterns for Twenty

Restish (https://rest.sh) is the underlying HTTP client. The Twenty skill registers two APIs per instance: `twenty-<instance>-core` and `twenty-<instance>-meta`. Auth is injected automatically via `scripts/auth-helper.sh`.

## Anatomy of a call

```
restish twenty-myco-core <operation-id> [<positional args>] [--flag value] [body-json]
        └────┬────────┘ └─────┬──────┘ └──────┬───────┘ └──────┬─────┘ └────┬────┘
        registered API   from spec        path params       options    request body
```

`operation-id` is the camelCase OpenAPI `operationId` rendered as kebab-case (e.g. `findManyPeople` → `find-many-people`).

## Listing

```bash
# Basic list (default limit 60)
restish twenty-myco-core find-many-people

# With filter and ordering, projecting only what you need
restish twenty-myco-core find-many-people \
  --filter 'jobTitle[ilike]:"%founder%"' \
  --order-by 'createdAt[DescNullsLast]' \
  --limit 20 \
  -f 'body.data.people[].{name, email: emails.primaryEmail, company: companyId}'

# Total count without fetching the page contents
restish twenty-myco-core find-many-people --limit 1 -f body.totalCount -r

# Across pages — capture endCursor and feed into starting_after
NEXT=$(restish twenty-myco-core find-many-people --limit 200 -f body.pageInfo.endCursor -r)
restish twenty-myco-core find-many-people --limit 200 --starting-after "$NEXT"
```

## Reading a single record

```bash
restish twenty-myco-core find-one-person 12345-abcd-...
restish twenty-myco-core find-one-person 12345-abcd-... --depth 0   # no relation expansion
```

Path params come after the operation. Order matches the OpenAPI `parameters` list.

## Creating

Body JSON goes at the end. Two forms — both work:

```bash
# Single positional JSON arg
restish twenty-myco-core create-one-company '{"name":"Acme","domainName":{"primaryLinkUrl":"acme.com"}}'

# Restish shorthand (key.subkey: value, …)
restish twenty-myco-core create-one-company \
  name: Acme, \
  domainName.primaryLinkUrl: acme.com, \
  employees: 50
```

Shorthand is documented at https://github.com/danielgtaylor/shorthand. Use full JSON when scripting; shorthand for ad-hoc CLI work.

## Updating

```bash
restish twenty-myco-core update-one-company <id> '{"employees": 75}'

# Bulk update via filter
restish twenty-myco-core update-many-companies \
  --filter 'idealCustomerProfile[eq]:true' \
  '{"accountOwnerId": "<workspace-member-id>"}'
```

## Deleting

```bash
restish twenty-myco-core delete-one-person <id>            # soft delete (sets deletedAt)
restish twenty-myco-core delete-many-people --filter 'deletedAt[is]:NOT_NULL'  # purge soft-deleted
```

## Output projection (`-f` / `--rsh-filter`)

`-f` runs a Shorthand query (https://github.com/danielgtaylor/shorthand#querying) on the response. Most useful patterns:

```bash
-f 'body.data.companies[].name'                       # one field, returns array
-f 'body.data.companies[].{id, name, domain: domainName.primaryLinkUrl}'  # projection
-f 'body.data.companies | length'                     # count
-f 'body.data.companies[?employees > `100`]'          # filter rows on response
-f 'body.data.companies[].name | sort'
```

Pair with `-r` (raw output) to avoid JSON-quoting strings — handy when piping to other tools:

```bash
restish twenty-myco-core find-many-people --limit 100 -f 'body.data.people[].emails.primaryEmail' -r
```

## Output formats

| Flag             | Format                  |
| ---------------- | ----------------------- |
| `-o json`        | JSON (default for tool) |
| `-o yaml`        | YAML                    |
| `-o jsonschema`  | Inferred JSON schema    |
| `-r`             | Raw, no JSON quoting    |

## Headers and overrides

```bash
# One-off header
restish twenty-myco-core find-many-people -H "X-Trace: debug-1"

# Override server (e.g. to hit a staging clone of the same workspace)
restish twenty-myco-core find-many-people -s https://staging.crm.example.com/rest

# Verbose (full request + response, including auth-helper invocation)
restish twenty-myco-core find-many-people -v
```

## Multi-instance flow

If `~/.config/twenty-cli/instances.json` has multiple instances, each is registered as its own restish API. To work with `prod` vs `staging`:

```bash
restish twenty-prod-core find-many-companies
restish twenty-staging-core find-many-companies
```

There's no global "switch instance" — you select by API name. The `default` field in `instances.json` matters only for `scripts/refresh-schema.sh` when no name is passed.

## Troubleshooting

- **`Error: accepts 0 arg(s), received 1`** — you put a path-param value but the operation doesn't take one. Use `--help` to see the operation's signature.
- **Restish hangs on first call after setup** — should not happen with the slim spec. If it does, the spec wasn't slimmed (schemas not stubbed). Re-run `scripts/refresh-schema.sh <instance>`.
- **401 / 403** — token expired or revoked. Recreate API key in Twenty UI, then update the token in your chosen storage (keychain/file/env), no need to re-run setup unless URL changed.
- **Rate-limited (429)** — 100 req/min cap. Slow down or use batch endpoints (re-run setup with `--keep-batch`).
- **Custom field doesn't appear in `--help`** — spec is per-tenant but cached. Run `bash scripts/refresh-schema.sh <instance>` to re-download and clear the restish CBOR cache.
