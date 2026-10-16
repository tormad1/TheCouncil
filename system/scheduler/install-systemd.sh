#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
[ "${1:-}" = "--enable" ] || { echo 'Pass --enable after acceptance and observed manual days.' >&2; exit 1; }
[ -f "$repo/.local/ACCEPTANCE_PASSED" ] && [ -f "$repo/.local/MANUAL_DAYS_CONFIRMED" ] || { echo 'Acceptance and manual-day confirmation required.' >&2; exit 1; }
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/collective.service" <<EOF
[Unit]
Description=Computational art studio heartbeat
[Service]
Type=oneshot
WorkingDirectory=$repo
ExecStart=/usr/bin/env lua system/heartbeat.lua
TimeoutStartSec=2h
EOF
cat > "$HOME/.config/systemd/user/collective.timer" <<EOF
[Unit]
Description=Local five-minute art studio heartbeat
[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now collective.timer
