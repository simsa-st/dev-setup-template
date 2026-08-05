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
2. **No repo paths in dotfiles.** `~/.zshrc` references `~/.config/...` only.
   Moving the checkout re-points symlinks; it does not edit `$HOME`.
3. **Back up before replacing.** Anything real that a symlink would overwrite is
   moved to `~/dev-setup-backups/<timestamp>/` (`link`, `backup_path`).
4. **No root on Linux.** Shared machines are installed user-locally into
   `~/.config/bin`. If a step needs `sudo`, it belongs on macOS only.
5. **Layered configuration.** `config/profile.env` (committed, same everywhere)
   → `config/machine.local.env` (gitignored, per machine) → `config/secrets/env`
   (gitignored, never committed).

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
│   └── clipboard.sh        lemonade + ssh config
├── config/
│   ├── profile.env(.example)   identity, pinned versions, ports
│   ├── shell/                  bashrc-extra (env, PATH, aliases), zshrc-base.zsh
│   ├── tmux/tmux.conf
│   ├── git/config.template
│   ├── ssh/hosts.toml(.example), custom-forwards
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
