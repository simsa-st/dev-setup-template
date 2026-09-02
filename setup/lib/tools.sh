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
# Both modes get the config at its layer path (~/.config/nvim-<suffix>), reached
# with NVIM_APPNAME; full mode additionally installs neovim itself and claims
# ~/.config/nvim. In layer mode the neovim *binary* belongs to the base setup --
# a second bob-managed install would shadow it on PATH.
step_nvim() {
  if [ -z "${NVIM_CONFIG_REPO:-}" ]; then
    warn "NVIM_CONFIG_REPO is unset in profile.env; skipping the neovim config."
    return 0
  fi

  # Suffixed: two instantiations on one machine have different
  # NVIM_CONFIG_REPOs, and an unsuffixed clone dir made them fight over one
  # checkout — whichever installed last won, and the other's editor silently
  # got the wrong config. Migrate an existing unsuffixed clone rather than
  # re-cloning it.
  local src="${XDG_CONFIG_HOME}/nvim-config-${LAYER_SUFFIX}"
  if [ -d "${XDG_CONFIG_HOME}/nvim-config" ] && [ ! -e "${src}" ]; then
    mv "${XDG_CONFIG_HOME}/nvim-config" "${src}"
  fi
  clone_or_pull "${NVIM_CONFIG_REPO}" "${src}"
  link "${src}" "${LAYER_NVIM_DIR}"

  [ "${DEVSETUP_MODE}" = "full" ] || return 0

  install_bob
  bob use "${NVIM_VERSION}"
  link "${src}" "${XDG_CONFIG_HOME}/${NVIM_APPNAME:-nvim}"
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
