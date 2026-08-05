# Bootstrap: turning this template into a real setup repo

Instructions for a coding agent (with a human answering questions) that is
instantiating this template for a concrete environment. Work top to bottom.
Every `TODO(bootstrap)` and `TODO` marker in the tree corresponds to something
below; when you are done, none should remain.

```bash
grep -rn "TODO(bootstrap)\|TODO " --exclude-dir=.git .
```

## 0. Copy and rename

```bash
cp -r dev-setup-template ~/code/<repo-name> && cd ~/code/<repo-name>
rm -rf .git && git init && git add -A && git commit -m "chore: start from dev-setup-template"
```

Then set the repo name in `pyproject.toml` and rewrite `README.md` for the real
repo — it should describe *this* environment, not the template.

## 1. Interview first, edit second

Do not guess these. Ask, and write the answers into the files named.

| Question | Where the answer goes |
|---|---|
| Git identity (name, email) | `setup/config/profile.env` |
| Which machines do you develop on? Names, aliases, whether they are shared, whether a bastion/jump host is needed | `setup/config/ssh/hosts.toml` |
| Are you one of several users on those machines? What is your user slot? | `hosts.toml` `[defaults] user_id`, mosh port ranges per machine |
| Which services do you forward (jupyter, tensorboard, dashboards)? How many at once? | `hosts.toml` `[services]`, `slots` |
| Which repos do you actually work in, and how is each one's environment created? | a new `setup/lib/project.sh` step |
| Which package manager / interpreter do those repos need, and can you install it without root on the shared machines? | `setup/lib/packages.sh`, `setup/lib/tools.sh` |
| Where does the neovim config live? | `NVIM_CONFIG_REPO` in `profile.env` |
| Which agent(s), which models/providers? | `setup/agents/pi/agent/settings.json`, `setup/agents/claude/settings.json` |
| Which secrets does the environment need, and how do they reach a new machine? | `setup/config/secrets/README.md` — pick one method and write it down |
| Is the repo pushed to a remote all machines can reach, or synced some other way? | `README.md` |

## 2. Fill in the configuration

1. `cp setup/config/profile.env.example setup/config/profile.env` and fill it in.
   Commit it — it is shared across your machines.
2. `cp setup/config/ssh/hosts.toml.example setup/config/ssh/hosts.toml`, enter
   the real machines, then check the result before installing:
   `setup/config/bin/hosts ssh-config --base` and `--forwards`.
   If hostnames are sensitive, add `hosts.toml` to `.gitignore` and say so in
   the README.
3. `cp setup/config/ssh/custom-forwards.example setup/config/ssh/custom-forwards`
   only if you need forwards outside the systematic scheme.
4. `cp setup/config/secrets/env.example setup/config/secrets/env`, `chmod 600`,
   fill in. It is gitignored — never commit it, and never replace that rule with
   file permissions on committed plaintext.

## 3. Add the project-specific step

The generic steps stop at "a usable machine". Everything about the repos you
actually work in goes in a new `setup/lib/project.sh` with a `step_project`
function, registered in `install.sh`'s `STEPS` array (before `finish`). Typically:

- clone the repos, in a fixed location exported from `bashrc-extra`;
- create their environments (`uv sync --frozen`, or the project's own bootstrap);
- install their pre-commit hooks;
- render their `.env` from the secrets layer;
- add the aliases and env vars for them at the bottom of `bashrc-extra`.

Keeping this in its own step is what lets the rest of the repo be reused for the
next job or machine.

## 4. Adjust the agent setup

- Set the provider/model in `setup/agents/pi/agent/settings.json` and the model
  in `setup/agents/claude/settings.json`.
- Keep the generic skills (`experiments`, `dev-setup`, `restructure-commits`,
  `explore-agent`, `tmux-subtasks`). Add environment-specific ones — issue
  tracker, code review, deployment, the domain tools you use — as new
  directories in `setup/agents/skills/`, symlinked into both agents:
  ```bash
  ln -s ../../skills/<name> setup/agents/claude/skills/<name>
  ln -s ../../../skills/<name> setup/agents/pi/agent/skills/<name>
  ```
- If a skill only makes sense for one agent, put it directly in that agent's
  `skills/` directory instead of the shared one.

## 5. Install and verify

Run on the laptop first, then on one remote machine:

```bash
./setup/install.sh --list-steps
./setup/install.sh
source ~/.zshrc
```

Then verify, and fix what fails rather than noting it:

- [ ] `./setup/install.sh` a second time changes nothing (idempotence — the
      single most important property).
- [ ] `~/.zshrc` contains exactly one `DEVSETUP_ZSHRC_HEADER` block.
- [ ] `git config --get user.email` is right; `git diff` is delta-formatted.
- [ ] `conn --tmux <alias>` connects, attaches tmux, and survives a disconnect.
- [ ] Copying in remote tmux copy-mode lands in the local clipboard — over mosh
      too, not just ssh.
- [ ] `claude` and `pi` both start and both list the shared skills.
- [ ] `uv run pre-commit run --all-files` passes.
- [ ] Nothing secret is tracked: `git ls-files | grep -i -E 'secret|token|\.env$|\.pem$'`
      returns nothing but examples.

## 6. Delete this file

Once the repo is real, `BOOTSTRAP.md` is noise — its content has become the
README, `setup/README.md`, and the config files. Delete it and commit.
