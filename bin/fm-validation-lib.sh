#!/usr/bin/env bash
# Positive changed-surface evidence shared by PR and local landing.
# A task receipt at state/<id>.validation.json has task_id, spawn_gen (empty for
# legacy tasks), head (full commit), result="passed", scope="changed-surface",
# and source (the validation command or pipeline run). It is trusted operator
# evidence, not a waiver of red or missing required checks. Head and task
# incarnation must match exactly. A no-mistakes task can also supply its current
# branch-bound run through axi status: Test and PR must be completed, with no
# failed step, and CI must be completed, running, pending, or skipped.
# That evidence is recorded as the task receipt before landing, including the
# pipeline run source. Skipped Test never supplies positive validation.

# shellcheck source=bin/fm-nm-run-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fm-nm-run-lib.sh"

fm_validation_receipt() { # <state> <id> <meta> <verified-head>
  local state=$1 id=$2 meta=$3 head=$4 receipt gen source wt branch mode
  local out run_head run_branch run_id outcome status tmp
  receipt="$state/$id.validation.json"
  gen=$(sed -n 's/^spawn_gen=//p' "$meta")
  if source=$(jq -er --arg id "$id" --arg gen "$gen" --arg head "$head" '
      select(.task_id == $id and .spawn_gen == $gen and .head == $head
        and .result == "passed" and .scope == "changed-surface"
        and (.source | type) == "string" and (.source | length) > 0)
      | .source' "$receipt" 2>/dev/null); then
    printf 'verified: positive validation receipt %s (source: %s) at head %s\n' "$receipt" "$source" "$head" >&2
    return 0
  fi
  mode=$(sed -n 's/^mode=//p' "$meta")
  [ "$mode" = no-mistakes ] || return 1
  wt=$(sed -n 's/^worktree=//p' "$meta")
  [ -d "$wt" ] || return 1
  branch=$(sed -n 's/^branch=//p' "$meta")
  [ -n "$branch" ] || branch="fm/$id"
  out=$(fm_nm_run_checked "$wt" 15 axi status) || return 1
  printf '%s\n' "$out" | grep -q '^run:' || return 1
  run_head=$(fm_nm_strip_quotes "$(fm_nm_field "$out" head)")
  run_branch=$(fm_nm_strip_quotes "$(fm_nm_field "$out" branch)")
  run_id=$(fm_nm_strip_quotes "$(fm_nm_field "$out" id)")
  [ -n "$run_id" ] && [ "$run_branch" = "$branch" ] || return 1
  [ "$run_head" = "$head" ] || [ "$(fm_nm_resolve_commit "$wt" "$run_head")" = "$head" ] || return 1
  outcome=$(fm_nm_strip_quotes "$(fm_nm_field "$out" outcome)")
  status=$(fm_nm_strip_quotes "$(fm_nm_field "$out" status)")
  case "$outcome" in
    passed|passed-with-skips|passed-with-override) ;;
    '') case "$status" in running|completed|ci) ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$out" | awk '
    /^[[:space:]]*steps\[[0-9]+\]\{step,status,/ { in_steps=1; next }
    in_steps && /^[[:space:]]*test,/ { test++; if ($0 ~ /^[[:space:]]*test,completed,/) test_ok++ ; next }
    in_steps && /^[[:space:]]*pr,/ { pr++; if ($0 ~ /^[[:space:]]*pr,completed,/) pr_ok++ ; next }
    in_steps && /^[[:space:]]*ci,/ { ci++; if ($0 ~ /^[[:space:]]*ci,(completed|running|pending|skipped),/) ci_ok++ ; next }
    in_steps && /^[[:space:]]*[a-z_-]+,failed,/ { failed++ ; next }
    in_steps && /^[^[:space:]]/ { in_steps=0 }
    END { exit (test != 1 || test_ok != 1 || pr != 1 || pr_ok != 1 || ci != 1 || ci_ok != 1 || failed != 0) }
  ' || return 1
  source="no-mistakes run $run_id (Test and PR completed; CI ${status})"
  tmp=$(mktemp "$state/.validation-$id.XXXXXX") || return 1
  if ! jq -n --arg id "$id" --arg gen "$gen" --arg head "$head" --arg source "$source" \
      '{task_id:$id, spawn_gen:$gen, head:$head, result:"passed", scope:"changed-surface", source:$source}' \
      > "$tmp" || ! mv "$tmp" "$receipt"; then
    rm -f "$tmp"
    return 1
  fi
  printf 'verified: positive validation receipt %s (source: %s) at head %s\n' "$receipt" "$source" "$head" >&2
}
