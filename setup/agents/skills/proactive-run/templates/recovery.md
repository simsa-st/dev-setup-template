# RECOVERY — when the session dies and the agents do not

Copy this into the run when it happens, fill it in as you go, and keep it: it
is the only record of which conversation is which after the fact.

## What actually happens

A tmux server can die — a crash, an OOM, a reconnect gone wrong — without
taking the agents with it. Where the panes are `docker exec` clients (or any
other remote shell), the clients die and the **agents inside keep running**:
they ignore the hangup, finish the turn they were in, and then idle where
nobody can reach them. They are not lost, they are unaddressed.

So the recovery is not "restart everything". It is: find each conversation,
prove it is quiet, kill the orphan, and reopen the window on the *same*
conversation.

## The procedure

1. **Fix the timeline before touching anything.** The last message that worked
   and the first that failed bracket the death; write both down with
   timestamps. `logs/comms.md` usually has them.
2. **Find each agent's transcript.** Grep the agent's session store for the
   worker's own identifying string (its window name, or the first line of its
   prompt). **Verify by the last entry inside the file, not by mtime** — an
   idle orphan rewrites its metadata on a timer, so mtimes say every session is
   equally alive.
3. **Prove it is quiet before killing it.** Watch the transcript for a few
   minutes of no new entries. An agent mid-turn is still writing, and killing
   it there loses the turn.
4. **Kill by the pid you identified**, verified by working directory and
   process tree — never by a name pattern, which is how one sweep killed four
   processes belonging to someone else.
5. **Reopen the window on the same conversation**: the original command line
   plus the agent's resume flag and that session id. Then send a short recovery
   note — what happened, what to re-read (scratchpad, inbox, time status),
   what not to redo.
6. **Record it in the table below**, and only then let the run continue.

Agents running as a supervised background service survive all of this
untouched; check for those before assuming a window is dead.

## What was recovered

| window | session id | orphan pid | cwd | state at death | note |
|---|---|---|---|---|---|
|  |  |  |  |  |  |

## Not restored, deliberately

<what was left dead, and why — a finished worker, a stale session, a loop whose
work is over. Being explicit here is what stops the next person reviving it.>

## Root cause

<what is known, what was ruled out, and the exact commands someone with more
access should run. "Unknown" with the ruling-out written down is a fine answer;
a guess presented as a cause is not.>
