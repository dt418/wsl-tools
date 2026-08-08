# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-09

### Added

- Initial public release.
- `wsl-safe-backup-restore.ps1`:
  - `BACKUP ONLY` mode — exports an independent, timestamped VHDX archive without unregistering the distro.
  - `SAFE MOVE / RESTORE` mode — archive backup + live VHDX export, dual validation, explicit confirmation chain, unregister, `--import-in-place`, registration/boot verification, and default-distro restoration.
  - Pre-flight checks: WSL availability, distro existence, WSL2 confirmation, VHDX detection/sanity, writability probes, and free-space checks with a configurable safety margin.
  - Capability checks for `--export --vhd` and `--import-in-place`.
  - Recovery guidance printed if unregister or import fails.
- `run-wsl-safe.cmd`:
  - Launcher that runs a PowerShell parser check before execution and refuses to run the script when syntax validation fails.
- Documentation: README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, and the safety-model deep dive in `docs/SAFETY_MODEL.md`.
- Vietnamese translations of the full documentation set (`*.vi.md`), linked from the English files.
- Validation toolchain: `npm run validate` parses every Mermaid diagram, verifies Markdown fences and internal links, and runs the PowerShell parser check without executing the script (`scripts/validate-docs.mjs`, `scripts/validate-ps1.mjs`, `scripts/validate-ps1.ps1`).
- Git hooks via lefthook: `pre-commit` (docs + PowerShell), `commit-msg` (commitlint / Conventional Commits), `pre-push` (full CI suite).
- GitHub Actions CI: documentation validation, English / Vietnamese docs sync check, PowerShell syntax validation on Windows, and commitlint on pull requests.
- Branch protection on `main` (including admins): require pull requests, required CI checks, conversation resolution, and block force-pushes/deletions.
