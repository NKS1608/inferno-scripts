#!/bin/bash
# Companion VM (arm64 Debian, HVF-accelerated). Must be started BEFORE the iPhone VM.
set -euo pipefail
cd "$(dirname "$0")"
rm -f /tmp/InfernoUSBRemote
exec ./Inferno/build/qemu-system-aarch64 \
  -M virt,gic-version=3 -accel hvf -cpu host -m 2G -smp 4 \
  -drive if=pflash,format=raw,readonly=on,file=companion/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=companion/edk2-arm-vars.fd \
  -drive file=companion/debian-generic-arm64.qcow2,if=virtio,format=qcow2 \
  -drive file=companion/seed.iso,if=virtio,format=raw,readonly=on \
  -nic user,model=virtio-net-pci,hostfwd=tcp::32222-:22 \
  -virtfs local,path="$PWD",mount_tag=inferno,security_model=none,readonly=on \
  -usb -device usb-ehci,id=ehci -device usb-tcp-remote,bus=ehci.0 \
  -nographic "$@"
