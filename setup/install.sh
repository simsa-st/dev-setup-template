#!/usr/bin/env bash
# Single entry point for installing this development environment.
#
#   ./setup/install.sh                      # auto-detect target, run all steps
#   ./setup/install.sh --target linux       # force a target
#   ./setup/install.sh --only shell,tmux    # run a subset
#   ./setup/install.sh --skip nvim          # run everything but one step
#   ./setup/install.sh --list-steps         # show the ordered step list and exit
#
# Every step is idempotent: re-running the installer must be safe and must not
# append duplicate config. See setup/README.md for the design rules.

set -euo pipefail

DEV_SETUP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEV_REPO_DIR=$(cd -- "${DEV_SETUP_DIR}/.." && pwd)
export DEV_SETUP_DIR DEV_REPO_DIR

TARGET=""
ONLY=""
SKIP=""
LIST_ONLY="no"
RECREATE_ENV="no"

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs macos|linux}"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --only) ONLY="${2:?--only needs a step list}"; shift 2 ;;
    --only=*) ONLY="${1#*=}"; shift ;;
    --skip) SKIP="${2:?--skip needs a step list}"; shift 2 ;;
    --skip=*) SKIP="${1#*=}"; shift ;;
    --list-steps) LIST_ONLY="yes"; shift ;;
    --recreate-env) RECREATE_ENV="yes"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done
export RECREATE_ENV

if [ -z "${TARGET}" ]; then
  case "${OSTYPE:-$(uname -s)}" in
    darwin*|Darwin) TARGET="macos" ;;
    linux*|Linux) TARGET="linux" ;;
    *) echo "Cannot auto-detect target from '${OSTYPE:-$(uname -s)}'; pass --target." >&2; exit 2 ;;
  esac
fi
case "${TARGET}" in
  macos|linux) ;;
  *) echo "Unsupported target '${TARGET}' (expected macos or linux)." >&2; exit 2 ;;
esac
export TARGET

# shellcheck source=lib/common.sh
source "${DEV_SETUP_DIR}/lib/common.sh"
source "${DEV_SETUP_DIR}/lib/packages.sh"
source "${DEV_SETUP_DIR}/lib/shell.sh"
source "${DEV_SETUP_DIR}/lib/tools.sh"
source "${DEV_SETUP_DIR}/lib/agents.sh"
source "${DEV_SETUP_DIR}/lib/sessions.sh"
source "${DEV_SETUP_DIR}/lib/clipboard.sh"

# Ordered list of steps. Each name maps to a `step_<name>` function.
STEPS=(
  preflight
  packages
  shell
  tmux
  git
  tools
  nvim
  agents
  sessions
  clipboard
  ssh
  finish
)

if [ "${LIST_ONLY}" = "yes" ]; then
  printf '%s\n' "${STEPS[@]}"
  exit 0
fi

should_run() {
  local name="$1"
  if [ -n "${ONLY}" ] && ! list_contains "${ONLY}" "${name}"; then return 1; fi
  if [ -n "${SKIP}" ] && list_contains "${SKIP}" "${name}"; then return 1; fi
  return 0
}

log "Target: ${TARGET} | repo: ${DEV_REPO_DIR}"
for step in "${STEPS[@]}"; do
  if should_run "${step}"; then
    log "step: ${step}"
    "step_${step}"
  else
    printf '    (skipping %s)\n' "${step}"
  fi
done
