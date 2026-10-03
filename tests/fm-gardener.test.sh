#!/usr/bin/env bash
set -u
# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
GARDENER="$ROOT/bin/fm-gardener.sh"
TMP_ROOT=$(fm_test_tmproot fm-gardener)
make_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/data/sample" "$home/state"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  : > "$home/data/backlog.md"
  printf '%s\n' "$home"
}
write_finding() {
  printf 'id=%s severity=medium file=%s line=%s description=%s authority=review\n' \
    "$1" "$2" "$3" "$4" >> "$5"
}
test_clusters_threshold_and_idempotency() {
  local home output queued_first queued_second
  home=$(make_home clustered)
  write_finding F-1 bin/dispatch.sh 10 'Avoid silent fallback when credentials fail' "$home/data/sample/nm-a-findings.txt"
  write_finding F-2 bin/dispatch.sh 20 'Avoid silent fallback when provider access fails' "$home/data/sample/nm-b-findings.txt"
  write_finding F-3 bin/dispatch.sh 30 'Use explicit fallback when model support is unknown' "$home/data/sample/nm-c-findings.txt"
  write_finding F-4 bin/brief.sh 40 'Use explicit approval for destructive change' "$home/data/sample/nm-d-findings.txt"
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener failed on synthetic findings"
  assert_contains "$output" 'bin/dispatch.sh | avoid silent fallback | hits=2' "the repeated theme was not clustered and ranked"
  assert_not_contains "$output" 'F-1' "finding identifiers leaked to output"
  assert_not_contains "$output" 'authority=review' "finding details leaked to output"
  queued_first=$(FM_HOME="$home" "$ROOT/bin/fm-tasks-axi.sh" list --state queued)
  assert_contains "$queued_first" 'Lint rule: avoid silent fallback' "the repeated theme did not create a queued lint task"
  assert_not_contains "$queued_first" 'provider access fails' "finding text was copied into the task"
  assert_contains "$(cat "$home/state/fm-gardener.tsv")" 'queued=1' "the run record missed its queued count"
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener rerun failed"
  queued_second=$(FM_HOME="$home" "$ROOT/bin/fm-tasks-axi.sh" list --state queued)
  assert_contains "$output" 'queued=0' "the rerun did not report zero new tasks"
  assert_equals "$queued_first" "$queued_second" "the rerun duplicated a queued theme"
  pass "gardener clusters repeated findings, queues one task at threshold, and stays idempotent"
}

test_empty_input_writes_record() {
  local home output
  home=$(make_home empty)
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener failed on empty input"
  assert_contains "$output" 'result=empty files=0 findings=0 themes=0 queued=0' "empty input did not produce the empty result"
  local record
  record=$(cat "$home/state/fm-gardener.tsv")
  assert_contains "$record" 'completed_at=' "empty input record missed its completion time"
  assert_contains "$record" $'result=empty\tfiles=0\tfindings=0\tthemes=0\tqueued=0' \
    "empty input did not write complete run counts"
  pass "gardener handles empty input and writes a run record"
}

command -v tasks-axi >/dev/null 2>&1 || { printf 'skip: tasks-axi is unavailable\n'; exit 0; }
test_clusters_threshold_and_idempotency
test_empty_input_writes_record
