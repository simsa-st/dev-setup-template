#!/usr/bin/env bash
# Offline regression for lib/syncthing.sh's folder half: bash scripts/test_syncthing_setup.sh
# The daemon half needs launchd or systemd and a real Syncthing, so it is not here.
set -euo pipefail
repo=$(cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
export HOME="${scratch}/home" XDG_CONFIG_HOME="${scratch}/home/.config" TARGET=linux
export DEV_SETUP_DIR="${scratch}/setup"
mkdir -p "${HOME}" "${DEV_SETUP_DIR}/config/syncthing"
# shellcheck source=/dev/null
source "${repo}/setup/lib/common.sh"
# shellcheck source=/dev/null
source "${repo}/setup/lib/syncthing.sh"
src="${DEV_SETUP_DIR}/config/syncthing"
syncthing_ensure_daemon() { echo daemon >> "${scratch}/calls"; }

# Off by default: no ignores written, no daemon.
mkdir -p "${HOME}/notes"
export SYNCTHING_FOLDERS="notes=notes"
step_syncthing > /dev/null
[ ! -e "${HOME}/notes/.stignore" ] && [ ! -e "${scratch}/calls" ]

# base, then <name>, then <name>.<target>; another target's file is left out.
printf 'base\n' > "${src}/base.stignore"
printf 'named\n' > "${src}/notes.stignore"
printf 'linux-only\n' > "${src}/notes.stignore.linux"
printf 'macos-only\n' > "${src}/notes.stignore.macos"
export SYNCTHING=true
step_syncthing > /dev/null
[ "$(cat "${HOME}/notes/.stignore")" = "$(printf 'base\nnamed\nlinux-only')" ]
[ "$(cat "${scratch}/calls")" = daemon ]

# A second run converges without rewriting; a changed source is picked up.
touch -t 200001010000 "${HOME}/notes/.stignore" "${scratch}/ref"
step_syncthing > /dev/null
[ ! "${HOME}/notes/.stignore" -nt "${scratch}/ref" ]
printf 'named2\n' > "${src}/notes.stignore"
step_syncthing > /dev/null
grep -qx named2 "${HOME}/notes/.stignore"

# Absolute paths are taken as given; a missing folder and a malformed entry are
# warnings, not failures.
mkdir -p "${scratch}/abs"
export SYNCTHING_FOLDERS="notes=${scratch}/abs missing=nowhere bogus"
step_syncthing > /dev/null 2>&1
[ -f "${scratch}/abs/.stignore" ] && [ ! -e "${HOME}/nowhere" ]

# No source patterns at all: an empty .stignore would mean "sync everything",
# so nothing is written.
rm -f "${src}"/*
mkdir -p "${HOME}/bare"
export SYNCTHING_FOLDERS="bare=bare"
step_syncthing > /dev/null 2>&1
[ ! -e "${HOME}/bare/.stignore" ]
echo 'syncthing setup: ok'
