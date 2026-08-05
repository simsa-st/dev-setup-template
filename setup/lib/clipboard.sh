#!/usr/bin/env bash
# Clipboard sync and SSH config.
#
# Clipboard path (see setup/README.md for the diagram):
#   remote tmux/nvim -> lemonade relay on the remote host -> reverse SSH tunnel
#   -> lemonade server on the laptop -> system clipboard.
# The relay exists so processes that cannot reach the tunnel's loopback port
# (containers, other users' namespaces) still have one address to talk to.

step_clipboard() {
  if [ "${TARGET}" = "macos" ]; then
    # Server side: built from source so it works on Apple Silicon.
    if [ ! -x "${HOME}/go/bin/lemonade" ]; then
      have go || die "go is required to build lemonade on macOS."
      go install github.com/lemonade-command/lemonade@latest
    fi
  else
    install_release_binary lemonade \
      "https://github.com/lemonade-command/lemonade/releases/download/${LEMONADE_VERSION}/lemonade_linux_amd64.tar.gz"
    # Containers and other processes need the host address to reach the relay.
    hostname -I 2> /dev/null | awk '{print $1}' > "${XDG_CONFIG_HOME}/host_ip" || true
  fi
}

step_ssh() {
  local hosts="${DEV_SETUP_DIR}/config/ssh/hosts.toml"
  if [ ! -f "${hosts}" ]; then
    warn "no ${hosts}; skipping SSH config generation (see BOOTSTRAP.md)."
    return 0
  fi

  local generated="${HOME}/.ssh/config.d/generated-port-forwards"
  mkdir -p "${HOME}/.ssh/config.d"
  chmod 700 "${HOME}/.ssh"

  backup_path "${HOME}/.ssh/config"
  "${DEV_SETUP_DIR}/config/bin/hosts" ssh-config --base > "${HOME}/.ssh/config"
  "${DEV_SETUP_DIR}/config/bin/hosts" ssh-config --forwards > "${generated}"
  chmod 600 "${HOME}/.ssh/config" "${generated}"

  local custom="${DEV_SETUP_DIR}/config/ssh/custom-forwards"
  if [ -f "${custom}" ]; then
    cp "${custom}" "${HOME}/.ssh/config.d/custom-forwards"
    chmod 600 "${HOME}/.ssh/config.d/custom-forwards"
  fi
}
