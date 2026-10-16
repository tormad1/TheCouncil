# Unattended operation

Enabled on 16 October 2026 at the human's explicit request, before completion of the original manual calibration period. The override is recorded in `.local/EARLY_SCHEDULING_AUTHORIZED`.

Windows task: `ComputationalArtCollectiveHeartbeat`. It runs the installed Python launcher with `system/run.py heartbeat` in this repository every five minutes. A manually started scheduled heartbeat exited successfully and advanced work 0001 from PROPOSAL_GATE to BUILD. This verifies scheduler execution, not completion of the first artwork.

Keep this PC awake and the same Windows user signed in. The terminal and Codex desktop window do not need to stay open. Local Codex authentication and pinned executable paths must remain valid. Budget pauses, failed stages and requests for attention may prevent a work from completing; no completion guarantee is implied by scheduling.

Pause inference with `council.cmd pause`; resume with `council.cmd resume`. Remove the scheduled task with `system/scheduler/remove-windows.ps1`. Status remains available during a running model job.
