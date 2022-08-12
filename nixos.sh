#!/usr/bin/env bash
# Run the image in QEMU

# $ qemu-system-aarch64 --version
# QEMU emulator version 6.2.0
# Copyright (c) 2003-2021 Fabrice Bellard and the QEMU Project developers

set -Eeuf -o pipefail
set -x

main() {
  local img=${1:-./nixos-btrfs.img}
  qemu-system-aarch64 \
    -M raspi3b \
    -dtb dtbs/bcm2710-rpi-3-b.dtb \
    -m 1G \
    -smp 4 \
    -drive "format=raw,file=${img}" \
    -kernel ./u-boot-rpi3.bin \
    -usb -device usb-kbd \
    -device usb-net,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -append "rw console=ttyS0 root=LABEL=NIXOS_SD rootfstype=btrfs" \
    -nographic
}

main "$@"

# None of these seem to get the keyboard or SSH working unfortunately.
# -append "console=ttyS0,115200n8 console=ttyAMA0,115200n8 console=tty0"
# -append "rw console=tty1 root=LABEL=NIXOS_SD rootfstype=btrfs" \
# -device usb-kbd \
# -device usb-mouse \
# -device usb-net,netdev=net0 \
# -dtb ./dtbs/bcm2837-rpi-3-b-plus.dts \
# -net nic -net user,hostfwd=tcp::2222-:22 \
# -netdev user,id=net0,hostfwd=tcp::2222-:22 \
# -nographic \
# -serial stdio \
# -usb -device usb-host,hostbus=001,hostaddr=002 \
