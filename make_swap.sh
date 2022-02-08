#!/usr/bin/env bash

set -Eeuf -o pipefail
set -x

main() {
  umount -R /mnt/swap || true
  mkdir -p /mnt/swap
  mount -o subvol=@swap /dev/mmcblk0p2 /mnt/swap
  cd /mnt/swap
  touch ./swapfile
  chattr +C ./swapfile
  btrfs property set ./swapfile compression none
  fallocate -l 1G ./swapfile
  chmod 0600 ./swapfile
  mkswap ./swapfile
}
main "$@"
