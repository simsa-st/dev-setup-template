# dev-setup-template

A skeleton for a personal "setup + experiments" repo: one repo that installs
your whole development environment on every machine you use, and holds the dated
experiments you run there.

**This template is not meant to be used as-is.** It is a shape to follow, with
the specifics — which machines, which projects, which secrets, which agent
models — deliberately left out, because those are only known once you are
setting up a concrete environment. Work through [BOOTSTRAP.md](BOOTSTRAP.md)
with a coding agent to turn it into a real repo; it lists what to ask, what to
fill in, and what to delete.

## What is in it

```text
setup/          one install.sh that sets up a machine end to end   → setup/README.md
experiments/    dated experiment folders and their conventions     → experiments/README.md
docs/tasks/     design/task notes for larger changes               → docs/tasks/README.md
scripts/        repo-wide tooling used by pre-commit
```

## The ideas worth keeping

**One repo, one command, every machine.** `./setup/install.sh` brings a laptop
or a shared Linux box to the same state. Steps are idempotent and individually
runnable (`--only shell`), so it stays useful long after day one — it is how you
change your environment, not just how you create it.

**Config is symlinked, not copied.** `~/.claude`, `~/.pi`, `~/.tmux.conf`,
`~/.config/*` point into the repo, so editing a config *is* editing the repo,
and `git pull` on another machine is a config update. Nothing outside `setup/`
hard-codes a repo path, so the checkout can move.

**Three layers of configuration.** Committed and shared (`profile.env`) →
per-machine and gitignored (`machine.local.env`) → secret and never committed
(`secrets/env`). Everything belongs to exactly one layer.

**Agent config is versioned like code.** Skills and prompts live once in
`setup/agents/skills/` and `setup/agents/prompts/`, symlinked into both Claude
Code and pi. Runtime state is excluded by a whitelist so credentials and session
logs cannot drift into git.

**Skills encode the ways of working.** The rules for experiments, for the setup
itself, and for commit hygiene live as skills the agents load, not as folklore.
When a rule changes, it changes in one file for both agents.

**A team of agents is a repeatable setup, not an improvisation.** Handing one
goal to several agents for days — while you are away, or with you driving —
has a layout, an operating protocol, budget pacing, a recovery procedure for
when the session dies without taking the agents with it, and above all the
verification discipline that decides whether any of the output can be trusted.
The `proactive-run` skill carries all of it, and every rule in it was bought
with a failure.

**Experiments are self-contained and dated.** Each has its own uv project, its
own README with the question and the answer, and gitignored `data/` and
`screen_logs/`. They may duplicate each other freely; they must not import each
other.

**Remote work is first class.** mosh for connections that survive sleep and
network changes, tmux for sessions that survive disconnects, a lemonade relay so
copying in a remote editor lands in the local clipboard, and a systematic
port-forwarding scheme so ports never need to be picked by hand.

**Work survives a reboot, agents included.** The tmux layout and the map from
agent session name to conversation are saved on a timer and replayed afterwards,
so a box that patches its own kernel overnight comes back with its windows — and
the conversations that were in them — rather than a blank server.

## Quick tour after instantiating

```bash
./setup/install.sh --list-steps   # what the installer will do
./setup/install.sh                # do it
conn --tmux gpu-01                # connect: tunnel + tmux, clipboard works
```
