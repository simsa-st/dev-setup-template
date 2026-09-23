#!/usr/bin/env bash
# Dead-man heartbeat: plain bash, detached by run.sh start, outliving every
# agent. Each beat KILLS whatever is in the heartbeat window and respawns a
# fresh cheap session on prompts/heartbeat_check.md — so the checker never
# grows a conversation, and a wedged checker is replaced rather than nudged.
# This loop never types into an agent's window itself; the checker does that.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

interval=${RUN_HEARTBEAT_INTERVAL_S}
end=$(epoch_of "${RUN_DEADLINE_UTC}")
grace=$((2 * 3600))
target=$(target_of heartbeat)
model=$(role_model heartbeat)

hb_log() { echo "$(now_utc) $*"; }

# Respawn runs on the tmux host side, so wrap the agent in the run's window
# command (a plain shell locally, docker exec in a containerised setup). Launch
# the agent with NO prompt argument and send the prompt afterwards, exactly as a
# worker is started: an inline prompt has to survive this loop's quoting and
# then the shell's, and when it does not the window comes up empty, the UI never
# appears, and the loop logs one failure an hour while doing nothing at all.
inner="cd ${RUN_WORK_DIR} && $(agent_launch_cmd "${model}")"
# An interactive shell may stop at a framework prompt before it ever runs the
# command: oh-my-zsh's "Would you like to update? [Y/n]" held one run's
# checker window for hours (BEAT_FAILED every beat, nothing repaired).
cmd="DISABLE_AUTO_UPDATE=true ${RUN_WINDOW_CMD} -ic '${inner}'"

# Background jobs the run depends on (a driver, a pipeline) are declared one
# per line in meta/jobs.txt:
#   <name> <pgrep-pattern> <log-path> <failure-regex> <finished-regex>
# Every beat this loop -- plain bash, no model -- counts failure lines and
# checks liveness, and wakes the manager on any change. One run lost most of
# its background jobs over several hours while every beat said "no alerts":
# the checker judged the agents healthy and never looked at the job they
# existed to produce. The checker prompt repeats this check; this is the floor.
jobs_file="${RUN_DIR}/meta/jobs.txt"
jobs_state="${RUN_DIR}/meta/heartbeat_jobs.state"
check_jobs() {
  [ -f "${jobs_file}" ] || return 0
  local name pat log fail done_re prev cur alerts="" last
  while read -r name pat log fail done_re; do
    [ -z "${name}" ] && continue; case "${name}" in \#*) continue ;; esac
    [ -f "${log}" ] || { alerts+="${name}: log ${log} missing; "; continue; }
    # grep -c prints the count even when it is 0 (and then exits 1), so no
    # `|| echo 0` -- that would print a second line and break the comparison.
    cur=$(grep -cE -- "${fail}" "${log}" 2> /dev/null); cur=${cur:-0}
    prev=$(grep -E "^${name} " "${jobs_state}" 2> /dev/null | awk '{print $2}')
    prev=${prev:-0}
    if [ "${cur}" -gt "${prev}" ]; then
      alerts+="${name}: ${cur} failure lines (was ${prev}) -- $(grep -E -- "${fail}" "${log}" | tail -3 | tr '\n' '|'); "
    elif [ "${cur}" -lt "${prev}" ]; then
      # The log was rotated or truncated: the count restarted. Rebase on the
      # new count instead of staying blind until it climbs past the old one.
      hb_log "jobs: ${name} log count fell ${prev} -> ${cur} (rotated?); rebasing"
    fi
    last=$(tail -n 1 "${log}" 2> /dev/null)
    if ! pgrep -f -- "${pat}" > /dev/null 2>&1 && ! printf '%s' "${last}" | grep -qE -- "${done_re}"; then
      alerts+="${name}: no process matching '${pat}' and the log does not end in a finished line; "
    fi
    printf '%s %s\n' "${name}" "${cur}" >> "${jobs_state}.new"
  done < "${jobs_file}"
  [ -f "${jobs_state}.new" ] && mv "${jobs_state}.new" "${jobs_state}"
  if [ -n "${alerts}" ]; then
    hb_log "JOB_ALERT: ${alerts}"
    "${SKILL_DIR}/scripts/message.sh" send --wake heartbeat manager "JOB ALERT (mechanical, from heartbeat.sh): ${alerts} Act on it this cycle; do not wait for the checker." > /dev/null 2>&1 || true
  fi
}

hb_log "heartbeat loop started (every ${interval}s until ${RUN_DEADLINE_UTC})"
while true; do
  check_jobs
  now=$(date -u +%s)
  if [ "${now}" -ge $((end + grace)) ]; then
    hb_log "deadline + grace reached, exiting"
    break
  fi
  if ! tmx has-session -t "${RUN_SESSION}" 2> /dev/null; then
    hb_log "session ${RUN_SESSION} is gone — cannot respawn, exiting"
    break
  fi

  hb_log "beat: respawning the checker in ${target}"
  # Kill and create, never `respawn-window -k`: respawn reuses the pane, and an
  # agent launched through `docker exec -it` never comes up under a reused one.
  # Create against the SESSION with -n, since `-t session:name` means "at the
  # position of the window called name" and so cannot create it.
  tmx kill-window -t "${target}" 2> /dev/null
  if ! tmx new-window -d -t "${RUN_SESSION}" -n heartbeat "${cmd}" 2> /dev/null; then
    hb_log "BEAT_FAILED: could not create ${target} — the loop is alive and doing nothing"
  elif wait_for_agent_ui "${target}" 90; then
    send_to_agent "${target}" "Read ${RUN_DIR}/prompts/heartbeat_check.md and follow it."
    hb_log "beat: checker prompted"
  else
    hb_log "BEAT_FAILED: checker UI did not appear — check RUN_WINDOW_CMD and the agent binary"
  fi

  remaining=$((end + grace - $(date -u +%s)))
  if [ "${remaining}" -lt "${interval}" ]; then
    sleep "$([ "${remaining}" -gt 0 ] && echo "${remaining}" || echo 1)"
  else
    sleep "${interval}"
  fi
done
