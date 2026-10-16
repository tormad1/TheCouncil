# Implementation delivery

The studio is implemented and remains in AI-disabled mode. No real artwork has been generated and no scheduler has been installed.

Start in this directory with `python system/run.py status` (or `council.cmd status` on Windows). Read [studio operation](OPERATIONS.md) before enabling live mode.

Validation completed on Windows:

- 36 offline acceptance tests, including a full synthetic week, Wednesday, duplicate retry, repair cap, budget denial, crash receipts, missed dates, curation and exactly-once Git commits.
- Real pinned Bob compilation and HTML5 bundle, bounded Chromium runtime, console checks, preview and F1 identity overlay.
- Real resvg conversion and a Codex OS sandbox write-denial probe.
- Zero model invocations during tests. All synthetic publication tests use disposable repositories.

The test reports are saved alongside this file. The installed tools remain under ignored `.local/`; the portable source ZIP excludes tools, temporary files and Git history. Fresh machines require explicit setup and revalidation.

The current installation is `D:\Council\Council Github\TheCouncil`, inside the existing `tormad1/TheCouncil` checkout. Its original Git history and remote are preserved; the implementation is supplied as uncommitted working-tree changes. The original README is backed up under `.local/migration-backup/`.

The relocation review fixed builder previews being blocked by the heartbeat lock, made status and the kill switch available during a build, checked all curation decisions before public writes, restricted publication commit recovery to exact trailers in the current branch, and made missing Bob return a normal verification failure. All three validation commands were rerun from the destination with zero model calls.

The first manual live attempt failed before process creation because Windows could not resolve the bare Codex command. Local configuration now records the full installed executable path, and process-launch failures are distinguished from started jobs in usage accounting. The failed launch receipts are archived and work 0001 is restored to IDEATE. During this diagnosis the test harness inherited live configuration and briefly launched a Codex process; it was terminated, its allowance usage is unknown and remains conservatively reserved in the operational ledger. Tests now reset production memory, force mock mode, and independently block real model executables. The subsequent 36-test run passed with those safeguards.

Human setup remains deliberate: choose a name and licensed fonts, configure normal Git authorship, then observe the first live day manually. Live model/account availability is untested. Linux scheduling and native-Lua launching are provided but untested on this machine. Python's embedded Lua launcher is tested here. Git push remains disabled/unimplemented.
