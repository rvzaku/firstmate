#!/usr/bin/env bash
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-help-contract)
HELP_HOME="$TMP_ROOT/home"
mkdir -p "$HELP_HOME"/{data,state,config,projects}
known_gaps='fm-agy-trust.sh fm-backend.sh fm-backlog-handoff.sh fm-backlog-receive.sh fm-bootstrap.sh fm-branch-outcome.sh fm-branch-prompt.sh fm-busy-event.sh fm-check-register.sh fm-check-unregister.sh fm-crew-state.sh fm-extension.sh fm-fleet-ledger.sh fm-forge-detect.sh fm-guard.sh fm-harness.sh fm-herdr-ci-cleanup.sh fm-herdr-session-cleanup.sh fm-install-actionlint.sh fm-install-herdr.sh fm-install-shellcheck.sh fm-install-treehouse.sh fm-lab-home.sh fm-lease.sh fm-lock.sh fm-merge-local.sh fm-on.sh fm-peek.sh fm-pr-check.sh fm-pr-poll.sh fm-promote.sh fm-procevent-remote-reply.sh fm-procevent-when.sh fm-project-mode.sh fm-quota-choose.sh fm-remote-delta-read.sh fm-remote-doctor.sh fm-remote-entrypoint.sh fm-remote-file.sh fm-remote-herdr-guard.sh fm-remote-home-provision.sh fm-remote-home-seed.sh fm-remote-inherit-push.sh fm-remote-inherit.sh fm-remote-job-worker.sh fm-remote-secondmate-relaunch.sh fm-secondmate-report.sh fm-sessionstart-cursor.sh fm-sessionstart-nudge.sh fm-sessionstart-run.sh fm-supervise-daemon.sh fm-turnend-guard-cursor.sh fm-turnend-guard-grok.sh fm-turnend-guard.sh fm-wake-grant.sh fm-watch-arm.sh fm-watch.sh fm-x-dismiss.sh fm-x-link.sh fm-x-poll.sh'
checked=0
allowed=0

for script in "$ROOT"/bin/fm-*.sh; do
  name=${script##*/}
  case "$name" in *-lib.sh) continue ;; esac
  out=$(timeout 5s env -i PATH="$PATH" HOME="$HELP_HOME" FM_HOME="$HELP_HOME" \
    FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$HELP_HOME/state" \
    FM_DATA_OVERRIDE="$HELP_HOME/data" FM_CONFIG_OVERRIDE="$HELP_HOME/config" \
    FM_PROJECTS_OVERRIDE="$HELP_HOME/projects" "$script" --help 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -Eiq 'usage:'; then
    checked=$((checked + 1))
    case " $known_gaps " in *" $name "*) fail "$name now supports --help and must be removed from the allowlist" ;; esac
  else
    case " $known_gaps " in
      *" $name "*) allowed=$((allowed + 1)) ;;
      *) fail "$name --help must exit 0 and print a usage line (exit $rc): $out" ;;
    esac
  fi
done

pass "bin help contract: checked $checked entry scripts, with $allowed known gaps allowlisted"
