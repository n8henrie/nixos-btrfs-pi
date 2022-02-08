#!/usr/bin/env bash
# copy-kernel.sh: Convenience script to mount the image and copy the kernel
# locally for use with `nixos.sh`. Delete `./u-boot-rpi3.bin` to copy a fresh
# version next run.

set -Eeuf -o pipefail
set -x

loopdev=
tmpmount=

cleanup() {
  mountpoint "${tmpmount}" && umount -R "${tmpmount}"
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}"
}
trap cleanup EXIT

main() {
  img=$1
  tmpmount=$(mktemp -d)
  loopdev=$(losetup --find --partscan --show "${img}")

  mount "${loopdev}p1" "${tmpmount}"
  cp "${tmpmount}/u-boot-rpi3.bin" .
}
main "$@"
