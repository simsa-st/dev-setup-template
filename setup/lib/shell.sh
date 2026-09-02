#!/usr/bin/env bash
# Shell, terminal and git configuration.
#
# Two rules make this re-runnable and relocatable:
#   1. ~/.zshrc only ever references stable ~/.config paths, never a repo path,
#      so moving the repo means re-pointing symlinks, not editing dotfiles.
#   2. Everything this setup writes into an existing file lives in a managed
#      BEGIN/END block that is rewritten wholesale on each run.

step_shell() {
  local cfg="${DEV_SETUP_DIR}/config"

  link "${cfg}/shell/zshrc-base.zsh" "${XDG_CONFIG_HOME}/zshrc-base.zsh"
  link "${cfg}/shell/bashrc-extra" "${XDG_CONFIG_HOME}/.bashrc-extra"

  # Drop stale bin symlinks that point at a different checkout of this repo,
  # then (re)link the current helper scripts.
  local existing
  for existing in "${XDG_CONFIG_HOME}/bin/"*; do
    [ -L "${existing}" ] || continue
    case "$(readlink "${existing}")" in
      */setup/config/bin/*) rm -f "${existing}" ;;
    esac
  done
  local f
  for f in "${cfg}"/bin/*; do
    case "$(basename "${f}")" in __pycache__ | *.pyc) continue ;; esac
    ln -sfn "${f}" "${XDG_CONFIG_HOME}/bin/$(basename "${f}")"
  done

  install_oh_my_zsh
  write_zshrc_header

  # Sourcing it here both loads the aliases/PATH for the rest of the install and
  # catches a ~/.config symlink still pointing at a different checkout.
  local expected="${DEV_SETUP_DIR}"
  # shellcheck disable=SC1091
  source "${XDG_CONFIG_HOME}/.bashrc-extra"
  [ "${DEV_SETUP_DIR}" = "${expected}" ] ||
    die "${XDG_CONFIG_HOME}/.bashrc-extra resolves to ${DEV_SETUP_DIR}, expected ${expected}"
}

install_oh_my_zsh() {
  local omz="${XDG_CONFIG_HOME}/oh-my-zsh"
  local custom="${omz}/custom"
  if [ ! -d "${omz}" ]; then
    log "installing oh-my-zsh"
    ZSH="${omz}" sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended --keep-zshrc
  fi

  clone_or_pull https://github.com/romkatv/powerlevel10k.git "${custom}/themes/powerlevel10k"
  clone_or_pull https://github.com/zsh-users/zsh-syntax-highlighting.git "${custom}/plugins/zsh-syntax-highlighting"
  clone_or_pull https://github.com/zsh-users/zsh-autosuggestions.git "${custom}/plugins/zsh-autosuggestions"

  # p10k's own config is generated per machine by `p10k configure`; it is not
  # tracked here because it encodes terminal/font capabilities.
  [ -f "${XDG_CONFIG_HOME}/p10k.zsh" ] || warn "run 'p10k configure' once to create ~/.config/p10k.zsh"
}

clone_or_pull() { # <url> <dir>
  if [ -d "$2/.git" ]; then git -C "$2" pull --quiet --ff-only || true; else git clone --depth=1 "$1" "$2"; fi
}

write_zshrc_header() {
  local snippet
  snippet=$(mktemp)
  cat > "${snippet}" << EOF
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
source \${XDG_CONFIG_HOME}/zshrc-base.zsh
source \${XDG_CONFIG_HOME}/.bashrc-extra
EOF
  managed_block "${HOME}/.zshrc" "ZSHRC_HEADER" "${snippet}"
  rm -f "${snippet}"
}

# The layer's own shell environment. Runs in both modes, because the file it
# installs is this repo's regardless of who owns the base -- what changes is
# only whether anything else is competing for ~/.zshrc.
#
# The block is *appended*: in layer mode the base setup owns the head of that
# file, and p10k's instant prompt has to stay near the top.
step_env() {
  link "${DEV_SETUP_DIR}/config/shell/bashrc-layer" "${LAYER_BASHRC}"

  # Two things stay unexpanded on purpose. The path is a ~/.config one rather
  # than a repo one, so moving this checkout re-points a symlink instead of
  # editing $HOME; and ${HOME}/${XDG_CONFIG_HOME} are written literally, so the
  # block is resolved when the shell starts rather than frozen to whatever the
  # installing user's home happened to be.
  local snippet
  snippet=$(mktemp)
  cat > "${snippet}" << EOF
_layer_bashrc="\${XDG_CONFIG_HOME:-\${HOME}/.config}/.bashrc-${LAYER_SUFFIX}"
[ -f "\${_layer_bashrc}" ] && source "\${_layer_bashrc}"
unset _layer_bashrc
EOF
  managed_block "${HOME}/.zshrc" "SHELL" "${snippet}"
  rm -f "${snippet}"

  write_layer_envrc
}

# The switch that makes two setups coexist without either being reconfigured:
# entering LAYER_ROOT points the editor and the agents at this layer's configs,
# and leaving it puts them back. Without it, a layer would have to either change
# the tools' defaults globally -- which is the base setup's business -- or be
# reachable only through aliases.
#
# direnv is what applies it; it is in the package list, and an .envrc has to be
# `direnv allow`ed once per machine.
write_layer_envrc() {
  [ -n "${LAYER_ROOT:-}" ] || return 0
  local envrc="${LAYER_ROOT}/.envrc"

  # In full mode the canonical paths *are* this repo's, so the overrides are
  # not merely unnecessary but wrong. Removing the block matters because a
  # machine can be switched from layer to full, and a step that only ever adds
  # cannot undo itself.
  if [ "${DEVSETUP_MODE}" = "full" ]; then
    remove_managed_block "${envrc}" "ENVRC"
    return 0
  fi

  if [ ! -d "${LAYER_ROOT}" ]; then
    warn "${LAYER_ROOT} does not exist; skipping the direnv layer profile."
    return 0
  fi

  local snippet
  snippet=$(mktemp)
  cat > "${snippet}" << EOF
export NVIM_APPNAME=${LAYER_NVIM_APPNAME}
export PI_CODING_AGENT_DIR="\${HOME}/.pi-${LAYER_SUFFIX}/agent"
export CLAUDE_CONFIG_DIR="\${HOME}/.claude-${LAYER_SUFFIX}"
EOF
  managed_block "${envrc}" "ENVRC" "${snippet}"
  rm -f "${snippet}"

  have direnv || warn "direnv is not installed; ${envrc} will not load."
}

step_tmux() {
  [ -d "${HOME}/.tmux/plugins/tpm" ] ||
    git clone --depth=1 https://github.com/tmux-plugins/tpm "${HOME}/.tmux/plugins/tpm"
  link "${DEV_SETUP_DIR}/config/tmux/tmux.conf" "${HOME}/.tmux.conf"

  # Cloning tpm is not installing the plugins tmux.conf declares: TPM only
  # fetches when told to, by `prefix + I` or by this script. Without this line
  # ~/.tmux/plugins holds tpm and nothing else, every `set -g @plugin` line is
  # inert, and the gap is invisible until the day the plugin was supposed to do
  # something — for tmux-resurrect, the reboot it was declared for.
  "${HOME}/.tmux/plugins/tpm/bin/install_plugins" > /dev/null ||
    warn "tmux: TPM could not install plugins; run prefix + I inside tmux"
}

step_git() {
  # Generated, not symlinked: the identity comes from profile.env, and a local
  # ~/.gitconfig may carry machine-specific credential helpers.
  mkdir -p "${XDG_CONFIG_HOME}/git"
  backup_path "${XDG_CONFIG_HOME}/git/config"
  sed -e "s|__GIT_USER_NAME__|${GIT_USER_NAME}|g" \
      -e "s|__GIT_USER_EMAIL__|${GIT_USER_EMAIL}|g" \
      "${DEV_SETUP_DIR}/config/git/config.template" > "${XDG_CONFIG_HOME}/git/config"
}
