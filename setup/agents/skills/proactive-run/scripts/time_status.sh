#!/usr/bin/env bash
# Where the run stands: deadline, usage against a linear target, machine load.
# Safe to run anytime by any agent, and the source of truth for pacing — a
# usage bar in some UI is not (one run lost hours to a stale bar reading 91%
# while the real figure was 41%).
#
# Claude snapshots come from its status line (per-model quotas); Codex comes
# from the same fetcher used by Pi's usage-status extension. Both are reported
# against the same pacing target. Never treat an old snapshot as live usage.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

now=$(date -u +%s)
goal=${RUN_BUDGET_GOAL_PERCENT}
end=$(epoch_of "${RUN_DEADLINE_UTC:?set RUN_DEADLINE_UTC in meta/run.env}")
[[ "${end}" =~ ^[0-9]+$ ]] || { echo "invalid RUN_DEADLINE_UTC in meta/run.env" >&2; exit 2; }

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
  # A run that crosses a reset may be allowed a different share of the fresh
  # window (e.g. 95% of the one that is ending, 60% of the new one).
  if [ -n "${RUN_QUOTA_RESET_UTC:-}" ]; then
    base=0
    goal=${RUN_BUDGET_GOAL_PERCENT_AFTER_RESET:-${goal}}
  fi
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
  captured=$(jq -r '.captured_at // 0' "${f}")
  [ $((now - captured)) -le 900 ] || continue
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
  cents=$(jq -r '.rate_limits.extra_usage | if .is_enabled == true and (.used_credits | type) == "number" and (.monthly_limit | type) == "number" then "\(.used_credits) \(.monthly_limit)" else empty end' "${f}")
  if [ -n "${cents}" ]; then
    read -r spent cap <<< "${cents}"
    line+=" EXTRA_USD=$(awk -v n="${spent}" 'BEGIN{printf "%.2f",n/100}')/$(awk -v n="${cap}" 'BEGIN{printf "%.2f",n/100}')"
  fi
  echo "${line}"
done
[ "${found}" = 1 ] || echo "CLAUDE=unavailable (no recent status-line snapshot)"
echo "SHORT_WINDOW_GUARD=${RUN_SHORT_WINDOW_MAX_PERCENT:-90}% (5h for both agents: above it, start nothing new)"

# Codex (pi) usage, refreshed from the subscription's usage endpoint when stale.
"${SKILL_DIR}/scripts/codex_usage.sh" > /dev/null 2>&1 || true
if [ -s "${RUN_CODEX_SNAPSHOT}" ] && jq -e '.captured_at and .rate_limits' "${RUN_CODEX_SNAPSHOT}" > /dev/null 2>&1 &&
   [ $((now - $(jq -r '.captured_at' "${RUN_CODEX_SNAPSHOT}"))) -le 900 ]; then
  line="CODEX AGE_MIN=$(((now - $(jq -r '.captured_at' "${RUN_CODEX_SNAPSHOT}")) / 60))"
  for spec in 'five_hour:SHORT' 'seven_day:LONG'; do
    key=${spec%%:*} label=${spec##*:}
    used=$(jq -r ".rate_limits.${key}.used_percentage // empty" "${RUN_CODEX_SNAPSHOT}")
    [ -n "${used}" ] || continue
    resets=$(jq -r ".rate_limits.${key}.resets_at // empty" "${RUN_CODEX_SNAPSHOT}")
    line+=" ${label}_USED=${used}%"
    [ -n "${resets}" ] && line+=" ${label}_RESET=$(date -u -d "@${resets}" +%m-%dT%H:%MZ 2> /dev/null || date -u -r "${resets}" +%m-%dT%H:%MZ 2> /dev/null)"
    [ "${label}" = "LONG" ] && line+=" VS_TARGET=$(awk "BEGIN{printf \"%+d\",${used}-${target}}")pts"
  done
  line+=" CAP=${RUN_CODEX_MAX_PERCENT:-95}%"
  credit=$(jq -r '.credit_balance // empty' "${RUN_CODEX_SNAPSHOT}")
  [ -z "${credit}" ] || line+=" CREDIT_BALANCE=${credit} (units unspecified; not USD)"
  echo "${line}"
else
  echo "CODEX=unavailable (missing or stale snapshot — is pi logged in?)"
fi

# Any external per-call paid service the run drives programmatically (a
# proxied LLM key, a paid search/data API) needs its own approved spend cap
# and a script that snapshots spend against it, written in the same shape as
# codex_usage.sh above ({"captured_at": <epoch>, "spend": <n>, "cap": <n>}).
# Point RUN_EXTERNAL_SPEND_SNAPSHOT at that file and RUN_EXTERNAL_SPEND_CAP_USD
# at the run's own lower stop. Leave both unset to skip this line entirely —
# but then nothing may call that service: unmetered spend must not happen, an
# agent must not authorize going over the cap, and only a human can raise it.
if [ -n "${RUN_EXTERNAL_SPEND_SNAPSHOT:-}" ]; then
  if [ ! -s "${RUN_EXTERNAL_SPEND_SNAPSHOT}" ] ||
    ! jq -e '(.captured_at | type) == "number" and (.spend | type) == "number"' "${RUN_EXTERNAL_SPEND_SNAPSHOT}" > /dev/null 2>&1 ||
    ! [[ "${RUN_EXTERNAL_SPEND_CAP_USD:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "EXTERNAL_SPEND=unavailable (missing or invalid snapshot/cap — stop paid calls)"
  else
    captured=$(jq -r '.captured_at | floor' "${RUN_EXTERNAL_SPEND_SNAPSHOT}")
    spent=$(jq -r '.spend' "${RUN_EXTERNAL_SPEND_SNAPSHOT}")
    if [ "$captured" -gt "$now" ] || [ $((now - captured)) -gt 900 ]; then
      echo "EXTERNAL_SPEND=stale (stop paid calls until metering is refreshed)"
    else
      verdict=$(awk -v spent="$spent" -v cap="$RUN_EXTERNAL_SPEND_CAP_USD" 'BEGIN {print (spent >= cap ? "STOP" : "OK")}')
      echo "EXTERNAL_SPEND=${verdict} AGE_MIN=$(((now - captured) / 60)) SPEND_USD=${spent} CAP_USD=${RUN_EXTERNAL_SPEND_CAP_USD}"
    fi
  fi
fi
if [ "${RUN_ALLOW_CREDITS:-0}" = 1 ]; then
  echo "ADVICE=under target -> launch more substantial delegated work; near the short-window limit -> no new workers; the human has authorised continuing on extra-usage credits (RUN_ALLOW_CREDITS=1): accept the dialog"
else
  echo "ADVICE=under target -> launch more substantial delegated work; near the short-window limit -> no new workers; never accept extra-usage credits (unless run.env sets RUN_ALLOW_CREDITS=1)"
fi

mem_available='?'
if [ -r /proc/meminfo ]; then
  mem_available=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
elif [ -s "${RUN_DIR}/meta/sysmon.json" ]; then
  mem_available=$(jq -r '.mem_avail_mb // "?"' "${RUN_DIR}/meta/sysmon.json")
fi
echo "LOAD_1M=$(load_1m) MEM_AVAIL_MB=${mem_available} CORES=$(nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo '?') LOCAL_TIME=$(date +%H:%M) (prefer heavy fan-outs when the machine is quiet)"
[ -s "${RUN_DIR}/logs/sysmon_alerts.md" ] && echo "SYSMON_LAST_ALERT=$(tail -n1 "${RUN_DIR}/logs/sysmon_alerts.md" | cut -c1-160)"

if [ "${now}" -ge "${end}" ]; then
  echo "STATUS=OVER — start nothing new, finalize the report, commit, wind down"
else
  echo "STATUS=RUNNING"
fi
