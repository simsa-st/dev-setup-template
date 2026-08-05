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
  local dest="$(backup_dir)/$(basename "${path}")"
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

version_ge() { # <have> <want>
  python3 - "$1" "$2" <<'PY'
import re, sys
parts = lambda v: [int(p) for p in re.split(r"[.+-]", v) if p.isdigit()]
sys.exit(0 if parts(sys.argv[1]) >= parts(sys.argv[2]) else 1)
PY
}

# Rewrite a `# BEGIN/END DEVSETUP_<name>` block in a file, creating it at the
# top if absent. This is what keeps re-runs idempotent instead of appending.
managed_block() { # <file> <name> <content-file>
  python3 - "$1" "$2" "$3" <<'PY'
from pathlib import Path
import sys

path, name, content_path = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
begin, end = f"# BEGIN DEVSETUP_{name}", f"# END DEVSETUP_{name}"
content = content_path.read_text()
if content and not content.endswith("\n"):
    content += "\n"
block = f"{begin}\n{content}{end}\n"

path.touch()
text = path.read_text()
start, stop = text.find(begin), text.find(end)
if start == -1 or stop == -1 or stop < start:
    path.write_text(block + text)
else:
    path.write_text(text[:start] + block + text[stop + len(end):].lstrip("\n"))
PY
}

# Values that differ per person (identity, nvim config repo, ports) live in
# config/profile.env, committed once the template is instantiated. Per-machine
# overrides live in config/machine.local.env, which is gitignored.
load_profile() {
  local profile="${DEV_SETUP_DIR}/config/profile.env"
  [ -f "${profile}" ] || die "Missing ${profile} — copy profile.env.example and fill it in (see BOOTSTRAP.md)."
  set -a
  # shellcheck disable=SC1090
  source "${profile}"
  [ -f "${DEV_SETUP_DIR}/config/machine.local.env" ] && source "${DEV_SETUP_DIR}/config/machine.local.env"
  set +a
}

step_preflight() {
  load_profile
  have zsh || die "zsh is required; install it first."
  have git || die "git is required; install it first."
  have python3 || die "python3 is required; install it first."
  mkdir -p "${XDG_CONFIG_HOME}/bin"
  chmod 700 "${DEV_SETUP_DIR}/config/secrets" 2> /dev/null || true
}

step_finish() {
  printf '\n\033[1;32mDone.\033[0m Run:\n  source ~/.zshrc\n'
  have nvm && printf '  nvm use default\n'
  printf 'Backups (if any) are in %s\n' "${BACKUP_DIR}"
}
