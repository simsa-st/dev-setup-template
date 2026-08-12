#!/usr/bin/env bash
# Where the run stands: deadline, usage against a linear target, machine load.
# Safe to run anytime by any agent, and the source of truth for pacing — a
# usage bar in some UI is not (one run lost hours to a stale bar reading 91%
# while the real figure was 41%).
#
# Usage snapshots come from the agent's status line (see the statusline script
# in this repo's agent config), one file per model because quotas can differ
# per model. Without them, everything but the usage lines still works.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

now=$(date -u +%s)
goal=${RUN_BUDGET_GOAL_PERCENT}
end=$(epoch_of "${RUN_DEADLINE_UTC:?set RUN_DEADLINE_UTC in meta/run.env}")

echo "NOW_UTC=$(now_utc)"
echo "DEADLINE_UTC=${RUN_DEADLINE_UTC}"
if [ -n "${RUN_START_UTC:-}" ]; then
  start=$(epoch_of "${RUN_START_UTC}")
  echo "START_UTC=${RUN_START_UTC}"
  echo "ELAPSED_HOURS=$(((now - start) / 3600))"
else
  start=${now}
  echo "START_UTC=<not started>"
fi
echo "REMAINING_HOURS=$([ "${now}" -lt "${end}" ] && echo $(((end - now) / 3600)) || echo 0)"

# A quota reset inside the run splits pacing into two windows: spend the first
# bucket by the reset, then pace the fresh one to the deadline.
base=${RUN_BUDGET_BASELINE_PERCENT:-0}
if [ -n "${RUN_QUOTA_RESET_UTC:-}" ] && [ "${now}" -lt "$(epoch_of "${RUN_QUOTA_RESET_UTC}")" ]; then
  reset=$(epoch_of "${RUN_QUOTA_RESET_UTC}")
  echo "PACING_WINDOW=pre-reset (quota resets ${RUN_QUOTA_RESET_UTC} — spend it before then)"
  win_start=${start} win_end=${reset}
else
  echo "PACING_WINDOW=final (deadline ${RUN_DEADLINE_UTC})"
  [ -n "${RUN_QUOTA_RESET_UTC:-}" ] && base=0
  win_start=$([ -n "${RUN_QUOTA_RESET_UTC:-}" ] && epoch_of "${RUN_QUOTA_RESET_UTC}" || echo "${start}")
  win_end=${end}
fi
target=$(awk "BEGIN{v=${base}+(${goal}-${base})*(${now}-${win_start})/(${win_end}-${win_start});
  if(v<${base})v=${base}; if(v>${goal})v=${goal}; printf \"%.0f\",v}")
echo "TARGET_USED_PERCENT=${target} (linear to ${goal}% by window end)"

snapshot_glob="$(dirname "${RUN_RATE_LIMIT_SNAPSHOT}")/$(basename "${RUN_RATE_LIMIT_SNAPSHOT}" .json).*.json"
found=0
for f in ${snapshot_glob}; do
  [ -s "${f}" ] || continue
  jq -e '.rate_limits != null' "${f}" > /dev/null 2>&1 || continue
  found=1
  model=$(jq -r '.model // "unknown"' "${f}")
  captured=$(jq -r '.captured_at' "${f}")
  line="MODEL=${model} AGE_MIN=$(((now - captured) / 60))"
  for spec in 'five_hour:SHORT' 'seven_day:LONG'; do
    key=${spec%%:*} label=${spec##*:}
    used=$(jq -r "(.rate_limits.${key}.used_percentage // empty) | if type==\"number\" then (.*10|round)/10 else . end" "${f}")
    [ -n "${used}" ] || continue
    line+=" ${label}_USED=${used}%"
    resets=$(jq -r ".rate_limits.${key}.resets_at // empty" "${f}")
    [ -n "${resets}" ] && line+=" ${label}_RESET=$(date -u -r "${resets}" +%m-%dT%H:%MZ 2> /dev/null ||
      date -u -d "@${resets}" +%m-%dT%H:%MZ 2> /dev/null)"
    [ "${label}" = "LONG" ] && line+=" VS_TARGET=$(awk "BEGIN{printf \"%+d\",${used}-${target}}")pts"
  done
  echo "${line}"
done
[ "${found}" = 1 ] || echo "USAGE=unavailable (no status-line snapshot yet)"
echo "ADVICE=under target -> launch more substantial delegated work; near the short-window limit -> no new workers; never accept extra-usage credits"

echo "LOAD_1M=$(load_1m) LOCAL_TIME=$(date +%H:%M) (prefer heavy fan-outs when the machine is quiet)"

if [ "${now}" -ge "${end}" ]; then
  echo "STATUS=OVER — start nothing new, finalize the report, commit, wind down"
else
  echo "STATUS=RUNNING"
fi
