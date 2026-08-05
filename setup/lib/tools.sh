#!/usr/bin/env bash
# Language toolchains and editors: uv, node, neovim.

step_tools() {
  install_uv
  install_node

  # The repo's own pre-commit hook, from its uv-managed dev group.
  if [ -f "${DEV_REPO_DIR}/.pre-commit-config.yaml" ]; then
    (cd "${DEV_REPO_DIR}" && uv run pre-commit install)
  fi

  # TODO(bootstrap): add per-project environment setup here — cloning the repos
  # you work on, creating their virtualenvs (`uv sync --frozen`), installing
  # their pre-commit hooks, writing their .env files. Keep the project-specific
  # part in its own lib/project.sh step rather than growing this one.
}

install_uv() {
  if have uv && version_ge "$(uv --version | awk '{print $2}')" "${MIN_UV_VERSION}"; then
    return 0
  fi
  if [ "${TARGET}" = "macos" ] && have brew; then
    brew upgrade uv || brew install uv
    # ~/.config/bin sits early on PATH and may hold an older standalone uv.
    rm -f "${XDG_CONFIG_HOME}/bin/uv" "${XDG_CONFIG_HOME}/bin/uvx"
  else
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="${XDG_CONFIG_HOME}/bin" sh
  fi
  hash -r
  have uv || die "uv installed but not on PATH (expected ${XDG_CONFIG_HOME}/bin on PATH)."
}

install_node() {
  local opts="$-"
  set +u  # nvm's script is not nounset-clean
  export NVM_DIR="${XDG_CONFIG_HOME}/nvm"
  export PROFILE=/dev/null  # keep the installer out of our dotfiles
  [ -s "${NVM_DIR}/nvm.sh" ] ||
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  # shellcheck disable=SC1091
  source "${NVM_DIR}/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
  nvm use --lts
  case "${opts}" in *u*) set -u ;; esac
}

# Neovim itself is managed by bob (a version manager), so the installed version
# is a config value rather than whatever the OS package manager ships. The
# config lives in its own repo — see NVIM_CONFIG_REPO in profile.env.
step_nvim() {
  install_bob
  bob use "${NVIM_VERSION}"

  if [ -n "${NVIM_CONFIG_REPO:-}" ]; then
    local src="${XDG_CONFIG_HOME}/nvim-config"
    clone_or_pull "${NVIM_CONFIG_REPO}" "${src}"
    link "${src}" "${XDG_CONFIG_HOME}/${NVIM_APPNAME:-nvim}"
  else
    warn "NVIM_CONFIG_REPO is unset in profile.env; skipping the neovim config."
  fi
}

install_bob() {
  have bob && return 0
  if [ "${TARGET}" = "macos" ] && have brew; then
    brew install bob
  else
    install_release_binary bob \
      "https://github.com/MordechaiHadad/bob/releases/latest/download/bob-linux-x86_64.zip" \
      "bob-linux-x86_64/bob"
  fi
}
