#!/usr/bin/env bash
# Syncthing: one daemon per user, shared by every setup on the machine.
#
# A machine can carry two instantiations of this template (layer mode), and
# both may want folders synced. Syncthing allows one daemon per user: a second
# one on the same config directory fails on ports 8384/22000 and, under
# KeepAlive, respawns forever. So the daemon belongs to no single setup. Every
# instantiation that enables this step renders the *same* launchd agent
# (SYNCTHING_AGENT_LABEL from the same plist template), and the step compares
# normalized plists, so whichever setup installs last changes nothing.
#
# That is the one deliberate exception to invariant 3: a path both setups write,
# made safe by both writing identical content. Keep this file and
# config/launchd/syncthing.plist.template identical across instantiations; a
# divergent copy makes the two installs restart the daemon in turn.
#
# What each setup owns is its folders, as .stignore files declared in
# SYNCTHING_FOLDERS. Pairing (device IDs, folder IDs, which peer shares what) is
# per-device state in Syncthing's own config and is done by hand, never here.
#
# Entry points for an instantiation that wraps this step:
#   syncthing_install_stignore <folder-dir> <name>   before any pairing
#   syncthing_ensure_daemon                          install, supervise, log the ID

# Not configurable: a per-setup label is exactly what would give two daemons.
SYNCTHING_AGENT_LABEL="dev.setup.syncthing"

step_syncthing() {
  if [ "${SYNCTHING:-false}" != "true" ]; then
    log "syncthing: off (SYNCTHING=false)"
    return 0
  fi
  # Ignores first: a folder that is already paired starts pulling the moment
  # the daemon is up, ahead of the file that says what not to want.
  syncthing_install_declared_folders
  syncthing_ensure_daemon
}

# SYNCTHING_FOLDERS is "name=path ...", path relative to $HOME unless absolute.
syncthing_install_declared_folders() {
  local entry name path
  for entry in ${SYNCTHING_FOLDERS:-}; do
    name="${entry%%=*}"
    path="${entry#*=}"
    if [ -z "${name}" ] || [ "${name}" = "${entry}" ] || [ -z "${path}" ]; then
      warn "syncthing: SYNCTHING_FOLDERS entry '${entry}' is not name=path; skipping."
      continue
    fi
    case "${path}" in /*) ;; *) path="${HOME}/${path}" ;; esac
    syncthing_install_stignore "${path}" "${name}"
  done
}

# Writes <folder-dir>/.stignore from config/syncthing/: base.stignore, then
# <name>.stignore, then <name>.stignore.<TARGET>, whichever exist.
#
# Device-local: Syncthing never syncs .stignore itself, so every node needs its
# own copy, which is why these files live in the repo. Copied, not symlinked:
# Syncthing reads the file itself, and a link left dangling by a moved checkout
# would quietly mean "ignore nothing".
syncthing_install_stignore() { # <folder-dir> <name>
  local folder="$1" name="$2"
  local src="${DEV_SETUP_DIR}/config/syncthing"
  local dest="${folder}/.stignore"
  local part found="no" rendered

  if [ ! -d "${folder}" ]; then
    warn "syncthing: no ${folder}; skipping its .stignore."
    return 0
  fi

  rendered=$(mktemp "${TMPDIR:-/tmp}/stignore.XXXXXX")
  for part in base.stignore "${name}.stignore" "${name}.stignore.${TARGET}"; do
    if [ -f "${src}/${part}" ]; then
      cat "${src}/${part}" >> "${rendered}"
      found="yes"
    fi
  done
  # An empty .stignore means "sync everything", which is never what a missing
  # source file was meant to say.
  if [ "${found}" = "no" ]; then
    rm -f "${rendered}"
    warn "syncthing: no ignore patterns for '${name}' in ${src}; leaving ${dest} alone."
    return 0
  fi

  if [ -f "${dest}" ] && cmp -s "${rendered}" "${dest}"; then
    rm -f "${rendered}"
    return 0
  fi
  backup_path "${dest}"
  mv "${rendered}" "${dest}"
  chmod 644 "${dest}"
  log "syncthing: wrote ${dest}"
}

# Always returns 0: a sync daemon that fails to come up is a warning, not a
# reason to abort the rest of the install.
syncthing_ensure_daemon() {
  case "${TARGET}" in
    macos) syncthing_install_macos || return 0 ;;
    linux) syncthing_install_linux || return 0 ;;
  esac

  syncthing_wait_for_api || return 0
  syncthing_drop_default_folder
  syncthing_converge_local_discovery

  log "syncthing: running, device $(syncthing_device_id)"
  log "syncthing: GUI on 127.0.0.1:8384 only (over ssh: ssh -L 8384:127.0.0.1:8384 <host>)"
}

# --- macOS: a launchd agent ------------------------------------------------

syncthing_install_macos() {
  if ! have brew; then
    warn "syncthing: no Homebrew on this Mac; skipping the daemon."
    return 1
  fi
  have syncthing || brew install syncthing || { warn "syncthing: brew install failed"; return 1; }

  local domain
  domain="gui/$(id -u)"
  syncthing_retire_replaced_agents "${domain}"
  if ! syncthing_agent_is_running "${domain}" && pgrep -qx syncthing; then
    warn "syncthing: a daemon not started by ${SYNCTHING_AGENT_LABEL} is running (brew services, Syncthing.app, or a label to add to SYNCTHING_REPLACES); not starting a second one."
    return 1
  fi

  local agents="${HOME}/Library/LaunchAgents"
  local plist="${agents}/${SYNCTHING_AGENT_LABEL}.plist"
  # Syncthing rotates this one itself; the plist says why launchd's own stdout
  # capture is thrown away rather than pointed at a second file.
  local logfile="${HOME}/Library/Logs/syncthing.log"
  mkdir -p "${agents}" "$(dirname "${logfile}")"

  # The binary's absolute path is resolved now and baked in: launchd starts an
  # agent with a minimal PATH that has no /opt/homebrew in it.
  #
  # Normalized through plutil, which drops the comments: two instantiations
  # whose copies of the template differ only in commentary then render the same
  # bytes, and neither install restarts the daemon over a reworded comment.
  local rendered
  rendered=$(mktemp "${TMPDIR:-/tmp}/${SYNCTHING_AGENT_LABEL}.XXXXXX")
  sed -e "s|__LABEL__|${SYNCTHING_AGENT_LABEL}|g" \
      -e "s|__SYNCTHING_BIN__|$(command -v syncthing)|g" \
      -e "s|__LOG__|${logfile}|g" \
      "${DEV_SETUP_DIR}/config/launchd/syncthing.plist.template" |
    plutil -convert xml1 -o "${rendered}" - || {
      rm -f "${rendered}"
      warn "syncthing: could not render ${plist}"
      return 1
    }

  # Reload only when the definition changed or the daemon is not up: a restart
  # costs about 15 seconds of sync, and invariant 1 says a re-run with nothing
  # changed is a no-op.
  if cmp -s "${rendered}" "${plist}" && syncthing_agent_is_running "${domain}"; then
    rm -f "${rendered}"
    log "syncthing: already running the current definition"
    return 0
  fi
  # No backup_path: the file is generated by this step and nothing else.
  mv "${rendered}" "${plist}"
  chmod 644 "${plist}"
  syncthing_bootout "${domain}" "${SYNCTHING_AGENT_LABEL}"
  if ! launchctl bootstrap "${domain}" "${plist}"; then
    warn "syncthing: launchctl bootstrap failed for ${plist}"
    return 1
  fi
}

# SYNCTHING_REPLACES lists launchd labels that ran this daemon before the step
# was shared, typically an instantiation's own old label. Each one is booted out
# and its plist removed, so it never runs beside the shared agent.
syncthing_retire_replaced_agents() { # <launchd-domain>
  local domain="$1" label plist
  for label in ${SYNCTHING_REPLACES:-}; do
    [ "${label}" = "${SYNCTHING_AGENT_LABEL}" ] && continue
    plist="${HOME}/Library/LaunchAgents/${label}.plist"
    if launchctl print "${domain}/${label}" > /dev/null 2>&1 || [ -f "${plist}" ]; then
      syncthing_bootout "${domain}" "${label}"
      rm -f "${plist}"
      log "syncthing: retired the ${label} agent in favour of ${SYNCTHING_AGENT_LABEL}"
    fi
  done
}

# bootout returns before the job is gone, and bootstrapping a label that is
# still shutting down fails with `Bootstrap failed: 5: Input/output error`,
# which reads like a broken plist and is not. Booting out something that is not
# loaded is an error, hence the `|| true`.
syncthing_bootout() { # <launchd-domain> <label>
  launchctl bootout "$1/$2" > /dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "$1/$2" > /dev/null 2>&1 || return 0
    sleep 1
  done
}

# `launchctl print` succeeding is not the test: it answers for a label that is
# merely *registered*, so a job that is loaded but dead (crashed, throttled,
# mid-bootout) would read as healthy. `state = running` is the honest question.
syncthing_agent_is_running() { # <launchd-domain>
  launchctl print "$1/${SYNCTHING_AGENT_LABEL}" 2> /dev/null |
    grep -qE '^[[:space:]]*state = running$'
}

# --- Linux: the distro's systemd user unit ---------------------------------

syncthing_install_linux() {
  if ! syncthing_apt_repo_current || ! have syncthing; then
    if ! sudo -n true 2> /dev/null; then
      if have syncthing; then
        warn "syncthing: no passwordless sudo; using the installed $(syncthing --version 2> /dev/null | awk '{print $2}') without the upstream apt repo."
      else
        warn "syncthing: no passwordless sudo and no syncthing; skipping the daemon."
        return 1
      fi
    else
      syncthing_apt_repo
      if ! have syncthing; then
        sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq syncthing ||
          { warn "syncthing: apt install failed"; return 1; }
      fi
    fi
  fi

  syncthing_enable_lingering
  systemctl --user enable --now syncthing.service > /dev/null 2>&1 ||
    { warn "syncthing: could not start syncthing.service"; return 1; }
  log "syncthing: syncthing.service $(systemctl --user is-active syncthing.service)"
}

# The Ubuntu archive lags Syncthing badly (24.04 ships 1.27 against upstream's
# 1.30), and peers on brew run current releases.
SYNCTHING_APT_KEY="/etc/apt/keyrings/syncthing-archive-keyring.gpg"
SYNCTHING_APT_LIST="/etc/apt/sources.list.d/syncthing.list"
SYNCTHING_APT_LINE="deb [signed-by=${SYNCTHING_APT_KEY}] https://apt.syncthing.net/ syncthing stable"

syncthing_apt_repo_current() {
  [ -f "${SYNCTHING_APT_KEY}" ] &&
    [ "$(cat "${SYNCTHING_APT_LIST}" 2> /dev/null)" = "${SYNCTHING_APT_LINE}" ]
}

syncthing_apt_repo() {
  syncthing_apt_repo_current && return 0
  log "syncthing: adding the upstream apt repo"
  sudo -n mkdir -p "$(dirname "${SYNCTHING_APT_KEY}")"
  sudo -n curl -fsSL -o "${SYNCTHING_APT_KEY}" https://syncthing.net/release-key.gpg
  printf '%s\n' "${SYNCTHING_APT_LINE}" | sudo -n tee "${SYNCTHING_APT_LIST}" > /dev/null
  sudo -n apt-get update -qq || warn "syncthing: apt-get update failed"
}

# Without lingering, user units stop at logout, which on a box nobody stays
# logged in to means the daemon lives for one ssh session.
syncthing_enable_lingering() {
  [ "$(loginctl show-user "${USER}" -p Linger --value 2> /dev/null)" = "yes" ] && return 0
  loginctl enable-linger "${USER}" 2> /dev/null ||
    sudo -n loginctl enable-linger "${USER}" 2> /dev/null ||
    warn "syncthing: could not enable lingering; the daemon will stop at logout."
}

# --- both ------------------------------------------------------------------

# The `syncthing cli` calls talk to the daemon's REST API, which is not up the
# instant the supervisor reports the process started.
syncthing_wait_for_api() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    syncthing cli show system > /dev/null 2>&1 && return 0
    sleep 1
  done
  warn "syncthing: API did not come up; skipping the config tweaks."
  return 1
}

# A fresh install ships a "default" folder at ~/Sync. Nothing uses it, and a
# folder in the list that nobody syncs is one more thing to mistake for real.
syncthing_drop_default_folder() {
  if syncthing cli config folders list | grep -qx default; then
    syncthing cli config folders default delete && rmdir "${HOME}/Sync" 2> /dev/null
  fi
  return 0
}

# Local discovery is a LAN broadcast. A laptop wants it (peers on the same
# network sync without leaving it); a cloud box has no LAN peers, and with it
# off 21027/udp never has to be opened. SYNCTHING_LOCAL_DISCOVERY overrides.
syncthing_converge_local_discovery() {
  local want="${SYNCTHING_LOCAL_DISCOVERY:-}"
  if [ -z "${want}" ]; then
    if [ "${TARGET}" = "macos" ]; then want="true"; else want="false"; fi
  fi
  if [ "$(syncthing cli config options local-ann-enabled get 2> /dev/null)" != "${want}" ]; then
    syncthing cli config options local-ann-enabled set "${want}"
    log "syncthing: local discovery ${want}"
  fi
}

# Syncthing 2 turned this from a flag into a subcommand and rejects the old
# spelling, so brew (2.x) and older apt builds (1.x) each need the other one.
syncthing_device_id() {
  syncthing device-id 2> /dev/null || syncthing --device-id
}
