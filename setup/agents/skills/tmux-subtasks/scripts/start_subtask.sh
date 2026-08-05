#!/usr/bin/env bash
# Start one subtask agent in its own tmux window.
#
#   start_subtask.sh [--agent CMD] [--model NAME] [--agent-arg ARG]... \
#                    <task_dir> <name> <prompt>
#
# The window is created without stealing focus, in the current tmux session when
# there is one, else in a detached session named "subtasks".
set -euo pipefail

AGENT="${SUBTASK_AGENT:-pi}"
MODEL="${SUBTASK_MODEL:-}"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --agent-arg) EXTRA_ARGS+=("$2"); shift 2 ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

task_dir="${1:?task_dir required}"
name="${2:?subtask name required}"
prompt="${3:?prompt required}"
[ -d "${task_dir}" ] || { echo "No such task dir: ${task_dir}" >&2; exit 2; }

prompt_file="${task_dir}/prompts/${name}.md"
result_file="${task_dir}/results/${name}.md"

cat > "${prompt_file}" << EOF
${prompt}

---
## Subtask contract

You are subtask \`${name}\`, running unattended. Working directory: $(pwd).

- Write your deliverable to \`${result_file}\`. That file is the answer; chat
  output is not read.
- Stay within the scope above. If it turns out to be wrong or too broad, say so
  in the result file instead of widening it.
- When finished, append one line to \`${task_dir}/progress.log\`:
  \`STATUS: DONE|FAILED|BLOCKED — ${name} — <one line of context>\`
- Then stop. Do not start unrelated work.
EOF

agent_args=()
[ -n "${MODEL}" ] && agent_args+=(--model "${MODEL}")
agent_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

agent_bin=$(command -v "${AGENT}") || { echo "Agent '${AGENT}' not on PATH" >&2; exit 2; }
tmux_cmd=(tmux)
[ -n "${TMUX_SOCKET:-}" ] && tmux_cmd=(tmux -S "${TMUX_SOCKET}")

if [ -n "${TMUX:-}" ]; then
  session=$("${tmux_cmd[@]}" display-message -p '#S')
else
  session="${TMUX_SUBTASK_SESSION:-subtasks}"
  "${tmux_cmd[@]}" has-session -t "${session}" 2> /dev/null ||
    "${tmux_cmd[@]}" new-session -d -s "${session}"
fi

# The wrapper keeps the window open on failure so it can be inspected, and
# closes it on a clean DONE so the session does not fill up with dead windows.
runner="${task_dir}/logs/run-${name}.sh"
cat > "${runner}" << EOF
#!/usr/bin/env bash
cd "$(pwd)"
"${agent_bin}" ${agent_args[*]+"${agent_args[*]}"} "\$(cat '${prompt_file}')"
status=\$?
if [ \${status} -eq 0 ] && grep -q "STATUS: DONE — ${name}" '${task_dir}/progress.log' 2>/dev/null; then
  exit 0
fi
echo
echo "Subtask ${name} needs attention (exit \${status}). Window kept open."
exec bash
EOF
chmod +x "${runner}"

"${tmux_cmd[@]}" new-window -d -t "${session}" -n "sub-${name}" "${runner}"
echo "started subtask '${name}' in ${session}:sub-${name} (agent: ${AGENT} ${agent_args[*]-})"
echo "  prompt: ${prompt_file}"
echo "  result: ${result_file}"
