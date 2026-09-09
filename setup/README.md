# setup/

One entry point installs a whole machine:

```bash
./setup/install.sh                    # auto-detects macos | linux; layer mode
./setup/install.sh --mode full        # this repo owns the machine; remembered
./setup/install.sh --target linux     # force the target
./setup/install.sh --only shell,tmux  # re-run a subset after editing config
./setup/install.sh --skip nvim
./setup/install.sh --list-steps       # annotated with what this mode skips
```

## Two modes

**`full`** — this repo owns the machine. Packages, zsh, tmux, git, uv/node, and
the editor and agent configs at their canonical paths (`~/.config/nvim`,
`~/.claude`, `~/.pi`).

**`layer`** (the default) — another setup owns the base: a work dotfiles repo,
or a second instantiation of this template. This install then adds only its own
layer beside it, and touches nothing the other setup writes:

| Full mode writes | Layer mode writes instead |
|---|---|
| `~/.config/nvim` | `~/.config/nvim-<suffix>` |
| `~/.claude`, `~/.pi` | `~/.claude-<suffix>`, `~/.pi-<suffix>` |
| `~/.zshrc` header block (top) | `~/.zshrc` layer block (appended) |
| `~/.ssh/config` | `~/.ssh/config.d/<suffix>-hosts` |
| `~/.config/git/config` | `~/.gitconfig` includeIf → `~/.config/git/config-<suffix>` |
| the packages, zsh and tmux config themselves | nothing — they are the other setup's |

`<suffix>` is `LAYER_SUFFIX` from `profile.env`, and `MANAGED_BLOCK_PREFIX`
namespaces the blocks. Two instantiations sharing a machine **must** differ in
both, or each install silently overwrites the other's work.

The switch between them is `${LAYER_ROOT}/.envrc`: entering this setup's tree
exports `NVIM_APPNAME`, `CLAUDE_CONFIG_DIR`, `PI_CODING_AGENT_DIR` and
`DEV_HOSTS_FILE` for the layer, and leaving it restores the other setup's
defaults. Git identity is scoped to the same tree, but by `includeIf` rather
than by the environment, because git is also invoked by things that never see a
direnv-exported variable. That is what lets
both setups keep their own agent logins and editor config without either being
reconfigured; `shell/bashrc-layer` carries the aliases that reach the same tools
from outside the tree.

Because layer mode writes only paths the other setup never touches, the two
installs are **order-independent** and either can be re-run at any time. That
property is the whole point, and it is the one to check when adding a step.

Steps run in this order, each one a `step_<name>` function in `lib/`:

| Step | Mode | What it does |
|---|---|---|
| `preflight` | both | load `config/profile.env`, check zsh/git/python3 |
| `packages` | full | Homebrew formulae (macOS) or user-local release binaries (Linux) |
| `shell` | full | oh-my-zsh + p10k, `~/.config` symlinks, managed `~/.zshrc` header |
| `tmux` | full | tpm + `tmux.conf` symlink |
| `git` | both | full: render `~/.config/git/config`; layer: an `includeIf` in `~/.gitconfig` giving `${LAYER_ROOT}` this identity |
| `tools` | full | uv, node/nvm, repo pre-commit hook |
| `nvim` | both | clone/symlink the config repo; full mode also installs neovim and the tree-sitter CLI |
| `agents` | both | symlink agent config; full mode also installs the binaries |
| `env` | both | `bashrc-layer`, the `~/.zshrc` block, `${LAYER_ROOT}/.envrc` |
| `sessions` | full | timer that saves the tmux layout and the agent name map |
| `clipboard` | full | lemonade server (macOS) or client + host IP (Linux) |
| `ssh` | both | hosts from `hosts.toml`: whole config, or a `config.d` fragment |
| `finish` | both | print what to run next |

## Invariants

These are what make the setup re-runnable and portable; break one and reruns
start corrupting dotfiles.

1. **Idempotent.** Re-running any step must be a no-op when nothing changed.
   Never append to a user-owned file: symlink the repo file, or rewrite a
   `# BEGIN/END <MANAGED_BLOCK_PREFIX>_<name>` managed block (`managed_block` in
   `lib/common.sh`).
2. **Converge, do not skip.** "Already present, leaving it alone" is not
   idempotence — it makes a step incapable of ever fixing a stale value. Compare
   against the value the step wants and rewrite when they differ. A
   presence-only check on a credentials file is how a rotated token keeps
   failing on every machine that already had the old one.

   This applies just as much to state held *outside* the machine — an ssh key
   or a firewall rule stored in a cloud provider's account, addressed by name.
   Existence-by-name is especially tempting there because the API makes it a
   one-liner, and especially dangerous because nothing local shows the drift:
   an entry a step created once and never checked again will happily hand a
   rebuilt machine a credential that was deliberately retired.
3. **In layer mode, stay out of the other setup's files.** Every path a step
   writes must be one the base setup never touches. Adding a step that writes
   `~/.zshrc`'s header, `~/.tmux.conf`, `~/.config/bin/*` or `~/.ssh/config`
   in layer mode makes install order matter again, and order-independence is
   the property that makes two setups on one machine survivable at all.
4. **Mode is declared, not detected.** Guessing from what happens to be
   installed makes a first run on a half-set-up machine take over files it
   should not — and a first run is exactly when the evidence for guessing is
   weakest. `--mode` is explicit and recorded in `machine.local.env`.
5. **A step that stops applying must undo itself.** A machine can be switched
   from layer to full. A step that only ever adds leaves the layer's managed
   block behind forever; `remove_managed_block` is the other half.
6. **Refuse the wrong environment before doing anything.** Validate the target
   and the arguments at the very top of an entry point, above any step that
   relocates, clones or writes — a guard below such a step cannot undo what it
   did.
7. **No repo paths in dotfiles.** `~/.zshrc` references `~/.config/...` only.
   Moving the checkout re-points symlinks; it does not edit `$HOME`.
8. **Back up before replacing.** Anything real that a symlink would overwrite is
   moved to `~/dev-setup-backups/<timestamp>/` (`link`, `backup_path`).
9. **Never require root on Linux.** The difference that matters is not the
   distro but whether you own the box: a shared machine has no sudo, and
   everything has to land user-locally in `~/.config/bin`. A step may *use*
   passwordless sudo when it is there — that is how a machine you own gets its
   apt packages — but it must detect that (`sudo -n true`), never prompt, and
   degrade to a warning rather than a failure when it is absent.
10. **Layered configuration.** `config/profile.env` (committed, same everywhere)
   → `config/machine.local.env` (gitignored, per machine) → `config/secrets/env`
   (gitignored, never committed).
11. **Install files, not session state.** A step that mutates something living in
   the current login — an ssh-agent, a running daemon's in-memory config, an
   exported variable — has nothing to converge on and no effect that survives a
   logout, and it usually wants to prompt. `ssh-add --apple-use-keychain` is the
   recurring example; the config file equivalents (`AddKeysToAgent`,
   `UseKeychain`) belong in the repo, the `ssh-add` does not.

## Layout

```text
setup/
├── install.sh              entry point: arg parsing, target detection, step order
├── lib/
│   ├── common.sh           logging, symlink/backup, managed blocks, profile loading
│   ├── packages.sh         brew list / user-local release binaries
│   ├── shell.sh            zsh, tmux, git
│   ├── tools.sh            uv, node, neovim
│   ├── agents.sh           Claude Code + pi
│   ├── sessions.sh         save/restore tmux + agent sessions across reboots
│   └── clipboard.sh        lemonade + ssh config
├── config/
│   ├── profile.env(.example)   identity, pinned versions, ports
│   ├── shell/                  bashrc-extra (full mode), bashrc-layer (layer)
│   ├── tmux/tmux.conf
│   ├── git/config.template
│   ├── ssh/hosts.toml(.example), custom-forwards
│   ├── systemd/, launchd/      unit templates for the persistence timer
│   ├── bin/                    symlinked into ~/.config/bin (on PATH)
│   └── secrets/                gitignored; see its README
└── agents/
    ├── skills/             shared skills, symlinked into both agents
    ├── prompts/            shared prompts / slash commands
    ├── claude/             becomes ~/.claude-<suffix> (and ~/.claude in full mode)
    └── pi/                 becomes ~/.pi-<suffix> (and ~/.pi in full mode)
```

## Helper scripts (`config/bin`, on `PATH`)

| Command | Purpose |
|---|---|
| `conn [--tmux] [--mosh] [--fwd] <host>` | connect, with clipboard tunnel and optional tmux/mosh |
| `hosts resolve\|list\|ssh-config` | the machine table: aliases and generated SSH config |
| `clipboard-copy` | stdin → local clipboard from anywhere (pbcopy → lemonade → OSC 52) |
| `lemonade-server`, `lemonade-tunnel`, `lemonade-relay` | the clipboard path |
| `tmux-say <tmux-target> <text>` | say something to an agent in another window |
| `claude-pane <name> [args]` | start/resume a Claude session under a stable Remote Control name |
| `claude-panes sync\|restore\|list\|bind\|forget` | the name → conversation map behind it |
| `resume-agent <delay> <tmux-target> [text]` | poke a waiting agent later |

## Clipboard

```text
remote nvim/tmux ──▶ lemonade-relay ──▶ reverse SSH tunnel ──▶ lemonade server ──▶ macOS clipboard
   (remote host)      0.0.0.0:64011        localhost:64010         localhost:2489
```

`conn` starts the server and refreshes the tunnel on every connect, and the
tunnel command ensures the remote relay is up. The relay exists because the
tunnel binds loopback only, which processes in other namespaces cannot reach.
tmux yanks pipe through `clipboard-copy`, whose lemonade hop is what makes copy
work over mosh < 1.4 (it drops OSC 52).

## Sessions that survive a reboot

```text
tmux-persist (timer, every 2 min)
   ├─▶ claude-panes sync   name → conversation map   ~/.local/state/claude-panes
   └─▶ resurrect save.sh   windows, layouts, cwds    ~/.local/share/tmux/resurrect
                                                              │
                       reboot ──▶ continuum restore ──────────┘
                                        └─▶ claude-panes restore ──▶ claude-pane <name>
```

A restored pane is only useful if what was running in it comes back too, and a
pane's command line (`claude`) does not say which conversation that was. So the
name is declared up front — `claude-pane <name>` — and the map from name to
conversation is saved alongside the layout.

Three things about this were found the hard way and are worth not rediscovering:

- **Continuum cannot do the saving here.** Its periodic save is driven from
  `status-right`, which tmux evaluates only for an *attached* client, and its
  `@continuum-boot` unit saves on shutdown only for a server it started itself.
  A box that reboots while nobody is attached would never save. Hence the timer.
- **resurrect's `save.sh` must run through `tmux run-shell`.** Called directly
  from a scheduler it uses bare `tmux`, finds only the default socket, writes a
  zero-byte save file over the good one, and exits 0.
- **`@resurrect-processes` cannot restore an agent TUI.** It sends the command
  the instant it creates the pane, and a zsh still sourcing its startup files
  swallows the line without a trace. `claude-panes restore` waits for an idle
  prompt, sends, and confirms the process is up.

## An always-on box

Sooner or later one of the machines this repo installs is a server rather than a
laptop — a VPS, a cloud dev box — and it grows services nothing else needs: a
sync daemon, a mesh VPN, a backup timer, a reverse proxy. Put those in their own
`lib/box.sh` with a full-mode-only step, so the laptops never evaluate them, and
keep the rules below. Each one is cheap to follow and was expensive to learn.

**User units, not system units.** `~/.config/systemd/user` sits inside the home
directory a backup already copies, so a rebuilt box gets its services back with
its files. `/etc/systemd/system` would not be in that backup, and nothing would
tell you until the rebuild.

**Lingering is the point.** Nobody stays logged in to a server, and without
`loginctl enable-linger` a user unit lives exactly as long as one ssh session —
so the timer works perfectly while you watch it and stops the moment you leave.

**Unit files are copied, never symlinked.** `systemctl reenable` is
disable-then-enable, and `disable` *deletes* a unit file that is a symlink: it
reads it as a `systemctl link` and unlinks it. A step that symlinks its units
removes the unit it just installed and then fails on it. (`lib/sessions.sh`
already does this correctly — copy its shape.)

**Quote every `Environment=` value.** systemd splits that line on whitespace, so
a value containing a space is accepted and then silently dropped with `Invalid
environment assignment, ignoring: <second word>`. A commit identity is the
usual victim, and the unit runs on with an empty variable.

**A unit that points into `~/.config/bin` depends on a step that can be
skipped.** `--only <that step>` on a fresh machine installs the unit without the
script it executes; systemd reports `203/EXEC` and launchd reports nothing at
all. Link the script from the step that installs the unit as well, not only from
the step that owns `config/bin`.

**Install the daemon; leave the join to a human.** For anything that
authenticates against an account — a VPN, a sync mesh — the step should stop at
"running and configured". Joining is per-device state, and automating it means
storing a long-lived credential on the box to save one command. Where that state
lives also decides what a rebuild costs: inside the home directory it comes back
with the backup, outside it (`/var/lib/...`) it must be re-authenticated
regardless, which is the honest reason to leave it manual.

**Converge on the contents of a package sources list, not on the file
existing.** The first version of one such check looked for the distro codename
as `/noble` where the line actually reads `... /ubuntu noble main`, so it
re-added the repository on every single run. A step that always does the work is
as broken as one that never does — it just fails quietly instead of loudly.

**The scripts that create and destroy the box belong in `setup/bin/`**, and they
follow invariant 2 like everything else. Three things worth building in from the
start:

- **rules are replaced, not added to.** Firewall rules, tags, and anything else
  the provider stores as a list should be declared in the script and applied
  wholesale each run. Create-time-only rules mean a port decided on later gets
  opened by hand in a console and then exists nowhere in the repo.
- **anything addressed by name needs a content check.** An ssh key or a security
  group whose *name* exists is not one whose *contents* are current; that is
  invariant 2 applied to the provider's API, and it is where a rotated
  credential comes back from the dead on the next rebuild.
- **a teardown script must refuse to tear down the machine it is running on.**
  Compare the target's address against the local interfaces before anything
  destructive runs. This becomes reachable the moment the provider's CLI is
  installed *on* the box, which is exactly when it stops being hypothetical.

## Agents

Both agents keep their entire config directory in this repo (`~/.claude` and
`~/.pi` are symlinks into `setup/agents/`), so settings, skills and prompts are
versioned and identical on every machine. Runtime state is excluded by a
whitelist `.gitignore` in each, so new runtime files never land in git by
accident.

Skills live once in `agents/skills/` and are symlinked into both agents' skill
directories; write a skill once and both see it. Shared prompts in
`agents/prompts/` are exposed as pi prompts and Claude Code slash commands the
same way. Agent-specific skills go directly in that agent's `skills/` dir.

Note the one incompatibility: pi prompts interpolate `$@`, Claude Code commands
use `$ARGUMENTS`. Shared prompts avoid both and state their target in prose.

`agents/claude/CLAUDE.md` becomes `~/.claude/CLAUDE.md`: the machine-wide
instructions every session on this box starts with. It is for what is true of
the *machine* rather than of a repo — the private tmux socket, how to read and
talk to another session, that an overnight reboot is scheduled rather than a
crash. Per-repo instructions stay in that repo's own `CLAUDE.md`.

`agents/claude/statusline.sh` renders the status line and, as a side effect,
writes the subscription rate-limit numbers to `/tmp/claude-rate-limits*.json`.
That snapshot is the only programmatic access to those numbers, and it is what
lets an unattended run pace its own budget (the `proactive-run` skill).
