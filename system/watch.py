"""Small live terminal dashboard for the collective's persistent state."""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / ".local" / "current.json"
SPINNER = "|/-\\"
DAY_NAMES = {1: "Monday", 2: "Tuesday", 3: "Wednesday", 4: "Thursday",
             5: "Friday", 6: "Saturday", 7: "Sunday"}
STAGE_NAMES = {
    "PREPARE": "Preparing the day",
    "IDEATE": "Developing an idea",
    "IDEATE_RETRY": "Retrying the idea",
    "PROPOSAL_GATE": "Reviewing the proposal",
    "BUILD": "Building the artwork",
    "VERIFY": "Checking the artwork",
    "VERIFY_AFTER_REPAIR": "Rechecking after a repair",
    "REPAIR_SIMPLE": "Debugging (simple repair)",
    "REPAIR_COMPLEX": "Debugging (complex repair)",
    "PUBLISH": "Publishing the finished work",
    "COMPLETE": "Complete",
    "PAUSED_BUDGET": "Paused by budget rules",
    "NEEDS_ATTENTION": "Needs attention",
    "RESCUE_PENDING": "Waiting for a rescue decision",
    "WAITING_FOR_HUMAN": "Waiting for you",
    "FAILED": "Failed",
}


def read_state() -> tuple[dict | None, float | None, Path | None, str | None]:
    try:
        raw = json.loads(STATE.read_text(encoding="utf-8"))
        state_path = ROOT / ".local" / "runs" / raw["date"] / "state.json"
        touched = state_path.stat().st_mtime if state_path.exists() else STATE.stat().st_mtime
        run_dir = state_path.parent
        pending = []
        for request_path in run_dir.glob("*/stage.requested.json"):
            stage_dir = request_path.parent
            if (stage_dir / "stage.completed.json").exists() or (stage_dir / "stage.failed.json").exists():
                continue
            try:
                request = json.loads(request_path.read_text(encoding="utf-8"))
                pending.append((request_path.stat().st_mtime, request_path, request))
            except (OSError, ValueError):
                continue
        active_call = max(pending, default=None, key=lambda row: row[0])
        if active_call:
            touched = max(touched, active_call[0])
        return raw, touched, active_call[1] if active_call else None, None
    except FileNotFoundError:
        return None, None, None, None
    except (OSError, ValueError, KeyError) as exc:
        return None, None, None, str(exc)


def format_age(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s ago"
    if seconds < 3600:
        return f"{seconds // 60}m {seconds % 60:02d}s ago"
    return f"{seconds // 3600}h {(seconds % 3600) // 60:02d}m ago"


def render(frame: int, refresh: float) -> str:
    state, touched, pending_path, error = read_state()
    now = time.time()
    lines = [
        "THE COUNCIL - LIVE STATUS",
        f"Monitor running {SPINNER[frame % len(SPINNER)]} | refreshes every {refresh:g}s | Ctrl+C to exit",
        "-" * 58,
    ]
    if error:
        lines.extend([f"Could not read current state: {error}", "The dashboard will retry automatically."])
        return "\n".join(lines)
    if state is None:
        lines.extend(["No active work has been allocated yet.", "Waiting for the first run or scheduled heartbeat."])
        return "\n".join(lines)

    work_date = state.get("date", "unknown date")
    day = DAY_NAMES.get(state.get("weekday"), "Unknown day")
    member = state.get("member", "unassigned")
    work_id = state.get("id")
    number = f"{int(work_id):04d}" if isinstance(work_id, (int, float)) else "unallocated"
    status = state.get("state", "UNKNOWN")
    title = (state.get("proposal") or {}).get("title") or "Idea not chosen yet"
    reason = state.get("reason")
    stage = STAGE_NAMES.get(status, status.replace("_", " ").title())
    pending_text = None
    if pending_path:
        try:
            request = json.loads(pending_path.read_text(encoding="utf-8"))
            route = request.get("route", pending_path.parent.name)
            command = request.get("command", [])
            model = command[command.index("--model") + 1] if "--model" in command else "model"
            elapsed = format_age(now - request.get("timestamp", now))
            if (pending_path.parent / "process.json").exists():
                pending_text = f"{route} process ended {elapsed}; waiting for its saved result."
            else:
                pending_text = f"{route} call requested for {model} {elapsed}; waiting for its result."
            reason = None
        except (OSError, ValueError, TypeError, IndexError):
            pending_text = "A model call is awaiting a completion receipt."
            reason = None
    if reason:
        stage += f" | {reason}"

    lines.extend([
        f"Work: {number} | {day}, {work_date} | {member}",
        f"Project: {title}",
        f"Stage: {stage}",
        f"Mode: {state.get('mode', 'unknown')}",
        f"Attempts: {int(state.get('retry', 0) or 0)} idea retries | {int(state.get('repairs', 0) or 0)} debug repairs",
    ])
    if state.get("recovery"):
        lines.append("Mode: historical recovery")
    if (ROOT / ".local" / "PAUSE").exists():
        lines.append("Global pause: ON")
    if touched is not None:
        stamp = datetime.fromtimestamp(touched).astimezone().strftime("%H:%M:%S")
        lines.append(f"Last workflow update: {stamp} ({format_age(now - touched)})")
    if pending_text:
        lines.append(pending_text)
    elif status == "PAUSED_BUDGET" or (reason and reason.lower() == "cooldown"):
        lines.append("The workflow is waiting for its cooldown or budget window; the monitor is still updating.")
    elif status == "WAITING_FOR_HUMAN":
        lines.append("The workflow needs your input before it can continue.")
    elif status == "NEEDS_ATTENTION":
        lines.append("The workflow needs a check; see council.cmd status for the recorded error.")
    elif status == "COMPLETE":
        lines.append("This work is finished.")
    else:
        lines.append("The workflow will advance on its next manual run or scheduled heartbeat.")
    return "\n".join(lines)


def main() -> int:
    try:
        refresh = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    except ValueError:
        print("Usage: council.cmd watch [refresh-seconds]", file=sys.stderr)
        return 2
    if not 0.5 <= refresh <= 60:
        print("Refresh interval must be between 0.5 and 60 seconds.", file=sys.stderr)
        return 2

    frame = 0
    try:
        while True:
            content = render(frame, refresh)
            if sys.stdout.isatty():
                if os.name == "nt":
                    os.system("cls")
                else:
                    sys.stdout.write("\x1b[2J\x1b[H")
            sys.stdout.write(content + "\n")
            sys.stdout.flush()
            frame += 1
            time.sleep(refresh)
    except KeyboardInterrupt:
        print("\nStopped watching.")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
