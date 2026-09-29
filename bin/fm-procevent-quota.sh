#!/usr/bin/env bash
# Quota process-event adapter.
#
# Usage:
#   fm-procevent-quota.sh arm [--recovery] [--interval <secs>] [--threshold <percent>] [--provider <provider>]
#   fm-procevent-quota.sh poll [--recovery] [--interval <secs>] [--threshold <percent>] [--provider <provider>] [--timeout <secs>]
#   fm-procevent-quota.sh classify <result-file>
#   fm-procevent-quota.sh terminal <result-file>
#   fm-procevent-quota.sh source-id [--recovery] [--provider <provider>]
#   fm-procevent-quota.sh retire [--recovery] [--provider <provider>]
#
# arm        Register a recurring quota-axi --json poll that wakes firstmate
#            when the tracked provider's effectivePercentRemaining drops below
#            <threshold> (default 10%) or when its runway.status becomes
#            exhausted_now. With --recovery it instead wakes after a provider
#            observed below the threshold or exhausted is known above the
#            threshold again on every reported scope. The condition is
#            deterministic, the action is only
#            the durable `check: procevent quota <source-id> <seq>` wake, and the watch is
#            registered through `bin/fm-procevent.sh register`.
# poll       The blocking child the generic runner executes; never run this
#            directly in a conversational turn. It polls `quota-axi --json`
#            until its condition is met or an error stops the watch.
# classify   Print the captured outcome class: low, exhausted, recovered, error, or unknown.
# terminal   Every quota poll is terminal because the source fires at most once.
# source-id  Print the canonical source id.
# retire     Stop the aggregate watch, or the matching provider watch when
#            --provider is supplied, and retire the registration.
#
# The canonical source id is `quota` for the aggregate tracked provider.
# A provider named with --provider makes it `quota-<provider>`.
# Recovery sources use `quota.recovery` and `quota.recovery-<provider>` so both
# watch types can run independently.
#
# Snapshots may be quota-axi schema 5 or 6 (bin/fm-quota-axi-lib.sh owns the
# validator). Both watches read every matching account row independently,
# without combining quotas. A --provider watch restricts those rows to the
# requested provider; details preserve each row's accountKey when present.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-procevent-lib.sh
. "$SCRIPT_DIR/fm-procevent-lib.sh"
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$SCRIPT_DIR/fm-quota-axi-lib.sh"
# shellcheck source=bin/fm-timeout-lib.sh
. "$SCRIPT_DIR/fm-timeout-lib.sh"

DEFAULT_INTERVAL=60
DEFAULT_THRESHOLD=10

SOURCE_ID_BASE=quota

CANONICAL_SOURCE_ID=
PROVIDER=
RECOVERY=0

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "${BASH_SOURCE[0]}"
  exit 2
}
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

resolve_provider() {
  local LC_ALL=C
  PROVIDER=${1:-}
  if [ -n "$PROVIDER" ]; then
    [[ "$PROVIDER" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "invalid provider: $PROVIDER"
    CANONICAL_SOURCE_ID="$SOURCE_ID_BASE-$PROVIDER"
  else
    CANONICAL_SOURCE_ID=$SOURCE_ID_BASE
    PROVIDER=
  fi
  fm_procevent_source_id_valid "$CANONICAL_SOURCE_ID" || die "source id is not path-safe: $CANONICAL_SOURCE_ID"
}

resolve_source() {
  SOURCE_ID_BASE=quota
  [ "$RECOVERY" = 0 ] || SOURCE_ID_BASE=quota.recovery
  resolve_provider "${1-}"
}

positive_number() {
  local n=${1-}
  local LC_ALL=C
  [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  [ "$n" != 0 ] && [[ ! "$n" =~ ^0+(\.0+)?$ ]]
}

positive_int() { case "${1-}" in ''|*[!0-9]*) return 1 ;; 0) return 1 ;; *) return 0 ;; esac }

valid_percent() {
  local n=${1-}
  local LC_ALL=C
  [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  jq -en --arg n "$n" '($n | tonumber) <= 100' >/dev/null 2>&1
}

valid_recovery_threshold() {
  valid_percent "$1" && jq -en --arg n "$1" '($n | tonumber) < 100' >/dev/null 2>&1
}

# quota_json [timeout]
# Run `quota-axi --json` bounded by the given timeout. A missing or incompatible
# quota-axi is an error condition, not a signal to fire.
quota_json() {
  local timeout=${1:-} output
  if [ -n "$timeout" ]; then
    fm_quota_axi_compatible "$timeout" >/dev/null 2>&1 || return 2
    output=$(fm_run_timed "$timeout" quota-axi --json 2>/dev/null </dev/null) || return 2
  else
    fm_quota_axi_compatible >/dev/null 2>&1 || return 2
    output=$(quota-axi --json 2>/dev/null </dev/null) || return 2
  fi
  printf '%s\n' "$output"
}

# condition_status <json> [provider] [threshold]
# Print healthy, low, exhausted, or error for the tightest known applicable
# quota scope.
condition_status() {
  local json=$1 provider=${2:-} threshold=${3:-$DEFAULT_THRESHOLD}
  printf '%s\n' "$json" | fm_quota_json_valid || { printf 'error\n'; return; }
  printf '%s\n' "$json" | jq -r --arg provider "$provider" --arg threshold "$threshold" '
    def classify($availability):
      ($availability | map(select(.status == "known"))) as $known |
      if ($availability | length) == 0 then "error"
      elif any($availability[]; (.runway.status // "") == "exhausted_now") then "exhausted"
      elif ($known | length) == 0 then "healthy"
      elif any($known[]; .effectivePercentRemaining < ($threshold | tonumber)) then "low"
      else "healthy"
      end;
    .providers |= map(select($provider == "" or .provider == $provider)) |
    if (.providers | length) == 0 and $provider != "" then "error"
    elif ([.providers[]?.quotaSemantics.effectiveAvailability[]?] | length) == 0 then "healthy"
    else classify([.providers[]?.quotaSemantics.effectiveAvailability[]?])
    end
  ' 2>/dev/null || printf 'error\n'
}

# details <json> [provider]
# Print a one-line summary of the quota state for the result document.
details() {
  local json=$1 provider=${2:-}
  printf '%s\n' "$json" | jq -c --arg provider "$provider" '
    def best_detail($availability):
      ($availability | map(select(.status == "known"))) as $known |
      ($availability | map(select((.runway.status // "") == "exhausted_now"))) as $exhausted |
      if ($exhausted | length) > 0 then ($exhausted | min_by(.effectivePercentRemaining // 101))
      elif ($known | length) > 0 then ($known | min_by(.effectivePercentRemaining))
      else null
      end;
    [.providers[]? | select($provider == "" or .provider == $provider) |
      {provider}
      + (if has("accountKey") then {accountKey} else {} end)
      + {best: best_detail(.quotaSemantics.effectiveAvailability // [])}
    ] as $summary |
    if $provider == "" or ($summary | length) > 1 then
      {
        provider: (if $provider == "" then "aggregate" else $provider end),
        summary: $summary
      }
    else
      $summary[0] // {provider: $provider, best: null}
    end
  ' 2>/dev/null
}

# A recovery needs positive evidence for every reported scope of this provider.
# Unknown, missing, and exactly-at-threshold scopes cannot prove recovery.
recovery_provider_status() {
  local json=$1 provider=$2 threshold=$3
  printf '%s\n' "$json" | jq -r --arg provider "$provider" --arg threshold "$threshold" '
    [.providers[] | select(.provider == $provider)] as $rows |
    [$rows[] | .quotaSemantics.effectiveAvailability[]?] as $availability |
    if ($availability | length) == 0 then "unknown"
    elif any($availability[]; (.runway.status // "") == "exhausted_now") then "exhausted"
    elif any($availability[]; .status == "known" and .effectivePercentRemaining < ($threshold | tonumber)) then "low"
    elif all($rows[]; .quotaSemantics.status == "known") and
         all($availability[]; .status == "known" and .effectivePercentRemaining > ($threshold | tonumber)) then "healthy"
    else "unknown"
    end
  ' 2>/dev/null || printf 'error\n'
}

cmd_source_id() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recovery) RECOVERY=1; shift ;;
      --provider) [ -n "${2-}" ] || die "--provider needs a value"; PROVIDER=$2; shift 2 ;;
      *) [ -z "$PROVIDER" ] || usage; PROVIDER=$1; shift ;;
    esac
  done
  resolve_source "$PROVIDER"
  printf '%s\n' "$CANONICAL_SOURCE_ID"
}

cmd_arm() {
  local interval=$DEFAULT_INTERVAL threshold=$DEFAULT_THRESHOLD
  local -a poll_args=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recovery) RECOVERY=1; shift ;;
      --interval)  positive_number "${2-}" || die "--interval needs a positive number"; interval=$2; shift 2 ;;
      --threshold) valid_percent "${2-}" || die "--threshold needs a percent 0-100"; threshold=$2; shift 2 ;;
      --provider)  [ -n "${2-}" ] || die "--provider needs a value"; PROVIDER=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  resolve_source "$PROVIDER"
  [ "$RECOVERY" = 0 ] || valid_recovery_threshold "$threshold" || die "--recovery needs a threshold below 100"
  fm_quota_axi_compatible 5 >/dev/null 2>&1 || die "quota-axi is missing or below the compatibility floor"
  local timeout
  timeout=$(perl -e 'print int($ARGV[0] * 0.8 + 0.5)' "$interval") || timeout=30
  [ "$timeout" -ge 5 ] || timeout=5
  [ "$RECOVERY" = 0 ] || poll_args+=(--recovery)
  "$SCRIPT_DIR/fm-procevent.sh" register quota "$CANONICAL_SOURCE_ID" \
    -- "$SCRIPT_DIR/fm-procevent-quota.sh" poll "${poll_args[@]}" --interval "$interval" --threshold "$threshold" --provider "$PROVIDER" --timeout "$timeout" || exit 1
  printf 'armed: %s\n' "$CANONICAL_SOURCE_ID"
  printf 'provider: %s\n' "${PROVIDER:-(aggregate)}"
  printf 'threshold: %s%%\n' "$threshold"
  printf 'interval: %ss\n' "$interval"
}

# For use inside the runner: parse the spec argv and run one condition evaluation.
# This is intentionally not the public `arm` path; the runner calls this command
# directly, so the argv must match the registration.
cmd_poll() {
  local interval=$DEFAULT_INTERVAL threshold=$DEFAULT_THRESHOLD timeout=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recovery) RECOVERY=1; shift ;;
      --interval)  [ "$#" -ge 2 ] || die "--interval needs a positive number"; interval=$2; shift 2 ;;
      --threshold) [ "$#" -ge 2 ] || die "--threshold needs a percent 0-100"; threshold=$2; shift 2 ;;
      --provider)  [ "$#" -ge 2 ] || die "--provider needs a value"; PROVIDER=$2; shift 2 ;;
      --timeout)   [ "$#" -ge 2 ] || die "--timeout needs a positive integer"; timeout=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  positive_number "$interval" || die "--interval needs a positive number"
  valid_percent "$threshold" || die "--threshold needs a percent 0-100"
  [ "$RECOVERY" = 0 ] || valid_recovery_threshold "$threshold" || die "--recovery needs a threshold below 100"
  [ -z "$timeout" ] || positive_int "$timeout" || die "--timeout needs a positive integer"
  resolve_source "$PROVIDER"
  local json detail status polls=0 provider seen_low='|' recovered='' providers=''
  while :; do
    polls=$((polls + 1))
    status=unknown
    if ! json=$(quota_json "${timeout:-}"); then
      printf 'quota: %s\n' "$CANONICAL_SOURCE_ID"
      printf 'status: error\n'
      printf 'detail: quota-axi --json failed or quota-axi is missing/incompatible\n'
      printf 'condition_polls: %s\n' "$polls"
      exit 0
    fi
    if [ "$RECOVERY" = 1 ]; then
      printf '%s\n' "$json" | fm_quota_json_valid || status=error
      if [ "${status:-}" != error ]; then
        providers=$(printf '%s\n' "$json" | jq -r --arg provider "$PROVIDER" '
          [.providers[] | select($provider == "" or .provider == $provider) | .provider] | unique[]')
        while IFS= read -r provider; do
          [ -n "$provider" ] || continue
          status=$(recovery_provider_status "$json" "$provider" "$threshold")
          case "$status" in
            low|exhausted)
              case "$seen_low" in *"|$provider|"*) : ;; *) seen_low="$seen_low$provider|" ;; esac
              ;;
            healthy)
              case "$seen_low" in *"|$provider|"*) recovered=$provider; break ;; esac
              ;;
            error) break ;;
          esac
        done <<< "$providers"
        if [ -n "$recovered" ]; then
          status=recovered
        elif [ "$status" != error ]; then
          sleep "$interval"
          continue
        fi
      fi
    else
      status=$(condition_status "$json" "$PROVIDER" "$threshold")
    fi
    case "$status" in
      healthy) sleep "$interval"; continue ;;
      low|exhausted|recovered) : ;;
      *) status=error ;;
    esac
    detail=$(details "$json" "${recovered:-$PROVIDER}")
    printf 'quota: %s\n' "$CANONICAL_SOURCE_ID"
    printf 'status: %s\n' "$status"
    [ -z "$recovered" ] || printf 'recovered_provider: %s\n' "$recovered"
    printf 'detail: %s\n' "$detail"
    printf 'condition_polls: %s\n' "$polls"
    exit 0
  done
}

cmd_classify() {
  local file=${1-} status
  [ -n "$file" ] || usage
  [ -f "$file" ] || die "result file does not exist: $file"
  status=$(awk '
    $0 == "output:" { exit }
    /^status: / { sub(/^status: /, ""); print; exit }
  ' "$file")
  case "$status" in
    low|exhausted|recovered|error) printf '%s\n' "$status" ;;
    *) printf 'unknown\n' ;;
  esac
}

cmd_terminal() {
  local file=${1-}
  [ -n "$file" ] || usage
  [ -f "$file" ] || die "result file does not exist: $file"
  [ "$(cmd_classify "$file")" != unknown ]
}

cmd_retire() {
  local id provider=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recovery) RECOVERY=1; shift ;;
      --provider) [ -n "${2-}" ] || die "--provider needs a value"; provider=$2; shift 2 ;;
      -*) usage ;;
      *) [ -z "$provider" ] || usage; provider=$1; shift ;;
    esac
  done
  resolve_source "$provider"
  id=$CANONICAL_SOURCE_ID
  "$SCRIPT_DIR/fm-procevent.sh" retire "$id"
}

case "${1-}" in
  arm)       shift; cmd_arm "$@" ;;
  poll)      shift; cmd_poll "$@" ;;
  classify)  shift; cmd_classify "$@" ;;
  terminal)  shift; cmd_terminal "$@" ;;
  source-id) shift; cmd_source_id "$@" ;;
  retire)    shift; cmd_retire "$@" ;;
  ''|-h|--help|help) usage ;;
  *) die "unknown command: $1" ;;
esac
