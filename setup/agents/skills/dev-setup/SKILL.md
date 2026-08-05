---
name: dev-setup
description: Use when changing the machine setup in this repo — install.sh, its steps, shell/tmux/ssh config, agent config, or the helper scripts in setup/config/bin. Works in both Claude Code and pi.
---

# dev-setup

The setup lives in `${DEV_SETUP_DIR}` (the `setup/` directory of this repo) and
installs a machine's whole environment. Read `setup/README.md` before changing
anything: it states the invariants that make re-runs safe.

Rules:

- Every step must stay **idempotent**. Never append to a user file — write into
  a `# BEGIN/END DEVSETUP_<name>` managed block, or symlink the repo file.
- Nothing outside `setup/` may hard-code a repo path. `~/.zshrc` references
  `~/.config/...` only, so moving the checkout means re-pointing symlinks.
- Values that differ per person go in `config/profile.env`; per machine, in
  `config/machine.local.env`; secrets, in `config/secrets/env`. Never inline any
  of them into a tracked config file.
- Prefer extending an existing step over adding a new one, and keep
  project-specific setup (repos you work on, their envs) in its own step so the
  generic steps stay reusable.
- After changing anything under `setup/`, update `setup/README.md` to match, and
  say which steps the user should re-run (`./setup/install.sh --only <step>`).
- Do not read `setup/config/secrets/` — it holds real tokens and keys.
- Keep coherent setup changes in focused commits (`setup: ...`, `agents: ...`).
  After committing, try `git push origin main` and report a failure rather than
  working around it.
