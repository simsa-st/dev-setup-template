// Optional Codex subscription usage in Pi's footer. Uses the shared
// proactive-run snapshot/fetcher when that script is installed.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
const fetcher = join(agentDir, "skills", "proactive-run", "scripts", "codex_usage.sh");
const intervalMs = 5 * 60 * 1000;

type Window = { used_percentage?: number | null; resets_at?: number | null };
type Snapshot = { rate_limits?: { five_hour?: Window; seven_day?: Window }; credit_balance?: number };

function bar(pct: number): string {
  const n = Math.min(10, Math.max(0, Math.floor(pct / 10)));
  return `${"█".repeat(n)}${"░".repeat(10 - n)} ${Math.round(pct)}%`;
}

function resetIn(epoch?: number | null): string {
  if (!epoch) return "";
  const minutes = Math.floor((epoch * 1000 - Date.now()) / 60000);
  if (minutes <= 0) return "";
  if (minutes >= 1440) return ` ~${Math.floor(minutes / 1440)}d${Math.floor(minutes % 1440 / 60)}h`;
  if (minutes >= 60) return ` ~${Math.floor(minutes / 60)}h${minutes % 60}m`;
  return ` ~${minutes}m`;
}

function render(s: Snapshot): string {
  const parts = ([['5h', s.rate_limits?.five_hour], ['7d', s.rate_limits?.seven_day]] as const)
    .filter(([, w]) => typeof w?.used_percentage === "number")
    .map(([label, w]) => `${label}:${bar(w!.used_percentage!)}${resetIn(w?.resets_at)}`);
  if (typeof s.credit_balance === "number") parts.push(`credits:${s.credit_balance}`);
  return parts.length ? parts.join(" | ") : "Codex usage unavailable";
}

export default function (pi: ExtensionAPI) {
  // A template may be instantiated without a Codex login. Loading an
  // extension should not probe a subscription unless this is opted in.
  if (process.env.PI_SHOW_CODEX_USAGE !== "true") return;
  let timer: ReturnType<typeof setInterval> | undefined;
  let busy = false;
  let active = false;

  function refresh(ctx: ExtensionContext) {
    if (!active || busy) return;
    busy = true;
    execFile(fetcher, ["--force"], { timeout: 35000, maxBuffer: 65536 }, (error, stdout) => {
      busy = false;
      if (!active) return;
      if (error) {
        const reason = error.killed ? "timeout" : `fetch ${error.code ?? "failed"}`;
        ctx.ui.setStatus("codex-usage", `Codex usage unavailable (${reason})`);
        return;
      }
      try {
        ctx.ui.setStatus("codex-usage", render(JSON.parse(stdout) as Snapshot));
      } catch {
        ctx.ui.setStatus("codex-usage", "Codex usage unavailable (invalid snapshot)");
      }
    });
  }

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    active = true;
    ctx.ui.setStatus("codex-usage", "Codex usage loading…");
    refresh(ctx);
    if (timer) clearInterval(timer);
    timer = setInterval(() => refresh(ctx), intervalMs);
  });
  pi.on("session_shutdown", (_event, ctx) => {
    active = false;
    if (timer) clearInterval(timer);
    timer = undefined;
    if (ctx.mode === "tui") ctx.ui.setStatus("codex-usage", undefined);
  });
}
