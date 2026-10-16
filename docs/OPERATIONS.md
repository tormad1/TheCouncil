# Studio operation

Make one small complete thing. The idea should be more interesting than its implementation.

The repository is the collection. Published works live under `works/`; machine-local operational state is under ignored `.local/`. The configured Windows installation has live inference and unattended scheduling enabled. A fresh checkout still needs its own setup, readiness checks and explicit scheduling authorization. Synthetic test works exist only in disposable test repositories.

## Installed on this machine

Pinned Bob/Defold 1.13.2, Temurin JRE 25.0.1+8, resvg 0.45.1, a small Phosphor 2.1.1 Regular subset and its MIT licence, Lua 5.4 through Lupa 2.6, timezone data, Playwright 1.55.0 and its Chromium are installed. Tool binaries and Python packages are in `.local/`; Chromium uses Playwright's normal per-user cache. `toolchain.lock` records source versions and downloaded binary SHA-256 values. Do not upgrade during daily work.

Python 3.12+ is the small OS bridge for atomic replacement/fsync, process timeouts, locks and IANA timezone conversion. Creative workflow and policy are Lua. A native Lua executable is optional: `python system/run.py` runs the same Lua entry point. On Windows, `council.cmd` is a convenience wrapper.

From this repository:

```powershell
python system/run.py status
python system/run.py dry-run
python system/run.py usage
python system/tests.py
python system/toolchain_tests.py
python system/sandbox_probe.py
```

With Lua installed, the specified interface is `lua system/council.lua <command>`. Set `COUNCIL_PYTHON` to a Python executable if it is not named `python`. Native Lua's bridge runs Python subprocesses; use the Python launcher for faster embedded calls.

On a fresh machine, run `python system/setup.py --install` once. Setup downloads only pinned infrastructure and the approved icon subset; it never invokes a model or installs scheduling. On Linux, install OpenJDK 25 before setup; the current installer supports Windows x64 and Linux x64. Rerun all three verification commands on the new machine. Do not copy readiness marker files between machines.

The source ZIP excludes Git history. After extracting it, initialize Git and commit the foundation using your normal identity before daily publication. The installation in `D:\Council\Council Github\TheCouncil` preserves your existing checkout and supplies the implementation as working-tree changes for review and commit.

## Commands

| Command | Purpose |
|---|---|
| `status`, `today` | Inspect the clock and active work |
| `watch [seconds]` | Keep a live terminal dashboard open; shows the work date/member, title, stage, retry/repair counts and last workflow update. Press Ctrl+C to exit. |
| `run` | Advance deterministic transitions and at most one inference stage |
| `heartbeat` | Advance at most one persistent transition |
| `pause`, `resume` | Create/remove `.local/PAUSE`; resume does not override budget policy |
| `usage` | Rolling seven-day counts, five-hour activity and calibration reminder |
| `words` | Create the current ISO week's fixed three-word file if absent |
| `validate <id-or-path>` | Deterministic checks; published works are copied into a validation cache |
| `preview <staging-path>` | Builder-only verification within `.local/workspaces/`, available while the heartbeat owns its lock |
| `build-workspace <path>` | Pinned Bob HTML5 build and JSON report |
| `rescue <id> astra-low` / `astra-medium` | Explicit manual rescue from `RESCUE_PENDING`; bypass automatic Astra cap |
| `recheck <id>` | Re-run deterministic verification from `RESCUE_PENDING` without spending a model call |
| `recover YYYY-MM-DD` | Explicitly select/allocate a historical day; continue with `run` |
| `readme` | Regenerate the collection's front page deterministically |
| `dry-run` | Print route, model, effort, context bytes, sandbox, argv and budget decision |

SVG conversion: `lua system/tool.lua rasterize input.svg output.png 512 512`.

In mock mode `run`/`heartbeat` use fixtures. **Use disposable copies for rehearsals**: mock mode can publish synthetic works to its own repository. The acceptance suite handles this isolation automatically and never touches real catalogue entries.

## Before the first real day

1. Choose the project name in `config.lua`. Supply or approve licensed fonts in `shared/fonts/`; no arbitrary typeface has been selected. The hidden technical signature currently uses Defold's built-in debug font.
2. Read `docs/acceptance-results.json`, `docs/toolchain-results.json` and `docs/sandbox-results.json`. Re-run checks after infrastructure changes. The gateway requires their local readiness markers in addition to `live_ready`.
3. Ensure the local authenticated Codex CLI supports the configured model IDs. The requested aliases are preserved; no live model availability or account-quota probe has been performed.
4. Leave `first_live_manual_done=false`. Set `live_ai=true` and `live_ready=true` only when ready to spend model allowance. Existing mock work cannot change to live mode: finish/abandon the disposable rehearsal instead.
5. Manually invoke `run` and inspect `.local/runs/<date>/`. Repeat `run` across the ideation, build and verification/publication boundaries. Each inference is a separate bounded process. Heartbeats cannot start the first live day unattended.
6. After several observed successful manual days, set `first_live_manual_done=true` and create `.local/MANUAL_DAYS_CONFIRMED` as the explicit installation confirmation. Only then install the scheduler. Windows installer: `system/scheduler/install-windows.ps1 -Enable -Python python`; Linux: `sh system/scheduler/install-systemd.sh --enable` with native `lua` on PATH.

Unattended scheduling is enabled on the configured installation. Git push is not implemented or attempted; publication uses local commits. The repository needs a configured Git committer name/email before the first live publication. Member names are recorded in manifests.

## Wednesday: Morrow

Morrow infers hidden properties from indirect evidence with quiet, excessive certainty. Tests, questionnaires, profiles, scoring and forensic reconstruction are natural routes. His Palimpsest worldview need not appear in each work. See `members/wednesday-morrow.md` and [Creative context](CREATIVE-CONTEXT.md).

## Recovery and failure

Every inference route has `stage.requested.json` and, on success, `stage.completed.json`. Completed stages return their retained result after restart without repeating inference. A request without a completed receipt becomes `NEEDS_ATTENTION`, even if the child might have finished: inspect process logs and answer manually. Never delete an uncertain request to force another paid call. If completion is proven by a successful process report and valid final JSON, the human may restore a completed receipt with the original invocation id and result, then restore the corresponding stage state. This deliberately conservative ambiguity requires human attention.

Unknown/failed invocations remain charged in the live usage ledger. Mock events are labelled and excluded from quota counts. Internal caps are studio safeguards, not estimates of account allowance. Compare against supported Codex usage surfaces during calibration. Budget pause rechecks local conditions without launching a job; no emergency artwork or automatic Astra call fills a missing day.

The publication journal makes work copy, catalogue append, exhibition update, README rendering and Git commit retryable. Work hashes are compared against successful verification and publication receipts. A publication interrupted by an unrelated staged Git change remains in `PUBLISH` with a reason; resolve the staging issue and heartbeat again. The system never commits unrelated staged files.

The lock is an atomic directory with owner PID, timestamp, state and work id. Reclamation requires both the generous six-hour timeout and proof the owner process is gone. An incomplete owner record is conservatively left for manual inspection.

## Boundaries and validation

The only model gateway is `system/codex.lua`. It ignores user configuration/rules, invokes an ephemeral Codex process, removes inherited shell secrets, disables builder network access, and grants workspace writes only to the staging workspace. Published objects are additionally sealed read-only and checked by hash. The OS sandbox probe exercises a real prohibited sibling write without inference. These controls constrain writes; they do not claim whole-machine read isolation. Use a dedicated OS account/container for stronger read isolation on a production installation.

Static JSON/CSV/SVG parse checks, unsafe filename/link checks, source scope warnings, unfinished markers, resource URLs, Defold dependency declarations, Bob compilation, bounded browser runtime, console errors, F1 signature capture and screenshots provide technical evidence. Verification does not establish artistic quality or prove every possible behaviour. The member owns the work and performs its refinement inside the build session.

A native Lua launch, Linux scheduling, and an authenticated live inference have not been exercised on this Windows machine. The model gateway command is assembled from the installed CLI help and official documentation; live mode remains disabled for the specified first manual rehearsal.

## References

- [Implementation specification](implementation-specification.md)
- [Official Codex CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli)
- [Official Codex permission profiles](https://learn.chatgpt.com/docs/permissions)
- [Defold Bob](https://defold.com/manuals/bob/)
- [Defold custom resources](https://defold.com/manuals/project-settings/)
- [Phosphor core 2.1.1](https://www.npmjs.com/package/@phosphor-icons/core/v/2.1.1)
