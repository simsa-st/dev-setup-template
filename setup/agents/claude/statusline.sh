#!/usr/bin/env bash
# Claude Code status line: directory, branch, model, and bars for context and
# subscription usage.
#
# Besides rendering, it persists the native rate-limit fields to a snapshot file
# so unattended runs can pace themselves (see the proactive-run skill) — a
# status line is the only place those numbers are handed to us. One file per
# model id as well as a latest-any-model one, because usage buckets can differ
# per model.
set -u
input=$(cat)

snapshot=${CLAUDE_RATE_LIMIT_SNAPSHOT:-/tmp/claude-rate-limits.json}
mkdir -p "$(dirname "${snapshot}")"
model_id=$(jq -j '.model.id // .model.display_name // "unknown"' <<< "${input}" | tr -c 'a-zA-Z0-9._-' '-')
for out in "${snapshot}" "$(dirname "${snapshot}")/$(basename "${snapshot}" .json).${model_id}.json"; do
  tmp="${out}.$$"
  jq --argjson captured_at "$(date +%s)" --arg model "${model_id}" \
    '{captured_at: $captured_at, model: $model, rate_limits: (.rate_limits // null)}' \
    <<< "${input}" > "${tmp}" && mv "${tmp}" "${out}"
done

cwd=$(jq -r '.workspace.current_dir // ""' <<< "${input}")
model=$(jq -r '.model.display_name // ""' <<< "${input}")
dir=${cwd##*/}
branch=""
if [ -n "${cwd}" ] && git -C "${cwd}" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "${cwd}" rev-parse --abbrev-ref HEAD 2> /dev/null || true)
fi

bar() { # <percent>
  local pct filled color=28 out="" i
  pct=$(awk -v p="${1:-0}" 'BEGIN{printf "%.0f",p}')
  filled=$((pct / 10))
  [ "${filled}" -gt 10 ] && filled=10
  [ "${pct}" -ge 50 ] && color=136
  [ "${pct}" -ge 80 ] && color=166
  [ "${pct}" -ge 95 ] && color=124
  for ((i = 0; i < filled; i++)); do out+="█"; done
  for ((i = filled; i < 10; i++)); do out+="░"; done
  printf '\033[38;5;%dm%s\033[0m %d%%' "${color}" "${out}" "${pct}"
}

reset_in() { # <epoch>
  local reset=${1:-} now diff mins
  [[ ${reset} =~ ^[0-9]+$ ]] || return 0
  now=$(date +%s)
  diff=$((reset - now))
  [ "${diff}" -gt 0 ] || return 0
  mins=$((diff / 60))
  if [ "${mins}" -ge 1440 ]; then
    printf ' \033[90m~%dd%dh\033[0m' "$((mins / 1440))" "$((mins % 1440 / 60))"
  elif [ "${mins}" -ge 60 ]; then
    printf ' \033[90m~%dh%dm\033[0m' "$((mins / 60))" "$((mins % 60))"
  else
    printf ' \033[90m~%dm\033[0m' "${mins}"
  fi
}

parts=()
[ -n "${branch}" ] && parts+=("${dir} [${branch}]") || parts+=("${dir}")
[ -n "${model}" ] && parts+=("${model}")
current=$(jq -r '(.context_window.current_usage // {}) | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))' <<< "${input}")
size=$(jq -r '.context_window.context_window_size // 0' <<< "${input}")
[ "${size}" -gt 0 ] && parts+=("ctx:$(bar "$((current * 100 / size))")")
for spec in 'five_hour:5h' 'seven_day:7d'; do
  key=${spec%%:*} label=${spec##*:}
  pct=$(jq -r ".rate_limits.${key}.used_percentage // empty" <<< "${input}")
  [ -n "${pct}" ] || continue
  resets=$(jq -r ".rate_limits.${key}.resets_at // empty" <<< "${input}")
  parts+=("${label}:$(bar "${pct}")$(reset_in "${resets}")")
done
# Extra-usage credits are cents. Show only explicit spend and limit values;
# subscription usage is not an inferred dollar cost.
extra=$(jq -r '.rate_limits.extra_usage | if .is_enabled == true and (.used_credits | type) == "number" and (.monthly_limit | type) == "number" then "\(.used_credits) \(.monthly_limit)" else empty end' <<< "${input}")
if [ -n "${extra}" ]; then
  read -r used limit <<< "${extra}"
  parts+=("extra:\$$(awk -v n="${used}" 'BEGIN{printf "%.2f",n/100}')/\$$(awk -v n="${limit}" 'BEGIN{printf "%.2f",n/100}')")
fi

printf '%s' "${parts[0]:-}"
for ((i = 1; i < ${#parts[@]}; i++)); do printf ' \033[90m|\033[0m %s' "${parts[i]}"; done
