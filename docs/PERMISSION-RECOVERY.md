# Windows builder permission recovery

The first build and its simple repair made real model calls but could not write files. The gateway requested `workspace-write` while also using `--ignore-user-config`. That removed the saved Windows sandbox selection. A no-inference `codex debug prompt-input` comparison reproduced the downgrade: without a Windows backend, the model-visible mode was `read-only`; explicitly selecting MXC restored `workspace-write`.

The gateway now selects `windows.sandbox="mxc"` explicitly on Windows. Its trusted host keeps an explicit non-secret environment allowlist, including the Windows runtime paths MXC needs. Model shells inherit only that sanitized environment. The login-shell prohibition was removed so ordinary model command invocations do not fail before sandbox execution.

Before a paid build or repair, `system/preflight.py` executes a no-inference sandbox check inside the assigned staging directory. It requires both an allowed staging write and denial of a protected sibling write. A failed check stops before invocation receipts or model-usage reservations are created.

The permission failure for work 0001 was retained in the existing receipts and paid usage ledger. With explicit human authorization, the work was reset to BUILD with `build_attempt=1`, a fresh build/repair receipt namespace and an unchanged proposal. The exhausted repair allowance was reset because the previous attempt never reached construction. No Astra escalation was used.

The offline sandbox also blocks Java's internal loopback sockets and the local preview server. A fixed-operation file request channel now lets the builder request preview from a trusted verifier outside its sandbox. The model remains offline; the trusted verifier uses pinned Bob and a local browser with outbound requests blocked. The preview service exists only during a maker/repair stage. A native MXC client-to-verifier integration test covers compilation, HTML5 runtime, F1 capture and a title containing Windows-forbidden punctuation.

Bob uses the project title as a directory name. The title's question mark made bundling fail on Windows. The build helper now supplies a safe platform label through Bob's settings override, preserving the authored source, manifest title and visible artwork title.

Forty offline acceptance tests passed after these changes. The exact sanitized-launch preflight also passed. The live rebuild completed on 16 October 2026 and reached COMPLETE after external build/runtime/preview verification. Work 0001 is archived under `works/0001-which-way-is-delete` in commit `d7405e6`; the member's nonexhibition decision was retained. No additional artistic call was used to redo that decision.

## Historical work 0002 browser-check incident

Work 0002's automated verification reported that Playwright's pinned headless-shell executable was missing. The file was present in the user's Playwright cache, the configured Playwright 1.55.0 package could launch Chromium, and the complete Defold build/runtime/interaction preview passed when rerun at 21:22 and 21:25. The saved evidence does not establish why the scheduled verification saw a different result; treat it as a transient or launch-context failure, not a confirmed missing installation.

The recovery path now pins Playwright's resolved Chromium executable first, records Python/package/browser-path diagnostics on launch failure, classifies browser-launch failures as infrastructure, and retries infrastructure verification twice without paying for a repair model. `council.cmd recheck <id>` can resume deterministic verification from `RESCUE_PENDING`. Work 0002 passed this recheck and reached COMPLETE without another model call, in commit `0a67b82`.

References: [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox), [non-interactive configuration](https://learn.chatgpt.com/docs/non-interactive-mode), [environment policy](https://learn.chatgpt.com/docs/config-file/config-advanced).
