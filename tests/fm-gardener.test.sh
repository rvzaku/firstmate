#!/usr/bin/env bash
set -u
# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
GARDENER="$ROOT/bin/fm-gardener.sh"
TASKS="$ROOT/bin/fm-tasks-axi.sh"
TMP_ROOT=$(fm_test_tmproot fm-gardener)
make_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/data" "$home/state"
  cp "$ROOT/.tasks.toml" "$home/.tasks.toml"
  : > "$home/data/backlog.md"
  printf '%s\n' "$home"
}
close_task() {
  FM_HOME="$1" "$TASKS" add "$2" "Synthetic $2" --kind ship >/dev/null || fail "could not add $2"
  FM_HOME="$1" "$TASKS" start "$2" >/dev/null || fail "could not start $2"
  FM_HOME="$1" "$TASKS" 'done' "$2" >/dev/null || fail "could not close $2"
}
write_text() {
  mkdir -p "$(dirname "$5")"
  printf 'id=%s severity=medium file=%s line=%s description=%s authority=review\n' \
    "$1" "$2" "$3" "$4" >> "$5"
}
write_json() {
  mkdir -p "$(dirname "$5")"
  printf '{"id":"%s","severity":"error","file":"%s","line":%s,"description":"%s"}\n' \
    "$1" "$2" "$3" "$4" >> "$5"
}
test_clusters_text_and_json_snapshots() {
  local home output
  home=$(make_home clustered)
  close_task "$home" task-a
  close_task "$home" task-b
  write_text F-1 bin/dispatch.sh 10 'Avoid silent fallback when credentials fail in dispatch.' "$home/data/task-a/nm-a-findings.txt"
  write_json F-2 bin/spawn.sh 20 'Avoid silent fallback when credentials fail in spawn' "$home/data/task-b/nm-b-findings.txt"
  write_text F-3 bin/brief.sh 30 'Use explicit approval for destructive change' "$home/data/task-b/nm-c-findings.txt"
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener failed on synthetic findings"
  assert_contains "$output" 'hits=2 | snapshots=2 | paths=bin/dispatch.sh,bin/spawn.sh' "text and JSON findings did not cluster across snapshots"
  assert_not_contains "$output" 'destructive' "a single hit was reported as a candidate"
  assert_not_contains "$output" 'F-1' "finding identifiers leaked to output"
  assert_contains "$output" 'candidates=1' "the summary missed the candidate count"
  assert_contains "$(cat "$home/state/fm-gardener.tsv")" 'completed_at=' "the run record missed its completion time"
  assert_equals "" "$(FM_HOME="$home" "$TASKS" list --state queued | grep -i 'lint' || true)" "the gardener filed a task"
  pass "gardener clusters text and JSON snapshots, applies the two-hit threshold, and files nothing"
}
test_only_closed_tasks_in_bounded_window() {
  local home output n
  home=$(make_home window)
  close_task "$home" closed-task
  for n in $(seq 1 22); do
    write_text "F-$n" bin/x.sh 1 "Recurring bounded theme appears again and again $n" "$home/data/closed-task/nm-$(printf '%02d' "$n")-findings.txt"
    touch -t "20260101$(printf '%02d' "$n")00" "$home/data/closed-task/nm-$(printf '%02d' "$n")-findings.txt"
  done
  write_text F-open bin/open.sh 1 'Recurring bounded theme appears again and again open' "$home/data/open-task/nm-z-findings.txt"
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener failed on the bounded window"
  assert_contains "$output" 'files=20 ' "the sample was not bounded to the newest 20 snapshots"
  assert_not_contains "$output" 'bin/open.sh' "a task that is not closed was sampled"
  pass "gardener samples only closed tasks within the newest 20 snapshots"
}
test_empty_input_writes_record() {
  local home output record
  home=$(make_home empty)
  output=$(FM_HOME="$home" "$GARDENER") || fail "gardener failed on empty input"
  assert_contains "$output" 'result=empty files=0 findings=0 clusters=0 candidates=0' "empty input did not produce the empty result"
  record=$(cat "$home/state/fm-gardener.tsv")
  assert_contains "$record" $'result=empty\tfiles=0\tfindings=0\tclusters=0\tcandidates=0' "empty input did not write complete run counts"
  pass "gardener handles empty input and writes a run record"
}
test_help_has_no_short_alias() {
  local home
  home=$(make_home help)
  assert_contains "$(FM_HOME="$home" "$GARDENER" --help)" 'candidate' "--help printed no usage"
  FM_HOME="$home" "$GARDENER" -h >/dev/null 2>&1 && fail "-h was accepted"
  pass "gardener answers --help only"
}

command -v tasks-axi >/dev/null 2>&1 || { printf 'skip: tasks-axi is unavailable\n'; exit 0; }
test_clusters_text_and_json_snapshots
test_only_closed_tasks_in_bounded_window
test_empty_input_writes_record
test_help_has_no_short_alias
