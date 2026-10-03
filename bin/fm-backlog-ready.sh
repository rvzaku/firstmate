#!/usr/bin/env bash
# Read the configured backlog's bounded readiness snapshot without mutating it.
# Usage: fm-backlog-ready.sh
# Prints ready<TAB>id, pending<TAB>id<TAB>date, or uncertainty<TAB>reason.
# Queued, unblocked, non-captain work is authorized pending work. Captain holds
# remain excluded even after their date expires. Other dated holds require
# supervision through their deadline. Quota and dispatch limits are resolved by
# firstmate before launch, never inferred by this reader.
# An existing worker record excludes its item from pending dispatch.
# FM_READY_READ_TIMEOUT bounds the backend read (default 3 seconds).
# FM_READY_ITEM_LIMIT bounds the comparison (default 1000 items).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_HOME=${FM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}
DATA=${FM_DATA_OVERRIDE:-$FM_HOME/data}
STATE=${FM_STATE_OVERRIDE:-$FM_HOME/state}
# shellcheck source=/dev/null
. "$SCRIPT_DIR/fm-tasks-axi-lib.sh"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/fm-backlog-transition-lib.sh"

[ -d "$DATA" ] || exit 0
bound=${FM_READY_READ_TIMEOUT:-3}
limit=${FM_READY_ITEM_LIMIT:-1000}
case "$bound" in ''|*[!0-9]*|0) bound=3 ;; esac
case "$limit" in ''|*[!0-9]*|0) limit=1000 ;; esac
# shellcheck disable=SC2016
if ! output=$(set +u; fm_exec_timed "$bound" 1 bash -c '
  . "$1/fm-tasks-axi-lib.sh"
  . "$1/fm-backlog-transition-lib.sh"
  fm_backlog_tasks_axi_addressing "$2" || exit
  if [ -n "$FM_BACKLOG_AXI_FILE" ] && [ ! -e "$FM_BACKLOG_AXI_FILE" ]; then exit 0; fi
  if [ -n "$FM_BACKLOG_AXI_FILE" ]; then export TASKS_AXI_FILE="$FM_BACKLOG_AXI_FILE"; else unset TASKS_AXI_FILE; fi
  fm_backlog_row_list "$2" --state queued --fields blocked,held,hold_kind,hold_until --limit "$3"
' _ "$SCRIPT_DIR" "$DATA" "$limit" 2>&1); then
  printf 'uncertainty\tconfigured backlog read failed, tasks-axi is unavailable, or the %ss bound expired\n' "$bound"
  exit 0
fi
[ -n "$output" ] || exit 0
if parsed=$(printf '%s\n' "$output" | perl -MJSON::PP -e '
  my (@fields, $expected, $seen, $total); $seen = 0;
  while (<STDIN>) {
    if (/^count: (\d+)(?: of (\d+) total)?/) { $total = $2 // $1; $expected = 0 if $1 == 0; }
    if (/^tasks\[(\d+)\]\{([^}]+)\}:\s*$/) {
      $expected = $1; @fields = split /,/, $2; next;
    }
    next unless @fields && $seen < $expected && /^  (.*)$/;
    my $line = $1; my @values;
    while (length $line) {
      if ($line =~ s/^("(?:[^"\\]|\\.)*")(?=,|$)//) {
        push @values, decode_json($1);
      } elsif ($line =~ s/^([^,]*)(?=,|$)//) { push @values, $1; }
      else { die "invalid backlog row\n"; }
      last unless length $line;
      $line =~ s/^,// or die "invalid backlog separator\n";
    }
    die "invalid backlog fields\n" unless @values == @fields;
    my %row; @row{@fields} = @values; ++$seen;
    for my $field (qw(id state kind blocked held hold_kind hold_until)) {
      die "missing backlog field\n" unless exists $row{$field};
    }
    die "invalid backlog identity\n" unless $row{id} =~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
    die "invalid backlog flags\n" unless $row{blocked} =~ /^(yes|no)$/ && $row{held} =~ /^(yes|no)$/;
    next if $row{kind} eq "captain" || $row{kind} eq "public-followup" || $row{hold_kind} eq "captain";
    next unless $row{state} eq "queued" && $row{blocked} eq "no";
    if ($row{held} eq "no") { print "ready\t$row{id}\n"; }
    elsif ($row{hold_until} =~ /^\d{4}-\d{2}-\d{2}$/) { print "pending\t$row{id}\t$row{hold_until}\n"; }
  }
  die "incomplete backlog snapshot\n" unless defined $expected && $seen == $expected;
  print "uncertainty\tbacklog comparison truncated at $seen of $total items\n" if defined $total && $total > $seen;
' 2>/dev/null); then
  while IFS=$'\t' read -r class id deadline; do
    case "$class" in
      ready|pending) [ ! -e "$STATE/$id.meta" ] || continue ;;
    esac
    [ -n "$class" ] || continue
    printf '%s\t%s' "$class" "$id"
    [ -z "$deadline" ] || printf '\t%s' "$deadline"
    printf '\n'
  done <<EOF
$parsed
EOF
else
  printf 'uncertainty\tconfigured backlog returned an unreadable readiness snapshot\n'
fi
