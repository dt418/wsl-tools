# Contributing to WSL Safe Backup / Move / Restore

Thanks for your interest in contributing! This project is a small, safety-critical tool: a bug here can destroy a WSL distro. The bar for changes that touch the destructive path is intentionally high, and every reviewer will ask *"what happens if this check is skipped or fails?"*

## Project scope

- Backup, move, and restore flows for WSL2 distros (Microsoft Store installs).
- The launcher (`run-wsl-safe.cmd`) and its syntax pre-check.
- Documentation that explains the safety model.

## Getting started

No build step is required. The project runs on stock Windows PowerShell 5.1+.

To validate your changes, run the same parser check the launcher uses:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorList=$null; $TokenList=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\wsl-safe-backup-restore.ps1'),[ref]$TokenList,[ref]$ErrorList) > $null; if($ErrorList.Count -gt 0){ $ErrorList | ForEach-Object { Write-Host ('Line {0}, Col {1}: {2}' -f $_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message) }; exit 1 } else { Write-Host '[OK] Syntax valid.'; exit 0 }"
```

## Validation

Before submitting changes, run the full validation suite:

```powershell
npm install
npm run validate
```

This runs two checks:

- **Documentation validation** (`npm run validate:docs`) — parses every `mermaid` diagram (via `scripts/validate-docs.mjs`), verifies that every Markdown code fence is balanced, and checks that every internal Markdown link resolves to a real file.
- **PowerShell syntax validation** (`npm run validate:ps1`) — the same parser check the launcher performs, without executing the script (`scripts/validate-ps1.mjs` + `scripts/validate-ps1.ps1`). On non-Windows systems this step is skipped automatically.

For the full CI suite (validation + English / Vietnamese documentation sync):

```powershell
npm run ci
```

Git hooks are managed by [lefthook](https://github.com/evilmartians/lefthook):

- `pre-commit` — validates staged Markdown and PowerShell files
- `commit-msg` — enforces Conventional Commits via commitlint
- `pre-push` — runs the full `npm run ci` suite

Install hooks after cloning:

```powershell
npx lefthook install
```

## Testing

> **Warning:** the MOVE flow shuts down WSL and calls `wsl --unregister`. Only test the full flow on a disposable distro or a machine you can afford to lose, and always keep your own backups.

- **BACKUP ONLY** — safe to test on a real machine.
- **SAFE MOVE / RESTORE** — test in a VM or with a throwaway distro before relying on it.

If you changed behavior, describe exactly what you tested in the pull request description.

## Guidelines

- Follow the existing style: comment banners, `Stop-Script` / `Exit-Safely` helpers, sectioned `Write-Host` output, and `wsl --export ... --vhd`-based exports.
- **Never weaken a safety gate.** A change that removes, skips, reorders, or bypasses a validation step will be challenged in review, and usually rejected without strong justification.
- Keep destructive operations behind the same confirmation chain (menu confirmation, danger-zone confirmation, typed `RESTORE`, last-second checks).
- Do not introduce silent overwrites of existing files.
- Prefer small, additive pull requests; update the README/CHANGELOG when behavior changes.
- Use approved PowerShell verbs and keep functions focused; the existing helpers should be reused rather than duplicated.

## Commit messages

Use short, imperative summaries (e.g. `Fix live VHDX size check`, `Document failure recovery matrix`). If the change touches the safety model, say so in the body.

## Pull requests

1. Explain *why* the change is needed and link any related issue.
2. Describe the testing you performed.
3. Update the CHANGELOG and documentation if user-visible behavior changed.
4. Keep the diff focused — unrelated formatting changes make review harder.

## Branch protection

`main` is protected for everyone, including admins:

- Changes must go through a pull request
- Required status checks must pass:
  - `Validate documentation`
  - `Validate PowerShell syntax`
- Stale reviews are dismissed when new commits are pushed
- Conversations must be resolved before merge
- Force-pushes and branch deletion are blocked

## Questions

Open an issue if you are unsure whether a change fits the project before investing time in a large PR.
