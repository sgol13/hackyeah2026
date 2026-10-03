#!/bin/bash
# Start/stop the Oniro (OpenHarmony 6.1) QEMU emulator inside WSL2 with KVM.
#
# Runs run.sh from the Oniro emulator release as a transient systemd unit so the
# emulator survives the wsl.exe call that started it. The SDL window shows up on
# the Windows desktop through WSLg; hdc reaches it at 127.0.0.1:55555.
#
# Usage (from Windows):
#   wsl -u root -- bash scripts/emulator.sh start   [IMAGE_DIR]
#   wsl -u root -- bash scripts/emulator.sh stop | status
# IMAGE_DIR defaults to ~/oniro/images of the default WSL user (uid 1000).
set -euo pipefail

UNIT=oniro-emu
USER_NAME=$(getent passwd 1000 | cut -d: -f1)
USER_HOME=$(getent passwd 1000 | cut -d: -f6)
IMAGE_DIR=${2:-$USER_HOME/oniro/images}

case "${1:-start}" in
  start)
    if systemctl is-active --quiet "$UNIT"; then echo "emulator already running"; exit 0; fi
    [[ -x "$IMAGE_DIR/run.sh" ]] || { echo "run.sh not found in $IMAGE_DIR" >&2; exit 1; }
    systemctl reset-failed "$UNIT" 2>/dev/null || true
    systemd-run --unit="$UNIT" --uid="$USER_NAME" --gid="$USER_NAME" \
      --working-directory="$IMAGE_DIR" \
      --setenv=HOME="$USER_HOME" \
      --setenv=DISPLAY=:0 --setenv=WAYLAND_DISPLAY=wayland-0 \
      --setenv=XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir \
      --setenv=PULSE_SERVER=unix:/mnt/wslg/PulseServer \
      "$IMAGE_DIR/run.sh" -s 6 -m 4096M
    echo "emulator starting; wait ~40 s, then: hdc tconn 127.0.0.1:55555"
    ;;
  stop)
    systemctl stop "$UNIT" || true
    ;;
  status)
    systemctl --no-pager status "$UNIT" | head -5
    ;;
  *)
    echo "usage: $0 start [IMAGE_DIR] | stop | status" >&2; exit 2
    ;;
esac
