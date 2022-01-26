#!/bin/bash

set -Eeuf -o pipefail
set -x

main() {
  local img=${1:-./nixos-btrfs.img}
  qemu-system-aarch64 \
    -M raspi3b \
    -drive "format=raw,file=${img}" \
    -kernel ./u-boot-rpi3.bin \
    -serial stdio \
    -device usb-kbd \
    -m 1024
}
main "$@"
# -device qemu-xhci,id=xhci \
# -device bus=xhci.0,hostdevice=/dev/bus/usb/001/002 \
# -device usb-mouse \
