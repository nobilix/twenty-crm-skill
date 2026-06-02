#!/usr/bin/env bash
# Reduce a Twenty core OpenAPI spec for use with Restish. Two transformations:
#   1. Stub all schemas to {"type":"object"} — REQUIRED. Twenty's schemas have
#      circular $ref cycles that hang restish's parser. Stubbing keeps the CLI
#      surface intact (operations, parameters) at the cost of request/response
#      validation in --help, which is fine: the full spec is kept separately as
#      reference material for the agent.
#   2. Filter paths to a focused CRM subset (default) or keep all (--full).
#
# Output: transformed spec on stdout.
#
# Usage:
#   slim-spec.sh <input.json>                     # default slim (8 objects)
#   slim-spec.sh <input.json> --full              # keep all object groups
#   slim-spec.sh <input.json> --objects a,b,c     # custom object set
#   slim-spec.sh <input.json> --keep-batch --keep-restore
#
# Defaults (slim mode):
#   --objects: people, companies, opportunities, tasks, notes,
#              taskTargets, noteTargets, workspaceMembers
#   /batch/* and /restore/* paths dropped (toggle with --keep-* flags)
#   /{x}/duplicates and /{x}/merge always dropped (low-value noise)

set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,22p' "$0"; exit 1; }
input="$1"; shift

DEFAULT_OBJECTS="people,companies,opportunities,tasks,notes,taskTargets,noteTargets,workspaceMembers"
objects="$DEFAULT_OBJECTS"
drop_batch=true
drop_restore=true
full=false

while [ $# -gt 0 ]; do
  case "$1" in
    --objects)      objects="$2"; shift ;;
    --keep-batch)   drop_batch=false ;;
    --keep-restore) drop_restore=false ;;
    --full)         full=true ;;
    *) echo "slim-spec: unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# Schema stubbing is mandatory — applied in both --full and slim modes.
STUB='
  .info.description = "See references/filter-dsl.md."
  | .components.schemas = (
      (.components.schemas // {}) | with_entries(.value = {type: "object"})
    )
'

if [ "$full" = "true" ]; then
  jq "$STUB" "$input"
  exit 0
fi

jq \
  --arg objs "$objects" \
  --argjson drop_batch   "$drop_batch" \
  --argjson drop_restore "$drop_restore" \
  "$STUB"'
  | ($objs | split(",") | map(select(length > 0))) as $keep
  | .paths |= with_entries(
      select(
        (.key | test("/(duplicates|merge)$") | not)
        and (($drop_batch   | not) or (.key | startswith("/batch/")   | not))
        and (($drop_restore | not) or (.key | startswith("/restore/") | not))
        and (.key == "/open-api/core"
             or (((.key | ltrimstr("/") | split("/"))[0]) as $top | ($keep | index($top)) != null))
      )
    )
' "$input"
