#!/usr/bin/env bash

set -Eeuf -o pipefail
set -x

make_swap() {
  local swapfile=/mnt/swap/swapfile

  [[ -e "${swapfile}" ]] && {
    swapon "${swapfile}" || return 0
    umount -R /mnt/swap
    return 0
  }

  umount -R /mnt/swap || true
  mkdir -p /mnt/swap
  chmod 0700 /mnt/swap
  mount -o subvol=@swap /dev/mmcblk0p2 /mnt/swap
  pushd /mnt/swap
  touch "${swapfile}"
  chmod 0600 "${swapfile}"
  btrfs property set "${swapfile}" compression none
  dd if=/dev/zero of="${swapfile}" bs=1M count=1024 status=progress conv=fsync
  mkswap "${swapfile}"
  swapon "${swapfile}"
  popd
}

install() {
  nix-channel --update
  nixos-install \
    --root / \
    --no-root-passwd \
    --max-jobs "$(nproc)"
}

main() {
  # make_swap
  install
  reboot
}

main "$@"
