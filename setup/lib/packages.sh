#!/usr/bin/env bash
# Base packages. macOS uses Homebrew. On Linux there are two cases and the
# difference is root, not the distro: a personal box has passwordless sudo and
# should just get apt packages, while a shared machine has none and everything
# has to land user-locally in ~/.config/bin. Detected, not declared -- the same
# script has to work on both.

# tree-sitter: the CLI nvim-treesitter (main branch) shells out to when it
# compiles a parser; without it every `:TSInstall` fails with ENOENT. Linux
# gets it as a release binary in tools.sh (install_tree_sitter_cli).
# TODO(bootstrap): trim/extend to the packages this environment actually needs.
BREW_PACKAGES=(
  autossh direnv fzf git git-delta git-lfs go jq mosh ripgrep tmux tree-sitter uv zsh
  font-meslo-lg-nerd-font
)

# GitHub release binaries installed without root on Linux (and used as the
# fallback on macOS when Homebrew does not carry them).
install_release_binary() { # <name> <url> [<path-inside-archive>]
  local name="$1" url="$2" inner="${3:-}"
  local dest="${XDG_CONFIG_HOME}/bin/${name}"
  [ -x "${dest}" ] && return 0
  log "installing ${name} into ${dest}"
  local tmp
  tmp=$(mktemp -d)
  (
    cd "${tmp}" || exit 1
    curl -fsSL "${url}" -o archive
    case "${url}" in
      *.tar.gz | *.tgz) tar -xzf archive ;;
      *.zip) unzip -q archive ;;
      # A bare compressed binary, which is how restic and friends ship. Without
      # this it falls to the catch-all below and a bz2 stream is installed as
      # the executable -- which fails as "cannot execute binary file" at the
      # point of use rather than here.
      *.bz2) bzip2 -dc archive > "${name}"; chmod +x "${name}" ;;
      *) mv archive "${name}"; chmod +x "${name}" ;;
    esac
    mv "${inner:-${name}}" "${dest}"
  )
  rm -rf "${tmp}"
  chmod +x "${dest}"
}

# Debian/Ubuntu packages, but only where we are actually allowed to install
# them. zsh in particular is not optional: step_shell dies without it, so a box
# that has never had it cannot be set up at all. mosh is what makes `conn
# --mosh` work, and without it a connection dies with the laptop lid.
# git-lfs: config/git/config.template marks the lfs filter `required`, so in any
# repo that tracks paths with it a commit fails without the binary. (Homebrew
# already carries it in BREW_PACKAGES.)
# TODO(bootstrap): trim/extend to what this environment actually needs.
APT_PACKAGES=(zsh tmux mosh git git-lfs curl unzip direnv fzf ripgrep jq build-essential)

apt_install_base() {
  have apt-get || return 0
  if ! sudo -n true 2> /dev/null; then
    warn "no passwordless sudo; skipping apt (shared machine: user-local installs only)."
    return 0
  fi
  local missing=() pkg
  for pkg in "${APT_PACKAGES[@]}"; do
    dpkg -s "${pkg}" > /dev/null 2>&1 || missing+=("${pkg}")
  done
  # Converge, but do not pay for an apt-get update on every single run.
  [ ${#missing[@]} -eq 0 ] && return 0
  log "apt-get install: ${missing[*]}"
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "apt-get update failed."
  sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" ||
    warn "apt-get install failed for: ${missing[*]}"
  hash -r
}

ensure_docker_group() {
  have docker || return 0
  getent group docker >/dev/null 2>&1 || return 0
  id -nG "${USER}" | tr ' ' '\n' | grep -qx docker && return 0
  if ! sudo -n true 2>/dev/null; then
    warn "not in the docker group and passwordless sudo is unavailable."
    return 0
  fi
  sudo -n usermod -aG docker "${USER}" || { warn "could not add ${USER} to docker group."; return 0; }
  warn "docker group added; log out and back in before using docker."
}

step_packages() {
  if [ "${TARGET}" = "linux" ]; then
    if [ "${INSTALL_BUN:-false}" = "true" ]; then
      [ -n "${BUN_VERSION:-}" ] || die "INSTALL_BUN=true requires BUN_VERSION"
    fi
    if [ "${INSTALL_DOCKER:-false}" = "true" ]; then
      APT_PACKAGES+=(docker.io docker-compose-v2)
    fi
  fi
  if [ "${TARGET}" = "macos" ]; then
    have brew || die "Homebrew is required on macOS: https://brew.sh"
    brew install "${BREW_PACKAGES[@]}"
  else
    apt_install_base
    for tool in curl git tmux zsh; do
      have "${tool}" || warn "${tool} is missing and needs an admin to install it."
    done
    install_release_binary delta \
      "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
      "delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu/delta"
    # A single static binary, and not optional: agents/claude/statusline.sh is
    # jq from its first line, and without it every prompt renders an empty
    # status line instead of an error.
    install_release_binary jq \
      "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64"
    if [ "${INSTALL_BUN:-false}" = "true" ]; then
      install_release_binary bun \
        "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip" \
        "bun-linux-x64/bun"
    fi
    if [ "${INSTALL_DOCKER:-false}" = "true" ]; then
      have docker || warn "INSTALL_DOCKER=true, but docker is unavailable (apt may need an administrator)."
      if [ "${JOIN_DOCKER_GROUP:-false}" = "true" ]; then
        ensure_docker_group
      else
        warn "Docker installed without group membership; use sudo or explicitly opt in to root-equivalent JOIN_DOCKER_GROUP."
      fi
    fi
  fi
}
