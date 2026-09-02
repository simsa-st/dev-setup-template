# Bootstrap: turning this template into a real setup repo

Instructions for a coding agent (with a human answering questions) that is
instantiating this template for a concrete environment. Work top to bottom.
Every `TODO(bootstrap)` and `TODO` marker in the tree corresponds to something
below; when you are done, none should remain.

```bash
grep -rn "TODO(bootstrap)\|TODO " --exclude-dir=.git .
```

## Day zero: what has to exist before the repo does

A brand-new machine has a bootstrap paradox: several of the things that make
cloning this repo work are configured *by* this repo. None of it can move into
`install.sh`, so it is worth stating once rather than rediscovering per machine.

**macOS: Homebrew, and its PATH lines.** `setup/lib/packages.sh` refuses to run
without it. On Apple Silicon it installs to `/opt/homebrew`, which is *not* on
the default `PATH`, so the "next steps" Homebrew prints when it finishes are
load-bearing rather than advisory:

```bash
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
```

**An ssh key the remote already trusts** — and if its filename is not one ssh
tries by default (`id_ed25519`, `id_rsa`, ...), the very first clone has to name
it, because the `IdentityFile` line that makes this unnecessary is generated
from `hosts.toml` by the `ssh` step and therefore arrives *with* the repo being
cloned:

```bash
GIT_SSH_COMMAND='ssh -i ~/.ssh/<key>' git clone <remote> ~/code/<repo>
```

Worth recognising the failure: a bare `Permission denied (publickey)` for a key
that works perfectly under `ssh -i`, with the server side saying only
`Connection closed by authenticating user <you> ... [preauth]` — the client
never offered anything usable.

**Generate that key on the new machine; do not carry the old one over.** A key
that lived on a machine you no longer control should be treated as burned, and
rotation is only cheap if it happens at the moment a machine changes. The
awkward part is normally the chicken-and-egg — installing the new public key
usually requires authenticating with the old one, which means restoring the old
private key onto the new machine first, the one place it should never be. Any
identity-based route to the remote breaks that cycle: a mesh VPN with
identity-based SSH (Tailscale SSH and equivalents) authorises on account rather
than key material, so the new public key can be appended over it and the old
private key never exists on the new machine at all.

**Verify the new key against the route that actually uses it.** If the remote is
reachable both directly and over such a VPN, only the direct one consults
`authorized_keys`; the VPN path succeeds whether or not the key works. The
server's own auth log, which names the accepted fingerprint, is the check that
cannot lie to you.

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
| Does this repo own the machine, or install beside another setup? (see the modes in `setup/install.sh`) | `--mode` on the first run; recorded in `machine.local.env` |
| If it installs beside another setup: which tree is this setup's work in, and what suffix names its paths? | `LAYER_ROOT`, `LAYER_SUFFIX`, `MANAGED_BLOCK_PREFIX` in `profile.env` |
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

## 2b. Decide the mode, and what the layer is called

`./setup/install.sh --mode full` if this repo owns the machine;
`--mode layer` (the default) if another setup already owns `~/.zshrc`,
`~/.tmux.conf`, `~/.config/nvim` and the packages. Layer mode installs only
paths named by `LAYER_SUFFIX` plus namespaced blocks in files it does not own,
so the two installs are order-independent — but that guarantee is only as good
as the names: two instantiations that share a `LAYER_SUFFIX` or a
`MANAGED_BLOCK_PREFIX` will quietly overwrite each other.

Fill in `shell/bashrc-layer` while you are here — it is the shell environment
this setup adds, and it carries a `TODO(bootstrap)` marker for the aliases and
PATH entries that must work anywhere on the machine.

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
- Fill in `setup/agents/claude/CLAUDE.md`, the machine-wide instructions every
  session starts with. Answer the two `TODO(bootstrap)` markers in it: what this
  machine is and what happens to it unattended, and what every session should
  know before its first tool call. On a shared or always-on box this is the
  cheapest documentation in the repo — without it each session rediscovers the
  same facts, badly.
- Keep the generic skills (`experiments`, `dev-setup`, `restructure-commits`,
  `explore-agent`, `tmux-subtasks`, `proactive-run`). Add environment-specific
  ones — issue tracker, code review, deployment, the domain tools you use — as
  new directories in `setup/agents/skills/`, symlinked into both agents:
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
- [ ] `cla <name>` starts a session, `claude-panes list` shows it, and after
      `prefix + Ctrl-s` / `prefix + Ctrl-r` (or a real reboot) the window comes
      back with that conversation in it.
- [ ] `uv run pre-commit run --all-files` passes.
- [ ] Nothing secret is tracked: `git ls-files | grep -i -E 'secret|token|\.env$|\.pem$'`
      returns nothing but examples.

## 6. Delete this file

Once the repo is real, `BOOTSTRAP.md` is noise — its content has become the
README, `setup/README.md`, and the config files. Delete it and commit.
