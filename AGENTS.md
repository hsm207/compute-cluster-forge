# Agent Execution Guidelines: Remote VM & Background Task Invariants

## 1. GCP Dev Machine Provisioning (Preferred Workflow)
- **DO NOT run raw Terraform (`terraform apply`) for provisioning dev boxes.** 
  The Terraform scripts in this repository represent a work-in-progress (WIP) exploration for long-term cross-cloud scaling and are not production-ready for daily development.
- **ALWAYS use the modular Python CLI (`forge`)** to launch and manage ephemeral dev machines on GCP:
  ```powershell
  python -m forge launch <workspace>
  # To destroy active clusters and clean up templates:
  python -m forge teardown --all
  ```
  *(e.g., `python -m forge launch freebuff` or `python -m forge teardown`)*.
- Refer to [`docs/guides/dev_spot_machine_guide.md`](docs/guides/dev_spot_machine_guide.md) for full runbook details, preemption mechanics, and recovery procedures.

## 2. SSH over Google IAP on Windows: The Stdin Rule
When executing `ssh` to GCP instances routed through the IAP proxy (`dev-box` or `iap_proxy.ps1`) via `run_command`:
- **NEVER** run bare `ssh <host> "<cmd>"`.
- **ALWAYS** redirect stdin or use `-n` (`ssh -n dev-box "<cmd>"` or `ssh dev-box "<cmd>" < /dev/null`). On PowerShell, pipe `$null` or use `-n`.
- **ALWAYS** set explicit connection and execution timeouts:
  `ssh -n -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 dev-box "<cmd>"`

## 3. Background Task Liveness & Watchdog Invariant
- Never launch a background task that is expected to finish within seconds or minutes and remain passive indefinitely.
- If a command is sent to background with `run_command`, and it does not finish within expected run duration (e.g. 30 seconds for a script, 2 minutes for a build):
  - Set a `schedule` one-shot timer for a tight watchdog duration (`DurationSeconds=30` to `60`).
  - When the timer fires, inspect `manage_task(status)` immediately.
  - If the task is stalled or hung, kill it (`manage_task(kill)`) and diagnose the root cause immediately rather than waiting.

## 4. GCP Metadata Script Execution Rule
- Do NOT assume GCP startup or shutdown scripts are written to `/usr/local/bin/` or run via ad-hoc bash wrappers.
- Use the official Google Guest Agent runner to invoke or test them:
  - Startup: `sudo google_metadata_script_runner startup`
  - Shutdown: `sudo google_metadata_script_runner shutdown`
- Always verify the script path and metadata key (`shutdown-script`, `startup-script`) before invoking.
