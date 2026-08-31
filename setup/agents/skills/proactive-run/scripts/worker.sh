#!/usr/bin/env bash
# Start a disposable worker agent in its own window of the run's session.
#
#   worker.sh <name> <prompt-file> [cwd] [model] [spawner]
#
#   name         short slug; the window becomes cw-<name>
#   prompt-file  the file the worker reads and follows (keep it in the run dir)
#   cwd          working directory — give every concurrent code-writing worker
#                its own git worktree, never a shared checkout
#   model        cheaper models for mechanical bulk, stronger for judgement
#   spawner      role notified on completion (default manager)
#
# The window is left open when the worker finishes so its results can be read;
# collect them, then `agent.sh stop cw-<name>`.
set -uo pipefail
SKILL_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=run_env.sh
source "${SKILL_DIR}/scripts/run_env.sh"

name=${1:?worker name required}
prompt_file=$(cd -- "$(dirname -- "${2:?prompt file required}")" && pwd)/$(basename -- "$2")
cwd=${3:-${RUN_WORK_DIR}}
model=${4:-$(role_model manager)}
spawner=${5:-manager}
win="cw-${name}"
target="${RUN_SESSION}:${win}"

tmx new-window -d -t "${RUN_SESSION}" -n "${win}" "${RUN_WINDOW_CMD}"
sleep 1
tmx send-keys -t "${target}" "cd ${cwd}" Enter
sleep 1
tmx send-keys -t "${target}" "$(agent_launch_cmd "${model}")" C-m

if ! wait_for_agent_ui "${target}" 90; then
  echo "worker UI did not come up in ${target} — inspect manually" >&2
  exit 1
fi
sleep 2

# The contract is repeated to every worker because each clause here was bought
# with lost work: silent finishes, local-only branches, and instructions that
# arrived while the worker was busy.
send_to_agent "${target}" "Read ${prompt_file} and follow it. Work autonomously — never ask the user anything; decide and record. Before declaring done: (1) run ${SKILL_DIR}/scripts/message.sh read ${win} and act on anything pending — instructions often arrive while you work; (2) if you created or advanced a git branch, verify the push with git ls-remote; (3) write your results where the prompt says; (4) state DONE or FAILED with a reason as your final message, and immediately notify your spawner so nobody waits on you: ${SKILL_DIR}/scripts/message.sh send --wake ${win} ${spawner} 'DONE|FAILED: <result path> + one-line summary'. Routine progress goes without --wake. When you finish, leave your window open and stand by: your spawner closes it after collecting your results, and work you own may still draw questions."

"${SKILL_DIR}/scripts/message.sh" log "${spawner}" "started worker ${win} (model ${model}, cwd ${cwd}, prompt ${prompt_file})"
echo "worker started in ${target} (model ${model})"
echo "watch: tmux -S ${TMUX_SOCKET} capture-pane -p -t ${target}"
