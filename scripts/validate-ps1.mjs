#!/usr/bin/env node
/**
 * Runs the same PowerShell parser check as run-wsl-safe.cmd,
 * without executing wsl-safe-backup-restore.ps1.
 * Skipped automatically on non-Windows platforms.
 *
 * Usage: npm run validate:ps1
 */
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

if (process.platform !== "win32") {
  console.log("[SKIP] PowerShell syntax check only runs on Windows.");
  process.exit(0);
}

try {
  execFileSync(
    "powershell.exe",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(root, "scripts", "validate-ps1.ps1"),
    ],
    { stdio: "inherit" }
  );
} catch {
  process.exit(1);
}
