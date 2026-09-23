#!/usr/bin/env bash
# Sessions that survive a reboot.
#
# Three pieces have to line up, and only one of them is a plugin:
#
#   * tmux-resurrect + tmux-continuum save and replay the tmux skeleton --
#     windows, layouts, working directories. tmux.conf declares them and
#     step_tmux installs them.
#   * config/bin/claude-pane gives each Claude session a command line that means
#     the same conversation after a reboot as before it, which is what a restore
#     can replay; config/bin/claude-panes keeps the name -> conversation map.
#   * this step schedules config/bin/tmux-persist, which writes both halves to
#     disk every couple of minutes. Continuum's own save triggers cannot do it
#     on a machine that reboots while detached — see the script for why.
#
# Optional in the sense that a laptop can live without it; on an always-on box
# that patches its own kernel overnight it is the difference between coming back
# to yesterday's windows and coming back to none.

# systemd and launchd both start a job with a near-empty environment, so the
# unit has to carry a PATH that contains tmux wherever this platform keeps it.
SESSIONS_UNIT_PATH="${XDG_CONFIG_HOME}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

step_sessions() {
  # Linked here as well as by step_shell, so `--only sessions` on a fresh
  # machine cannot leave the scheduler pointing at a path that does not exist
  # yet (systemd reports that as 203/EXEC, launchd as a silent no-op).
  local script
  for script in claude-pane claude-panes tmux-persist activity-log; do
    chmod +x "${DEV_SETUP_DIR}/config/bin/${script}"
    ln -sfn "${DEV_SETUP_DIR}/config/bin/${script}" "${XDG_CONFIG_HOME}/bin/${script}"
  done

  if [ "${TARGET}" = "macos" ]; then
    sessions_install_launchd
  else
    sessions_install_systemd
  fi
}

sessions_install_systemd() {
  if ! have systemctl; then
    warn "sessions: no systemd; run ~/.config/bin/tmux-persist from cron instead."
    return 0
  fi

  local units="${XDG_CONFIG_HOME}/systemd/user"
  mkdir -p "${units}"

  # Copied and rendered, not symlinked: `systemctl reenable` is disable-then-
  # enable, and disable deletes a unit file that happens to be a symlink.
  sed -e "s|__TMUX_SOCKET__|${TMUX_SOCKET}|g" \
      -e "s|__PATH__|${SESSIONS_UNIT_PATH}|g" \
      "${DEV_SETUP_DIR}/config/systemd/tmux-persist.service.template" \
      > "${units}/tmux-persist.service"
  sed -e "s|__INTERVAL__|${TMUX_PERSIST_INTERVAL}|g" \
      "${DEV_SETUP_DIR}/config/systemd/tmux-persist.timer.template" \
      > "${units}/tmux-persist.timer"

  sessions_enable_lingering

  systemctl --user daemon-reload
  systemctl --user reenable tmux-persist.timer > /dev/null
  systemctl --user start tmux-persist.timer
  log "sessions: timer $(systemctl --user is-active tmux-persist.timer), every ${TMUX_PERSIST_INTERVAL}s"
}

# Without lingering, user units are torn down at logout — which on a box nobody
# stays logged in to means the timer runs for the length of one ssh session and
# then stops, exactly when it would have mattered.
sessions_enable_lingering() {
  [ "$(loginctl show-user "${USER}" -p Linger --value 2> /dev/null)" = "yes" ] && return 0
  # No sudo here (invariant 6): on a machine where this needs root, an admin
  # runs `loginctl enable-linger` once and the rest of the step still works.
  loginctl enable-linger "${USER}" 2> /dev/null ||
    warn "sessions: could not enable lingering; the timer will stop at logout."
}

sessions_install_launchd() {
  local label="${TMUX_PERSIST_LABEL}"
  local plist="${HOME}/Library/LaunchAgents/${label}.plist"
  local logfile="${HOME}/Library/Logs/${label}.log"
  mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"

  sed -e "s|__LABEL__|${label}|g" \
      -e "s|__BIN_DIR__|${XDG_CONFIG_HOME}/bin|g" \
      -e "s|__TMUX_SOCKET__|${TMUX_SOCKET}|g" \
      -e "s|__PATH__|${SESSIONS_UNIT_PATH}|g" \
      -e "s|__INTERVAL__|${TMUX_PERSIST_INTERVAL}|g" \
      -e "s|__LOG__|${logfile}|g" \
      "${DEV_SETUP_DIR}/config/launchd/tmux-persist.plist.template" \
      > "${plist}"

  # Converge rather than skip: bootout unloads whatever definition is currently
  # registered, so an edited interval or a moved path takes effect. Booting out
  # something that is not loaded is an error, hence the guard — and `bootstrap`
  # on an already-loaded label would fail with EALREADY.
  local domain
  domain="gui/$(id -u)"
  launchctl bootout "${domain}/${label}" > /dev/null 2>&1 || true
  if ! launchctl bootstrap "${domain}" "${plist}"; then
    warn "sessions: launchctl bootstrap failed for ${plist}"
    return 0
  fi
  log "sessions: ${label} every ${TMUX_PERSIST_INTERVAL}s, log ${logfile}"

  # Only a full-mode Mac polls configured machines. Layer mode leaves its
  # owner's scheduler alone; it may opt into a separate layer-specific job.
  local sync_label="dev.setup.activity-log-sync"
  local sync_plist="${HOME}/Library/LaunchAgents/${sync_label}.plist"
  local sync_log="${HOME}/Library/Logs/${sync_label}.log"
  if [ -z "${ACTIVITY_LOG_CATEGORY:-}" ]; then
    launchctl bootout "${domain}/${sync_label}" > /dev/null 2>&1 || true
    rm -f "${sync_plist}"
    return 0
  fi
  case "${ACTIVITY_LOG_CATEGORY}" in work | personal) ;; *) die "invalid ACTIVITY_LOG_CATEGORY" ;; esac
  sed -e "s|__BIN_DIR__|${XDG_CONFIG_HOME}/bin|g" \
      -e "s|__PATH__|${SESSIONS_UNIT_PATH}|g" \
      -e "s|__LOG__|${sync_log}|g" \
      "${DEV_SETUP_DIR}/config/launchd/activity-log-sync.plist.template" > "${sync_plist}"
  launchctl bootout "${domain}/${sync_label}" > /dev/null 2>&1 || true
  launchctl bootstrap "${domain}" "${sync_plist}" ||
    warn "sessions: launchctl bootstrap failed for ${sync_plist}"
}
