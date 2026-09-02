#!/usr/bin/env bash
# Shared helpers. Sourced by install.sh, never executed directly.

BACKUP_DIR="${HOME}/dev-setup-backups/$(date +%Y-%m-%d_%H-%M-%S)"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"

log() { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxxx\033[0m %s\n' "$*" >&2; exit 1; }

list_contains() { # <comma-list> <needle>
  case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" > /dev/null 2>&1; }

backup_dir() {
  mkdir -p "${BACKUP_DIR}"
  chmod 700 "${BACKUP_DIR}"
  printf '%s' "${BACKUP_DIR}"
}

# Back up a real file/dir before it gets replaced by a symlink or generated copy.
backup_path() { # <path>
  local path="$1"
  [ -e "${path}" ] || return 0
  [ -L "${path}" ] && return 0
  local dest
  dest="$(backup_dir)/$(basename "${path}")"
  log "backing up ${path} -> ${dest}"
  mv "${path}" "${dest}"
}

# Symlink repo config into place, backing up anything real that sits there.
link() { # <source> <destination>
  local src="$1" dst="$2"
  [ -e "${src}" ] || die "link source missing: ${src}"
  mkdir -p "$(dirname "${dst}")"
  backup_path "${dst}"
  ln -sfn "${src}" "${dst}"
}

# setup/config/bin/hosts parses hosts.toml with tomllib, which is 3.11+. macOS
# ships 3.9, and Homebrew's python@3.x links only the versioned name, so a
# fresh Mac has no usable `python3` however many pythons are installed. `conn`
# calls that script at runtime, not just the installer, so the fix has to
# outlive the install: a symlink in ~/.config/bin, which bashrc-extra puts
# first on PATH. No-op wherever python3 is already new enough.
ensure_modern_python3() {
  python3 -c 'import tomllib' 2> /dev/null && return 0
  local candidate
  for candidate in python3.14 python3.13 python3.12 python3.11; do
    if have "${candidate}" && "${candidate}" -c 'import tomllib' 2> /dev/null; then
      log "linking ${candidate} as ${XDG_CONFIG_HOME}/bin/python3 (system python3 lacks tomllib)"
      link "$(command -v "${candidate}")" "${XDG_CONFIG_HOME}/bin/python3"
      hash -r
      return 0
    fi
  done
  warn "no python3 with tomllib (3.11+); setup/config/bin/hosts and conn cannot run."
}

# Set `<key><sep><value>` in a config file, converging rather than appending.
# Most "add this line to your ~/.npmrc" instructions use `>>`, which duplicates
# the line on every run; a setup step has to be safe to re-run, so this rewrites
# an existing key in place and only appends when the key is genuinely absent.
# Never rewrites the rest of the file -- ~/.npmrc can hold registry auth.
ensure_config_line() { # <file> <key> <sep> <value> [<header>]
  python3 - "$1" "$2" "$3" "$4" "${5:-}" <<'CFG_PY'
from pathlib import Path
import re, sys

path, key, sep, value, header = (Path(sys.argv[1]), *sys.argv[2:6])
path.parent.mkdir(parents=True, exist_ok=True)
text = path.read_text() if path.exists() else ""
line = f"{key}{sep}{value}"
pattern = re.compile(rf"^\s*{re.escape(key)}\s*{re.escape(sep.strip())}\s*.*$", re.M)
if pattern.search(text):
    new = pattern.sub(line, text, count=1)
else:
    if header and header not in text:
        text = (text.rstrip("\n") + "\n" if text else "") + header + "\n"
    new = (text.rstrip("\n") + "\n" if text else "") + line + "\n"
if new != text:
    path.write_text(new)
CFG_PY
}

version_ge() { # <have> <want>
  python3 - "$1" "$2" <<'PY'
import re, sys
parts = lambda v: [int(p) for p in re.split(r"[.+-]", v) if p.isdigit()]
sys.exit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PY
}

# Converge a git checkout this repo owns but does not track: the oh-my-zsh
# plugins and the neovim config repo.
#
# The symlink case is not hypothetical. Two instantiations sharing a machine
# reach this with the *same* destination path, and the loser gets a symlink
# into the winner's checkout -- at which point `git -C <dir> pull` would
# fast-forward the other install's repository from this install's remote. So a
# symlink here is dropped and re-cloned rather than followed.
#
# A failed pull warns rather than passing silently: a checkout stuck on an old
# commit because it has local changes is exactly the drift this function exists
# to remove, and nothing else reports it.
clone_or_pull() { # <url> <dir>
  if [ -L "$2" ]; then
    rm -f "$2"
  fi
  if [ -d "$2/.git" ]; then
    git -C "$2" pull --quiet --ff-only || warn "could not fast-forward $2; leaving it as is"
  else
    git clone --depth=1 "$1" "$2"
  fi
}

# Rewrite a `# BEGIN/END <prefix>_<name>` block in a file, creating it if absent.
# This is what keeps re-runs idempotent instead of appending a second copy.
#
# The position matters and is not cosmetic. A block this repo owns is appended
# by default, so a *base* setup's header — and p10k's instant prompt, which has
# to stay near the top of ~/.zshrc — is not pushed down by a layer installed
# afterwards. Pass "top" only for a block that must precede everything else in
# the file; ~/.ssh/config's Include is the one real case, because an Include
# placed after the first Host line stops being global.
#
# The prefix is namespaced (MANAGED_BLOCK_PREFIX, from profile.env) because two
# instantiations of this template can share a machine, and two blocks both
# called DEVSETUP_SHELL in one ~/.zshrc would silently overwrite each other.
managed_block() { # <file> <name> <content-file> [top|bottom]
  python3 - "$1" "$2" "$3" "${4:-bottom}" "${MANAGED_BLOCK_PREFIX:-DEVSETUP}" <<'BLOCK_PY'
from pathlib import Path
import sys

path, name, content_path = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
where, prefix = sys.argv[4], sys.argv[5]
begin, end = f"# BEGIN {prefix}_{name}", f"# END {prefix}_{name}"
content = content_path.read_text()
if content and not content.endswith("\n"):
    content += "\n"
block = f"{begin}\n{content}{end}\n"

# The file's directory may not exist yet (~/.aws on a fresh box), and touch()
# raises rather than creating it. link() already does this; this did not.
path.parent.mkdir(parents=True, exist_ok=True)
path.touch()
text = path.read_text()
start, stop = text.find(begin), text.find(end)
if start != -1 and stop != -1 and stop > start:
    # Re-separate from whatever follows with exactly one blank line, matching
    # what the insert path below writes. Without this the replace path strips a
    # separator the insert path added, so the *second* run of the installer
    # still changes the file -- which is precisely the idempotence claim.
    rest = text[stop + len(end):].lstrip("\n")
    path.write_text(text[:start] + block + (f"\n{rest}" if rest else ""))
elif where == "top":
    rest = text.lstrip("\n")
    path.write_text(block + (f"\n{rest}" if rest else ""))
else:
    # The blank line is a *separator*, so an empty file gets none. Emitting one
    # anyway left every file this function creates starting with a blank line,
    # which is merely ugly until something else normalises the file -- and then
    # the run after that is a diff, which is the idempotence claim again.
    if text and not text.endswith("\n"):
        text += "\n"
    path.write_text(f"{text}\n{block}" if text else block)
BLOCK_PY
}

# Remove a managed block entirely. A step that stops applying to the current
# mode has to *undo* itself: switching a machine from layer to full would
# otherwise leave the layer's block in ~/.zshrc forever.
remove_managed_block() { # <file> <name>
  [ -f "$1" ] || return 0
  python3 - "$1" "$2" "${MANAGED_BLOCK_PREFIX:-DEVSETUP}" <<'UNBLOCK_PY'
from pathlib import Path
import sys

path, name, prefix = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
begin, end = f"# BEGIN {prefix}_{name}", f"# END {prefix}_{name}"
text = path.read_text()
start, stop = text.find(begin), text.find(end)
if start != -1 and stop != -1 and stop > start:
    path.write_text(text[:start].rstrip("\n") + "\n" + text[stop + len(end):].lstrip("\n"))
UNBLOCK_PY
}

MACHINE_LOCAL_ENV="${DEV_SETUP_DIR}/config/machine.local.env"

# --- mode ----------------------------------------------------------------
# layer vs full is a property of the machine, and it is *declared*, never
# guessed from what happens to be installed: a wrong guess on a half-set-up
# machine makes this repo take over files another setup owns, and a first run is
# exactly when the evidence for guessing is weakest.
#
#   full   this repo owns the machine: packages, zsh, tmux, git, and the agent
#          and editor configs at their canonical paths (~/.claude,
#          ~/.config/nvim).
#   layer  another setup owns the base. This repo installs only beside it —
#          ~/.claude-<suffix>, ~/.config/nvim-<suffix>, a managed block appended
#          to ~/.zshrc, a fragment under ~/.ssh/config.d — and writes nothing the
#          other setup owns, so the two installs are order-independent and both
#          stay re-runnable.
#
# --mode is sticky: it is recorded in machine.local.env (gitignored), so a
# machine is told once and stays told.
resolve_mode() { # [<mode-from-cli>]
  local requested="${1:-}"
  DEVSETUP_MODE=""
  [ -f "${MACHINE_LOCAL_ENV}" ] && DEVSETUP_MODE=$(
    # shellcheck disable=SC1090
    source "${MACHINE_LOCAL_ENV}"; printf '%s' "${DEVSETUP_MODE:-}"
  )
  if [ -n "${requested}" ]; then
    DEVSETUP_MODE="${requested}"
    mkdir -p "$(dirname "${MACHINE_LOCAL_ENV}")"
    touch "${MACHINE_LOCAL_ENV}"
    python3 - "${MACHINE_LOCAL_ENV}" "${requested}" <<'MODE_PY'
from pathlib import Path
import re, sys

path, mode = Path(sys.argv[1]), sys.argv[2]
lines = [l for l in path.read_text().splitlines() if not re.match(r"\s*DEVSETUP_MODE=", l)]
lines.append(f'DEVSETUP_MODE="{mode}"')
path.write_text("\n".join(lines).lstrip("\n") + "\n")
MODE_PY
  fi
  DEVSETUP_MODE="${DEVSETUP_MODE:-layer}"
  case "${DEVSETUP_MODE}" in
    layer | full) ;;
    *) die "Unknown mode '${DEVSETUP_MODE}' (expected layer or full)." ;;
  esac
  export DEVSETUP_MODE
}

# Adopt an agent's existing config directory into the repo before a symlink
# replaces it, so an existing login and its settings survive the switch instead
# of being backed up into a directory nobody opens again.
adopt_existing_agent_dir() { # <existing-path> <repo-dir>
  local existing="$1" repo_dir="$2"
  [ -e "${existing}" ] || return 0
  [ -L "${existing}" ] && return 0
  log "adopting existing ${existing} into ${repo_dir}"
  mkdir -p "${repo_dir}"
  cp -a "${existing}/." "${repo_dir}/"
  backup_path "${existing}"
}

# Make ~/.ssh/config.d/* reachable without owning ~/.ssh/config. A no-op when
# something already provides an Include, which is the normal case once a base
# setup has generated that file.
ensure_ssh_config_include() {
  local config="${HOME}/.ssh/config"
  if [ -f "${config}" ] && grep -qE '^[[:space:]]*Include[[:space:]]+.*\.ssh/config\.d/' "${config}"; then
    return 0
  fi
  local snippet
  snippet=$(mktemp)
  printf 'Include ~/.ssh/config.d/*\n' > "${snippet}"
  managed_block "${config}" "SSH_INCLUDE" "${snippet}" top
  rm -f "${snippet}"
  chmod 600 "${config}"
}

# Values that differ per person (identity, nvim config repo, ports) live in
# config/profile.env, committed once the template is instantiated. Per-machine
# overrides live in config/machine.local.env, which is gitignored.
#
# The LAYER_* values below are consumed by lib/{agents,shell,tools}.sh and are
# exported anyway by the enclosing `set -a`. shellcheck models neither the
# sourcing boundary nor allexport, so it flags all five as unused; the directive
# is function-scoped rather than per-line because a bare one covers only the
# next command.
# shellcheck disable=SC2034
load_profile() {
  local profile="${DEV_SETUP_DIR}/config/profile.env"
  [ -f "${profile}" ] || die "Missing ${profile} — copy profile.env.example and fill it in (see BOOTSTRAP.md)."
  set -a
  # shellcheck disable=SC1090
  source "${profile}"
  # shellcheck disable=SC1090
  [ -f "${MACHINE_LOCAL_ENV}" ] && source "${MACHINE_LOCAL_ENV}"

  # Everything this repo installs in layer mode is named by one suffix, so its
  # paths cannot collide with the base setup's, nor with a second instantiation
  # of this template on the same machine.
  LAYER_SUFFIX="${LAYER_SUFFIX:-personal}"
  LAYER_NVIM_APPNAME="nvim-${LAYER_SUFFIX}"
  LAYER_NVIM_DIR="${XDG_CONFIG_HOME}/nvim-${LAYER_SUFFIX}"
  LAYER_CLAUDE_DIR="${HOME}/.claude-${LAYER_SUFFIX}"
  LAYER_PI_DIR="${HOME}/.pi-${LAYER_SUFFIX}"
  LAYER_BASHRC="${XDG_CONFIG_HOME}/.bashrc-${LAYER_SUFFIX}"
  set +a
}

step_preflight() {
  load_profile
  # Only things this installer cannot install for you. zsh is deliberately NOT
  # here: it is a *target*, installed by step_packages, and preflight runs
  # first -- so requiring it here makes a fresh Linux box impossible to set up,
  # dying before the step that would have fixed it. step_shell checks it, which
  # is both after packages and the place that actually needs it.
  have git || die "git is required; install it first."
  have curl || die "curl is required; install it first."
  have python3 || die "python3 is required; install it first."
  mkdir -p "${XDG_CONFIG_HOME}/bin"

  # Git records only the executable bit, so a fresh clone -- or a file written
  # under a loose umask -- leaves secrets/env group- and world-readable. The
  # modes are re-enforced on every run rather than at creation time, because the
  # file that matters is usually the one somebody added by hand afterwards.
  local secrets="${DEV_SETUP_DIR}/config/secrets"
  mkdir -p "${secrets}"
  chmod 700 "${secrets}"
  find "${secrets}" -type f ! -name '*.md' ! -name '*.example' -exec chmod 600 {} +
}

step_finish() {
  printf '\n\033[1;32mDone.\033[0m Run:\n  source ~/.zshrc\n'
  have nvm && printf '  nvm use default\n'
  if [ "${DEVSETUP_MODE}" = "layer" ] && [ -n "${LAYER_ROOT:-}" ]; then
    printf 'This layer activates inside %s via direnv.\n' "${LAYER_ROOT}"
  fi
  # Guarded: the message named a directory that does not exist on every run that
  # replaced nothing, which is most of them.
  [ -d "${BACKUP_DIR}" ] && printf 'Backups are in %s\n' "${BACKUP_DIR}"
  return 0
}
