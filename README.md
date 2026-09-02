# dev-setup-template

One repo that installs your entire development environment — shell, tmux,
editor, language tooling, ssh, coding agents — on every machine you work on,
and keeps them the same afterwards. This is the **template**: the shape,
with the specifics deliberately left out.

The problem it solves is not "set up a new laptop once". It is the slow
divergence afterwards: the alias that exists on one machine, the tmux binding
you fixed on the server and never brought home, the agent config that drifted
between two laptops, and the second setup you cannot install because the first
one owns `~/.zshrc`.

## What you get

**The same environment everywhere, from one command.** `./setup/install.sh`
brings a laptop or a shared Linux box to the same state, and every step is
idempotent, so re-running is a no-op when nothing changed. That is what makes it
the tool you *change* your environment with, not just the one you create it
with — `--only shell` after editing a config, and the change is live on every
machine after a `git pull`.

**Remote work is first class, not an afterthought.** mosh for connections that
survive sleep and network changes, tmux for sessions that survive disconnects, a
lemonade relay so copying inside a remote editor lands in the local clipboard,
and a systematic port-forwarding scheme so two people on one box never collide
and no port is ever picked by hand. Working on a remote machine feels the same
as working locally, which is the point.

**One shape, several setups.** The template is instantiated once per context —
a personal repo, a repo for each job — and they share their design without
sharing their contents. Nothing employer-specific ever enters the personal one;
nothing personal ever enters a work one; and a fix made in either can be carried
across deliberately, as a change you reviewed rather than a merge.

Two setups on **one machine** is the case this is really built for, because it
is where naive dotfile repos break: both want to own `~/.zshrc`, `~/.tmux.conf`,
`~/.config/nvim` and the agent config dirs, and whichever installs last wins.
`install.sh` has two modes. In **full** mode it owns the machine. In **layer**
mode it installs beside another setup — `~/.config/nvim-<suffix>`,
`~/.claude-<suffix>`, a managed block *appended* to `~/.zshrc`, a fragment in
`~/.ssh/config.d/` — and writes no path the other setup owns, so the two
installs are order-independent and either can be re-run at any time.

What makes that usable rather than merely non-destructive is
`${LAYER_ROOT}/.envrc`: entering this setup's tree points neovim and the coding
agents at its own configs, and leaving it restores the other setup's defaults.
Both keep their own agent logins and editor config, and neither is reconfigured
to accommodate the other. The mode is declared with `--mode` and remembered per
machine — never guessed from what happens to be installed, because a first run
on a half-set-up machine is exactly when guessing is least reliable and most
destructive.

**Config is symlinked, not copied.** `~/.claude`, `~/.pi`, `~/.tmux.conf`,
`~/.config/*` point into the repo, so editing a config *is* editing the repo,
and `git pull` on another machine is a config update. Nothing outside `setup/`
hard-codes a repo path, so the checkout can move.

**Three layers of configuration, and everything belongs to exactly one.**
Committed and shared (`profile.env`) → per-machine and gitignored
(`machine.local.env`) → secret and never committed (`secrets/env`). The
whitelist `.gitignore` means a new secret file cannot drift into git by
accident.

**Agent config is versioned like code.** Skills and prompts live once in
`setup/agents/skills/` and `setup/agents/prompts/`, symlinked into both Claude
Code and pi, so writing a skill once reaches both agents. Runtime state —
credentials, sessions, caches — is excluded by a whitelist.

**Skills encode the ways of working.** The rules for experiments, for the setup
itself, and for commit hygiene live as skills the agents load, not as folklore
you re-explain every session. When a rule changes it changes in one file, for
both agents.

**A team of agents is a repeatable setup, not an improvisation.** Handing one
goal to several agents for days — while you are away, or with you driving — has
a layout, an operating protocol, budget pacing, a recovery procedure for when
the session dies without taking the agents with it, and above all the
verification discipline that decides whether any of the output can be trusted.
The `proactive-run` skill carries all of it, and every rule in it was bought
with a failure.

**Work survives a reboot, agents included.** The tmux layout and the map from
agent session name to conversation are saved on a timer and replayed afterwards,
so a box that patches its own kernel overnight comes back with its windows — and
the conversations that were in them — rather than a blank server.

**Experiments are self-contained and dated.** Each has its own uv project, its
own README stating the question and the answer, and gitignored `data/` and
`screen_logs/`. They may duplicate each other freely; they must not import each
other.

## How to use it

**This template is not meant to be used as-is**, and not to be cloned as your
setup. It is instantiated: copied into a new repo, with its history dropped, and
then filled in for one concrete environment.

```bash
git clone <this repo> ~/code/dev-setup-template     # keep it; you will port to it
cp -r dev-setup-template ~/code/dev-setup-<context> # e.g. -personal, -<employer>
cd ~/code/dev-setup-<context>
rm -rf .git && git init && git add -A && git commit -m "chore: start from dev-setup-template"
```

Dropping `.git` is deliberate: each instantiation gets its own history and no
upstream link, so a work repo pushed to an employer's GitHub carries none of
your template's history, and the template never accumulates anyone's specifics.

Then work through **[BOOTSTRAP.md](BOOTSTRAP.md) with a coding agent**. It opens
with what has to exist on the machine before the repo can even be cloned, then
interviews you for the things that must not be guessed — machines, identity,
which repos you work in, which agents and models, how secrets reach a new
machine — and tells you what to fill in and what to delete. You are done when
this is empty:

```bash
grep -rn "TODO(bootstrap)\|TODO " --exclude-dir=.git .
```

Repeat for each context. One instantiation per job or persona; never merge two.

### Keeping them in sync

Changes flow **both ways**, and this is the part to be deliberate about, because
nothing enforces it:

- **generic fix → the template.** When you fix something in an instantiation
  that was wrong everywhere — a portability bug, a step that skipped instead of
  converging, a new invariant you paid for — port it to the template while the
  reasoning is still fresh. Ask the agent directly: *"port whatever belongs to
  dev-setup-template"*, and expect it to leave the specifics behind.
- **template improvement → each instantiation.** When the template gains
  something, ask an agent in each instantiation to port it forward.
- **specifics stay put.** Hostnames, employer names, personal paths, secrets,
  and anything only true of one environment never move to the template. If a
  change cannot be described without naming your machines, it is not generic
  yet — the generic half usually still exists underneath it.

An agent is the right tool here precisely because the two repos have diverged by
design: this is a translation, not a merge, and `git` cannot do it for you.

## What is in it

```text
setup/          one install.sh that sets up a machine end to end   → setup/README.md
experiments/    dated experiment folders and their conventions     → experiments/README.md
docs/tasks/     design/task notes for larger changes               → docs/tasks/README.md
scripts/        repo-wide tooling used by pre-commit
```

`setup/README.md` is worth reading before changing anything under `setup/`: it
carries the invariants that keep re-running safe, each one written down because
breaking it cost something.

## Quick tour after instantiating

```bash
./setup/install.sh --list-steps   # what the installer will do
./setup/install.sh                # do it
conn --tmux gpu-01                # connect: tunnel + tmux, clipboard works
```

## License

MIT — see [LICENSE](LICENSE).
