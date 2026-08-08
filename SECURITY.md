# Security Policy

This project operates with destructive privileges over WSL registrations and VHDX files. Security issues are taken seriously, including issues that could trick a user into data loss.

## Supported versions

Only the latest commit on the default branch is supported. There are no backport releases at this time.

## Reporting a vulnerability

Please report issues by opening a GitHub issue in this repository.

When reporting:

- Describe the issue and the conditions needed to trigger it.
- Do **not** include personal data, private VHDX paths, or full machine identifiers.
- If you discovered a weakness in the safety model (e.g. a path where data could be lost despite the guarantees), mark the issue clearly as a safety-model bug.

There is no private reporting channel configured yet. If that changes, this policy will be updated.

## Safety-relevant design notes

- The only destructive operation is `wsl --unregister <distro>`.
- Unregister is only reachable after: two independently validated VHDX exports, a danger-zone confirmation, a typed `RESTORE` confirmation, and last-second re-validation.
- The script never overwrites an existing file; it refuses to start when a destination already exists.
- Archive backup and live VHDX are never the same file, and a same-path check blocks unregister if they unexpectedly resolve identically.
- Paths are compared case-insensitively after normalization; environment-variable expansion is applied before comparison.
- The launcher (`run-wsl-safe.cmd`) runs a PowerShell parser check and refuses to execute the script when syntax validation fails, reducing the risk of running a corrupted script.

## Responsible disclosure

Please allow time for a fix and a release before publicly discussing a vulnerability. For safety-model defects specifically, we ask that you do not publish reproduction steps that could cause data loss for other users before a fix lands.
