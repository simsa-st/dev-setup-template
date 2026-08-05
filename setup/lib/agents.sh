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

step_agents() {
  link "${DEV_SETUP_DIR}/agents/claude" "${HOME}/.claude"
  link "${DEV_SETUP_DIR}/agents/pi" "${HOME}/.pi"

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
