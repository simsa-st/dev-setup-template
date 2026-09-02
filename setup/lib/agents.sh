#!/usr/bin/env bash
# Coding agents: Claude Code and pi.
#
# Both keep their whole config directory in this repo and symlink it into $HOME,
# so agent settings, skills and prompts are versioned and identical on every
# machine. Runtime state (credentials, sessions, caches) is gitignored — see
# setup/agents/*/.gitignore.
#
# Skills live once in setup/agents/skills/ and are symlinked into each agent's
# skills dir, so a skill edit reaches both agents. Agent-specific skills live
# directly in that agent's skills dir.

# The layer paths are installed in both modes; the canonical ones only when this
# repo owns the machine. In layer mode the agents themselves are the base
# setup's business -- installing a second copy of the CLI would fight it -- so
# only the config directories are linked, and ${LAYER_ROOT}/.envrc (step_env) is
# what points the agents at them.
step_agents() {
  local claude_dir="${DEV_SETUP_DIR}/agents/claude"
  local pi_dir="${DEV_SETUP_DIR}/agents/pi"

  adopt_existing_agent_dir "${LAYER_CLAUDE_DIR}" "${claude_dir}"
  adopt_existing_agent_dir "${LAYER_PI_DIR}" "${pi_dir}"
  link "${claude_dir}" "${LAYER_CLAUDE_DIR}"
  link "${pi_dir}" "${LAYER_PI_DIR}"

  [ "${DEVSETUP_MODE}" = "full" ] || return 0

  adopt_existing_agent_dir "${HOME}/.claude" "${claude_dir}"
  adopt_existing_agent_dir "${HOME}/.pi" "${pi_dir}"
  link "${claude_dir}" "${HOME}/.claude"
  link "${pi_dir}" "${HOME}/.pi"

  if ! have claude; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  if have npm; then
    npm install -g "${PI_PACKAGE}"
    have pi && pi install npm:pi-nvim || true
  else
    warn "npm missing; skipping pi install (run the tools step first)."
  fi
}
