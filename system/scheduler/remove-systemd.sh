#!/bin/sh
set -eu
systemctl --user disable --now collective.timer
rm -f -- "$HOME/.config/systemd/user/collective.timer" "$HOME/.config/systemd/user/collective.service"
systemctl --user daemon-reload
