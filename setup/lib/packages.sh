#!/usr/bin/env bash
# Base packages. macOS uses Homebrew; Linux hosts are assumed to be shared
# machines without root, so everything lands user-locally in ~/.config/bin.

# TODO(bootstrap): trim/extend to the packages this environment actually needs.
BREW_PACKAGES=(
  autossh direnv fzf git git-delta git-lfs go jq mosh ripgrep tmux uv zsh
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
      *) mv archive "${name}"; chmod +x "${name}" ;;
    esac
    mv "${inner:-${name}}" "${dest}"
  )
  rm -rf "${tmp}"
  chmod +x "${dest}"
}

step_packages() {
  if [ "${TARGET}" = "macos" ]; then
    have brew || die "Homebrew is required on macOS: https://brew.sh"
    brew install "${BREW_PACKAGES[@]}"
  else
    # No root on shared Linux machines: only user-local installs here.
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
  fi
}
