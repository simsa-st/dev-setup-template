# setup/

One entry point installs a whole machine:

```bash
./setup/install.sh                    # auto-detects macos | linux
./setup/install.sh --target linux     # force the target
./setup/install.sh --only shell,tmux  # re-run a subset after editing config
./setup/install.sh --skip nvim
./setup/install.sh --list-steps
```

Steps run in this order, each one a `step_<name>` function in `lib/`:

| Step | What it does |
|---|---|
| `preflight` | load `config/profile.env`, check zsh/git/python3 |
| `packages` | Homebrew formulae (macOS) or user-local release binaries (Linux) |
| `shell` | oh-my-zsh + p10k, `~/.config` symlinks, managed `~/.zshrc` header |
| `tmux` | tpm + `tmux.conf` symlink |
| `git` | render `~/.config/git/config` from the profile |
| `tools` | uv, node/nvm, repo pre-commit hook |
| `nvim` | bob + the pinned neovim, clone/symlink the config repo |
| `agents` | Claude Code and pi: install binaries, symlink config into `$HOME` |
| `sessions` | timer that saves the tmux layout and the agent name map |
| `clipboard` | lemonade server (macOS) or client + host IP (Linux) |
| `ssh` | generate `~/.ssh/config` and port forwards from `hosts.toml` |
| `finish` | print what to run next |

## Invariants

These are what make the setup re-runnable and portable; break one and reruns
start corrupting dotfiles.

1. **Idempotent.** Re-running any step must be a no-op when nothing changed.
   Never append to a user-owned file: symlink the repo file, or rewrite a
   `# BEGIN/END DEVSETUP_<name>` managed block (`managed_block` in
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
3. **Refuse the wrong environment before doing anything.** Validate the target
   and the arguments at the very top of an entry point, above any step that
   relocates, clones or writes — a guard below such a step cannot undo what it
   did.
4. **No repo paths in dotfiles.** `~/.zshrc` references `~/.config/...` only.
   Moving the checkout re-points symlinks; it does not edit `$HOME`.
5. **Back up before replacing.** Anything real that a symlink would overwrite is
   moved to `~/dev-setup-backups/<timestamp>/` (`link`, `backup_path`).
6. **No root on Linux.** Shared machines are installed user-locally into
   `~/.config/bin`. If a step needs `sudo`, it belongs on macOS only.
7. **Layered configuration.** `config/profile.env` (committed, same everywhere)
   → `config/machine.local.env` (gitignored, per machine) → `config/secrets/env`
   (gitignored, never committed).
8. **Install files, not session state.** A step that mutates something living in
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
│   ├── shell/                  bashrc-extra (env, PATH, aliases), zshrc-base.zsh
│   ├── tmux/tmux.conf
│   ├── git/config.template
│   ├── ssh/hosts.toml(.example), custom-forwards
│   ├── systemd/, launchd/      unit templates for the persistence timer
│   ├── bin/                    symlinked into ~/.config/bin (on PATH)
│   └── secrets/                gitignored; see its README
└── agents/
    ├── skills/             shared skills, symlinked into both agents
    ├── prompts/            shared prompts / slash commands
    ├── claude/             becomes ~/.claude
    └── pi/                 becomes ~/.pi
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
