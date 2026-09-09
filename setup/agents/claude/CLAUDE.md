# This machine

TODO(bootstrap): describe this box in three or four lines — what it is for,
where its own setup lives, and anything that happens to it without a human
present (unattended reboots for kernel updates, nightly jobs, a shared user).
Agents waste real time rediscovering that a session "crashed" overnight when in
fact the machine rebooted itself on schedule.

Sessions and tmux windows are saved every couple of minutes and restored
afterwards (`setup/lib/sessions.sh`), so a session that vanished overnight was
rebooted, not crashed.

# tmux

The server runs on a **private socket**, not the default one. Inside a pane bare
`tmux` works; from anywhere else add `-S ~/tmp-tmux-socket` (`TMUX_SOCKET` in
`setup/config/profile.env`), or the server looks like it does not exist.

    tmux ls                                                    # sessions
    tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'
    tmux display-message -p '#{session_name}:#{window_index}'  # which am I?
    tmux capture-pane -p -t work:2 | tail -30                  # read a window

Windows are named after the conversation in them, so `list-windows -a` is the
map of who is doing what.

# Talking to an agent in another window

    tmux-say work:2 'take a look at the pacing table'

Use it rather than raw `send-keys`: it sends the text literally and the Enter as
a separate keystroke after a pause, both of which are needed and neither of
which fails loudly when skipped. Read the answer with `capture-pane`; the
session is still working while its footer shows `esc to interrupt`.

# Starting a Claude session

    cla <remote-control-name>

in the pane it should live in. The name is what the phone shows and what lets
the session be resumed into the same pane after a reboot; `claude-panes list`
shows the tracked ones. A long-lived session started as bare `claude` has no
name and will not come back.

# Secrets

Everything under `setup/config/secrets/` except the README and the `*.example`
files is gitignored and is a local secrets file: never reveal its contents, in
output or in a commit. `setup/config/secrets/README.md` says how secrets reach a
machine.

TODO(bootstrap): add whatever else every session on this machine should know
before its first tool call — where the repos are, which commands are expensive,
what must never run here.
