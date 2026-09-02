#!/usr/bin/env bash
# Single entry point for installing this development environment.
#
#   ./setup/install.sh                      # auto-detect target, run all steps
#   ./setup/install.sh --mode full          # this repo owns this machine
#   ./setup/install.sh --target linux       # force a target
#   ./setup/install.sh --only shell,tmux    # run a subset
#   ./setup/install.sh --skip nvim          # run everything but one step
#   ./setup/install.sh --list-steps         # show the ordered step list and exit
#
# Two modes, because a machine you own and a machine another setup owns need
# different halves:
#
#   full              This repo owns the machine. Packages, zsh, tmux, git,
#                     uv/node, and the agent and editor configs at their
#                     canonical paths (~/.claude, ~/.pi, ~/.config/nvim).
#   layer  (default)  Another setup owns the base of this machine — a work
#                     dotfiles repo, or a second instantiation of this template.
#                     This install adds only its own layer beside it:
#                     ~/.config/nvim-<suffix>, ~/.claude-<suffix>,
#                     ~/.pi-<suffix>, ~/.config/.bashrc-<suffix>, a managed
#                     block appended to ~/.zshrc and a fragment under
#                     ~/.ssh/config.d. It writes nothing the other setup owns,
#                     so the two installs are order-independent and either can
#                     be re-run at any time.
#
# `--mode` is sticky: it is written to config/machine.local.env (gitignored), so
# a machine is told once. LAYER_SUFFIX in profile.env names the layer's paths.
#
# Every step is idempotent: re-running the installer must be safe and must not
# append duplicate config. See setup/README.md for the design rules.

set -euo pipefail

DEV_SETUP_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEV_REPO_DIR=$(cd -- "${DEV_SETUP_DIR}/.." && pwd)
export DEV_SETUP_DIR DEV_REPO_DIR

TARGET=""
MODE=""
ONLY=""
SKIP=""
LIST_ONLY="no"
RECREATE_ENV="no"

usage() {
  sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?--target needs macos|linux}"; shift 2 ;;
    --target=*) TARGET="${1#*=}"; shift ;;
    --mode) MODE="${2:?--mode needs layer|full}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
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

# Everything this installer installs user-locally lands in ${XDG_CONFIG_HOME}/bin
# (uv, node shims, delta, jq, the helper scripts). Put it on PATH here rather
# than relying on step_shell, which sources bashrc-extra as a side effect and is
# both full-mode-only and skippable: `--only project` otherwise ran with a
# different PATH than a full install and reported tools "not installed" that
# were sitting right there.
export PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/bin:${PATH}"

resolve_mode "${MODE}"
load_profile

# Ordered list of steps. Each name maps to a `step_<name>` function; the ones in
# FULL_ONLY_STEPS are the base of a machine and run in full mode only.
STEPS=(
  preflight
  packages
  shell
  tmux
  git
  tools
  nvim
  agents
  env
  sessions
  clipboard
  ssh
  finish
)
# nvim, agents, env, git and ssh run in both modes: each one installs to its
# layer path always, and additionally to the canonical path in full mode. The
# rest are the base of a machine, which in layer mode belongs to somebody else.
#
# git is in that list rather than full-only because a commit made from this
# setup's tree has to carry this setup's identity even when the base setup owns
# ~/.config/git/config; step_git writes an includeIf for the tree instead.
FULL_ONLY_STEPS="packages,shell,tmux,tools,sessions,clipboard"

if [ "${LIST_ONLY}" = "yes" ]; then
  for step in "${STEPS[@]}"; do
    if [ "${DEVSETUP_MODE}" = "layer" ] && list_contains "${FULL_ONLY_STEPS}" "${step}"; then
      printf '%s (full mode only)\n' "${step}"
    else
      printf '%s\n' "${step}"
    fi
  done
  exit 0
fi

should_run() {
  local name="$1"
  if [ "${DEVSETUP_MODE}" = "layer" ] && list_contains "${FULL_ONLY_STEPS}" "${name}"; then return 1; fi
  if [ -n "${ONLY}" ] && ! list_contains "${ONLY}" "${name}"; then return 1; fi
  if [ -n "${SKIP}" ] && list_contains "${SKIP}" "${name}"; then return 1; fi
  return 0
}

log "Mode: ${DEVSETUP_MODE} | target: ${TARGET} | repo: ${DEV_REPO_DIR}"
for step in "${STEPS[@]}"; do
  if should_run "${step}"; then
    log "step: ${step}"
    "step_${step}"
  else
    printf '    (skipping %s)\n' "${step}"
  fi
done
