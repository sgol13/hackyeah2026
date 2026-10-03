#!/bin/bash
# qemu-system-x86_64 wrapper for Oniro's run.sh (passed with `run.sh -q <this file>`).
# Adds an absolute pointing device (virtio tablet; the guest kernel has virtio_input).
# Without it the only pointer is a relative PS/2 mouse, and in the SDL window under WSLg
# its movement arrives mirrored in the guest (moving down moves the cursor up).
case "${1:-}" in
  --version|-device) exec qemu-system-x86_64 "$@" ;;  # run.sh's capability probes
esac
exec qemu-system-x86_64 "$@" -device virtio-tablet-pci
