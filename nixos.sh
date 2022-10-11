#!/usr/bin/env bash
# Run the image in QEMU

# $ qemu-system-aarch64 --version
# QEMU emulator version 6.2.0
# Copyright (c) 2003-2021 Fabrice Bellard and the QEMU Project developers
#
# Notes on `console=` and getting terminal output:
#   - `-nographic` alone allows seeing kernel messages during boot
#   - Changing the serial devices in `-append` doesn't seem to matter, only changing the `kernalParams` results in changing extlinux.conf which takes effect
#   - ttyAMA0 seems to allow the kernel messages and systemd messages but no login prompt
#   - ttyS0, tty0, ttyUSB0 all seem nonfunctional? no output (perhaps overridden by my qemu args?)
#   https://tldp.org/HOWTO/Remote-Serial-Console-HOWTO/configure-kernel.html
#   - The console parameter can be given repeatedly, but the parameter can only be given once for each console technology. So console=tty0 console=lp0 console=ttyS0 is acceptable but console=ttyS0 console=ttyS1 will not work.
#   - When multiple consoles are listed output is sent to all consoles and input is taken from the last listed console. The last console is the one Linux uses as the /dev/console device.

set -Eeuf -o pipefail
set -x

main() {
  local img=${1:-./btrfspi.iso}
  qemu-system-aarch64 \
    -M raspi3b \
    -m 1G \
    -smp 4 \
    -drive "format=raw,if=sd,file=${img}" \
    -kernel ./u-boot-rpi3.bin \
    -usb -device usb-kbd \
    -device usb-net,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -serial null \
    -serial mon:stdio \
    -append 'root=/dev/mmcblk0p2 rootfstype=btrfs rootflags=subvol=@ rootwait'
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
