/**
 * RTK Rewrite Plugin for OpenClaw
 *
 * Transparently rewrites exec tool commands to RTK equivalents
 * before execution, cutting up to 90% of the bash output that reaches the LLM context.
 *
 * All rewrite logic lives in `rtk rewrite` (src/discover/registry.rs).
 * This plugin is a thin delegate — to add or change rules, edit the
 * Rust registry, not this file.
 *
 * Exit code protocol for `rtk rewrite`:
 *   0 + stdout  Allow — rewrite found, explicitly allowed → auto-apply
 *   1           No RTK equivalent → pass through unchanged
 *   2           Deny rule matched → block the call
 *   3 + stdout  Ask rule matched (or default) → rewrite, require approval
 *
 * See: src/hooks/rewrite_cmd.rs
 */

import { execFileSync } from "node:child_process";

let rtkAvailable: boolean | null = null;

function checkRtk(): boolean {
  if (rtkAvailable !== null) return rtkAvailable;
  try {
    execFileSync("which", ["rtk"], { stdio: "ignore" });
    rtkAvailable = true;
  } catch {
    rtkAvailable = false;
  }
  return rtkAvailable;
}

type RewriteVerdict = "ask" | "deny";

function tryRewrite(command: string): [string | null, RewriteVerdict?] {
  try {
    const result = execFileSync("rtk", ["rewrite", command], {
      encoding: "utf-8",
      timeout: 2000,
    })
      .toString()
      .trim();
    return [result && result !== command ? result : null];
  } catch (e: any) {
    if (e?.status === 3 && e.stdout) {
      const result = e.stdout.toString().trim();
      if (result && result !== command) return [result, "ask"];
      return [null];
    }
    if (e?.status === 2) {
      return [null, "deny"];
    }
    return [null];
  }
}

export default function register(api: any) {
  const pluginConfig = api.config ?? {};
  const enabled = pluginConfig.enabled !== false;
  const verbose = pluginConfig.verbose === true;

  if (!enabled) return;

  if (!checkRtk()) {
    console.warn("[rtk] rtk binary not found in PATH — plugin disabled");
    return;
  }

  api.on(
    "before_tool_call",
    (event: { toolName: string; params: Record<string, unknown> }) => {
      if (event.toolName !== "exec") return;

      const command = event.params?.command;
      if (typeof command !== "string") return;

      const [rewritten, verdict] = tryRewrite(command);

      if (verdict === "deny") {
        if (verbose) {
          console.log(`[rtk] DENY: ${command}`);
        }
        return {
          block: true,
          blockReason: "RTK deny rule matched",
        };
      }

      if (!rewritten) return;

      if (verbose) {
        console.log(
          `[rtk] ${command} -> ${rewritten}${verdict === "ask" ? " (approval required)" : ""}`
        );
      }

      const result: {
        params: Record<string, unknown>;
        requireApproval?: {
          title: string;
          description: string;
          severity: "info";
          timeoutBehavior: "deny";
          allowedDecisions: Array<"allow-once" | "deny">;
          onResolution?: (decision: string) => void;
        };
      } = {
        params: { ...event.params, command: rewritten },
      };

      if (verdict === "ask") {
        result.requireApproval = {
          title: "RTK rewrite suggestion",
          description: `Rewrite: \`${command}\` → \`${rewritten}\``,
          severity: "info",
          timeoutBehavior: "deny",
          allowedDecisions: ["allow-once", "deny"],
          onResolution: (decision: string) => {
            if (verbose) {
              console.log(`[rtk] approval ${decision}: ${command} -> ${rewritten}`);
            }
          },
        };
      }

      return result;
    },
    { priority: 10 }
  );

  if (verbose) {
    console.log("[rtk] OpenClaw plugin registered");
  }
}
