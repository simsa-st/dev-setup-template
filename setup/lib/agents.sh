#!/usr/bin/env bash
# Coding agents: Claude Code and pi.
#
# Both keep their whole config directory in this repo and symlink it into $HOME,
# so agent settings, skills and prompts are versioned and identical on every
# machine. Runtime state (credentials, sessions, caches) is gitignored — see
# setup/agents/*/.gitignore. settings.json is the awkward case, because it is
# both: see merge_agent_settings.
#
# Skills live once in setup/agents/skills/ and are symlinked into each agent's
# skills dir, so a skill edit reaches both agents. Agent-specific skills live
# directly in that agent's skills dir.

# The layer paths are installed in both modes; the canonical ones only when this
# repo owns the machine. In layer mode the agents themselves are the base
# setup's business -- installing a second copy of the CLI would fight it -- so
# only the config directories are linked, and ${LAYER_ROOT}/.envrc (step_env) is
# what points the agents at them.
# Render an agent's settings from the base file this repo owns, keeping whatever
# the agent itself has written into the live one.
#
# settings.json is the agent's file to write, and both agents write to it:
# Claude Code records skipDangerousModePermissionPrompt there once you accept
# the dangerous-mode warning, pi records lastChangelogVersion on every upgrade
# and the packages this step installs. Tracking that file means a machine that
# has ever run an agent is permanently dirty, and any pull touching the file
# conflicts -- and a conflicted settings.json is one Claude Code cannot parse to
# start. settings.base.json is the half this repo owns; settings.json is
# gitignored and belongs to the agent.
#
# Base keys win, so an edit there converges on every machine at the next
# install, the way the rest of the installer does. Keys only the live file has
# are kept. The merge is deliberately shallow: `permissions` is the repo's to
# define wholesale, not something to accumulate entries into from both sides.
#
# A key *removed* from the base is not removed from the live file -- delete it
# there, or delete the live file and let this rewrite it.
merge_agent_settings() { # <base file> <live file>
  local base="$1" live="$2"
  [ -f "${base}" ] || return 0
  python3 - "${base}" "${live}" <<'SETTINGS_PY'
import json
import sys
from pathlib import Path

base_path, live_path = Path(sys.argv[1]), Path(sys.argv[2])
base = json.loads(base_path.read_text())

live = {}
if live_path.exists():
    try:
        live = json.loads(live_path.read_text())
    except json.JSONDecodeError:
        # Half-written, or carrying conflict markers. Not something to merge
        # into, and not something to discard silently either.
        kept = live_path.with_name(live_path.name + ".unparsable")
        live_path.rename(kept)
        print(f"!!! {live_path} was not valid JSON; kept it at {kept}", file=sys.stderr)

merged = {**live, **base}
# A re-run with nothing to change must touch nothing.
if merged != live:
    live_path.parent.mkdir(parents=True, exist_ok=True)
    live_path.write_text(json.dumps(merged, indent=2) + "\n")
SETTINGS_PY
}

step_agents() {
  local claude_dir="${DEV_SETUP_DIR}/agents/claude"
  local pi_dir="${DEV_SETUP_DIR}/agents/pi"

  adopt_existing_agent_dir "${LAYER_CLAUDE_DIR}" "${claude_dir}"
  adopt_existing_agent_dir "${LAYER_PI_DIR}" "${pi_dir}"
  link "${claude_dir}" "${LAYER_CLAUDE_DIR}"
  link "${pi_dir}" "${LAYER_PI_DIR}"

  # After adoption, so a machine whose agent dir was just pulled into the repo
  # keeps the runtime keys it arrived with, and before the early return, so it
  # happens in layer mode too.
  merge_agent_settings "${claude_dir}/settings.base.json" "${claude_dir}/settings.json"
  merge_agent_settings "${pi_dir}/agent/settings.base.json" "${pi_dir}/agent/settings.json"

  [ "${DEVSETUP_MODE}" = "full" ] || return 0

  adopt_existing_agent_dir "${HOME}/.claude" "${claude_dir}"
  adopt_existing_agent_dir "${HOME}/.pi" "${pi_dir}"
  link "${claude_dir}" "${HOME}/.claude"
  link "${pi_dir}" "${HOME}/.pi"

  if have claude; then
    claude update
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  if have npm; then
    if have pi; then
      pi update
    else
      npm install -g "${PI_PACKAGE}"
    fi
    have pi && pi install npm:pi-nvim || true
  else
    warn "npm missing; skipping pi install/update (run the tools step first)."
  fi
}
