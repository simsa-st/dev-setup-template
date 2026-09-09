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

  # Suffixed: two instantiations on one machine each keep their own clone, even
  # when both point at the same repo (the normal case -- there is one nvim
  # config). An unsuffixed clone dir made them fight over one checkout:
  # whichever installed last won its identity, remotes and push URL below, and
  # the other's editor silently got the wrong ones. Migrate an existing
  # unsuffixed clone rather than re-cloning it.
  local src="${XDG_CONFIG_HOME}/nvim-config-${LAYER_SUFFIX}"
  if [ -d "${XDG_CONFIG_HOME}/nvim-config" ] && [ ! -e "${src}" ]; then
    mv "${XDG_CONFIG_HOME}/nvim-config" "${src}"
  fi
  clone_or_pull "${NVIM_CONFIG_REPO}" "${src}"
  # The clone is a personal repo; without a local identity a commit made in it
  # carries the global GIT_USER_EMAIL, which in a work instantiation is the
  # employer's. See NVIM_CONFIG_GIT_EMAIL.
  if [ -n "${NVIM_CONFIG_GIT_EMAIL:-}" ]; then
    git -C "${src}" config user.name "${GIT_USER_NAME}"
    git -C "${src}" config user.email "${NVIM_CONFIG_GIT_EMAIL}"
  fi
  add_machine_remotes "${src}"
  set_nvim_config_push_url "${src}"
  link "${src}" "${LAYER_NVIM_DIR}"

  [ "${DEVSETUP_MODE}" = "full" ] || return 0

  install_bob
  bob use "${NVIM_VERSION}"
  install_tree_sitter_cli
  link "${src}" "${XDG_CONFIG_HOME}/${NVIM_APPNAME:-nvim}"
}

# nvim-treesitter's main branch does not ship compiled parsers; it downloads
# each grammar and shells out to `tree-sitter build`, so without the CLI every
# parser install fails with ENOENT and nothing gets highlighted (the master
# branch, which needed only a C compiler, is frozen and refuses Neovim 0.12).
# macOS gets it from Homebrew (BREW_PACKAGES); the release zip holds the bare
# binary, which is what install_release_binary expects.
install_tree_sitter_cli() {
  have tree-sitter && return 0
  if [ "${TARGET}" = "macos" ] && have brew; then
    brew install tree-sitter
  else
    install_release_binary tree-sitter \
      "https://github.com/tree-sitter/tree-sitter/releases/download/${TREE_SITTER_CLI_VERSION}/tree-sitter-cli-linux-x64.zip"
  fi
}

# Every machine has its own clone of the nvim config at the same path, and a
# commit made on a box whose github.com key is not on the nvim repo's account
# cannot be pushed from there. The laptop can pull it over ssh instead, so each
# machine in hosts.toml becomes a git remote of the laptop's clone, named the
# way `conn` names it:
#
#     git pull --ff-only <alias> master && git push origin master
#
# Laptop only: the boxes never pull from each other, and a box adding a remote
# to itself would be noise. The URL uses the machine name, which the generated
# SSH config carries whatever the aliases are. Idempotent: an existing remote
# is repointed, not duplicated.
add_machine_remotes() { # <repo dir>
  [ "${TARGET}" = "macos" ] || return 0
  local repo="$1" rel="${1#"${HOME}"/}" remote host url
  "${DEV_SETUP_DIR}/config/bin/hosts" git-remotes 2> /dev/null | while read -r remote host; do
    url="${host}:${rel}"
    if git -C "${repo}" remote get-url "${remote}" > /dev/null 2>&1; then
      git -C "${repo}" remote set-url "${remote}" "${url}"
    else
      git -C "${repo}" remote add "${remote}" "${url}"
    fi
  done
}

# Fetch and push part ways: fetch stays on NVIM_CONFIG_REPO (anonymous HTTPS,
# works on a box with no personal key), push goes over the ssh alias in
# NVIM_CONFIG_PUSH_URL -- but only where that alias is defined, or a fresh
# laptop's first `git push` would fail on an alias nobody has created yet.
# `ssh -G` prints the resolved config without connecting: an undefined alias
# resolves to itself, a defined one to github.com. Converges either way: the
# push URL is set when the alias exists and dropped when it does not.
set_nvim_config_push_url() { # <repo dir>
  [ -n "${NVIM_CONFIG_PUSH_URL:-}" ] || return 0
  local repo="$1" alias="${NVIM_CONFIG_PUSH_URL#*@}"
  alias="${alias%%:*}"
  git -C "${repo}" remote set-url origin "${NVIM_CONFIG_REPO}"
  if ssh -G "${alias}" 2> /dev/null | grep -qi '^hostname github\.com$'; then
    git -C "${repo}" remote set-url --push origin "${NVIM_CONFIG_PUSH_URL}"
  else
    git -C "${repo}" config --unset-all remote.origin.pushurl 2> /dev/null || true
  fi
}

install_bob() {
  have bob && return 0
  if [ "${TARGET}" = "macos" ] && have brew; then
    brew install bob
  else
    install_release_binary bob \
      "https://github.com/MordechaiHadad/bob/releases/download/${BOB_VERSION}/bob-linux-x86_64.zip" \
      "bob-linux-x86_64/bob"
  fi
}
