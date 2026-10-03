# shellcheck shell=bash
# Shared "supervision missing" predicate.
# Usage: . bin/fm-supervision-lib.sh
#
# Reports whether a firstmate home needs supervision (fm_supervision_status
# below is the single owner of that condition set), and whether its watcher has
# a fresh liveness beacon (state/.last-watcher-beat, touched every poll cycle,
# within the grace window).
# bin/fm-turnend-guard.sh uses the PID-strict fm_watcher_healthy from
# bin/fm-wake-lib.sh for its block decision. bin/fm-guard.sh uses the model-aware
# fm_watcher_supervision_verdict (also in bin/fm-wake-lib.sh), which owns what a
# live watcher process means per supervision model. The status fields here retain
# the beacon-age details used in their messages.

# Portable mtime; Linux stat lacks -f, macOS stat lacks -c.
fm_sup_stat_mtime() {
  if [ "$(uname)" = Darwin ]; then
    /usr/bin/stat -f %m "$1" 2>/dev/null
  else
    stat -c %Y "$1" 2>/dev/null
  fi
}

# fm_supervision_status <state-dir> [grace-seconds]
# Populates, for the state dir at $1:
#   FM_SUP_IN_FLIGHT      count of state/*.meta (in-flight tasks)
#   FM_SUP_SOURCES        count of registered process-to-event sources
#   FM_SUP_CHECKS         count of registered custom checks: a state/<id>.check.sh
#                         with the state/<id>.check-trust binding that
#                         bin/fm-check-register.sh writes. Task PR polls carry no
#                         such binding and are torn down with their task, and the
#                         relay shim keeps its own trust path, so neither counts
#                         here. Presence of the binding is the whole test: whether
#                         those bytes are still the registered ones is the check
#                         sweep's call at execution time, and a home whose check
#                         no longer validates needs the watcher precisely so the
#                         sweep can report the rejection instead of going quiet.
#   FM_SUP_NEEDED         true/false - in-flight work, an X-mode relay poll, a
#                         registered event source (a source is a wait on an
#                         external process, not a task, so it has no metadata),
#                         a registered custom check, or authorized pending backlog
#                         work or its next eligibility deadline
#   FM_SUP_BACKLOG        true/false - pending work or a deadline; read failure or uncertainty never sets it
#   FM_SUP_BACKLOG_DETAIL bounded configured-backlog readiness snapshot, cached
#                         for 60 seconds in state/.backlog-ready-cache after a
#                         successful read without uncertainty
#   FM_SUP_WATCHER_FRESH  true/false - a watcher beacon within the grace window
#   FM_SUP_BEACON_DESC    human-readable beacon age, for banners ("never" if absent)
#   FM_SUP_QUEUE_PENDING  true/false - state/.wake-queue has unread records
# grace-seconds defaults to $FM_GUARD_GRACE, then 300, matching fm-guard.sh.
# Always returns 0; callers read the vars, or use fm_supervision_unhealthy below.
fm_supervision_status() {
  local state=$1 grace=${2:-${FM_GUARD_GRACE:-300}} meta source check id beat m age
  FM_SUP_IN_FLIGHT=0
  FM_SUP_NEEDED=false
  FM_SUP_WATCHER_FRESH=false
  FM_SUP_BEACON_DESC=never
  FM_SUP_QUEUE_PENDING=false
  FM_SUP_BACKLOG=false
  FM_SUP_BACKLOG_DETAIL=

  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    FM_SUP_IN_FLIGHT=$((FM_SUP_IN_FLIGHT + 1))
  done
  FM_SUP_SOURCES=0
  for source in "$state"/procevent/*.source; do
    [ -e "$source" ] || continue
    FM_SUP_SOURCES=$((FM_SUP_SOURCES + 1))
  done
  FM_SUP_CHECKS=0
  for check in "$state"/*.check.sh; do
    [ -e "$check" ] || continue
    id=${check##*/}
    id=${id%.check.sh}
    if [ "$id" = x-watch ]; then
      continue
    fi
    [ -e "$state/$id.check-trust" ] || continue
    FM_SUP_CHECKS=$((FM_SUP_CHECKS + 1))
  done
  local readiness_bin home cache cached_at snapshot line now tab
  tab=$(printf '\t')
  readiness_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fm-backlog-ready.sh"
  home=${FM_HOME:-${state%/*}}
  cache="$state/.backlog-ready-cache"
  if [ -x "$readiness_bin" ]; then
    now=$(date +%s)
    cached_at=$(fm_sup_stat_mtime "$cache")
    if [ -n "$cached_at" ] && [ $((now - cached_at)) -ge 0 ] && [ $((now - cached_at)) -lt 60 ]; then
      FM_SUP_BACKLOG_DETAIL=$(cat "$cache" 2>/dev/null)
    elif snapshot=$(FM_HOME="$home" FM_STATE_OVERRIDE="$state" "$readiness_bin" 2>/dev/null); then
      FM_SUP_BACKLOG_DETAIL=$snapshot
      case "$snapshot" in
        *uncertainty*) ;;
        *) [ ! -d "$state" ] || printf '%s' "$snapshot" > "$cache" 2>/dev/null || true ;;
      esac
    fi
    while IFS= read -r line; do
      case "$line" in
        ready"$tab"*|pending"$tab"*) FM_SUP_BACKLOG=true ;;
      esac
    done <<BACKLOG_EOF
$FM_SUP_BACKLOG_DETAIL
BACKLOG_EOF
  fi
  if [ "$FM_SUP_IN_FLIGHT" -gt 0 ] \
    || [ -f "$state/x-watch.check.sh" ] \
    || [ "$FM_SUP_SOURCES" -gt 0 ] \
    || [ "$FM_SUP_CHECKS" -gt 0 ] \
    || [ "$FM_SUP_BACKLOG" = true ]; then
    FM_SUP_NEEDED=true
  fi

  beat="$state/.last-watcher-beat"
  if [ -e "$beat" ]; then
    m=$(fm_sup_stat_mtime "$beat")
    if [ -n "$m" ]; then
      age=$(( $(date +%s) - m ))
      FM_SUP_BEACON_DESC="${age}s ago"
      [ "$age" -lt "$grace" ] && FM_SUP_WATCHER_FRESH=true
    else
      # shellcheck disable=SC2034 # Read by callers (fm-guard.sh) after sourcing.
      FM_SUP_BEACON_DESC=unknown
    fi
  fi

  # shellcheck disable=SC2034 # Read by callers (fm-guard.sh) after sourcing.
  [ -s "$state/.wake-queue" ] && FM_SUP_QUEUE_PENDING=true
  return 0
}

# fm_supervision_needed <state-dir> [grace-seconds]
# Exit 0 (true) exactly when the home needs a watcher.
fm_supervision_needed() {
  fm_supervision_status "$@"
  [ "$FM_SUP_NEEDED" = true ]
}

# fm_supervision_unhealthy <state-dir> [grace-seconds]
# Exit 0 (true) exactly when supervision is needed and no watcher has a fresh
# beacon. Exit 1 (false) otherwise.
fm_supervision_unhealthy() {
  fm_supervision_status "$@"
  [ "$FM_SUP_NEEDED" = true ] && [ "$FM_SUP_WATCHER_FRESH" = false ]
}
