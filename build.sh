#!/bin/bash

set -Eeuf -o pipefail
set -x

cleanup() {
  sudo umount -R "${tmpdir}" || true
  sudo losetup -d "${loopdev}" || true
}

trap cleanup INT TERM ERR

main() {
  nix build \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    --show-trace \
    config.system.build.sdImage

  local result
  result=${1:-./result/sd-image/nixos-btrfs.img}
  cp "${result}" ./nixos-btrfs.img

  if [[ ! -r ./u-boot-rpi3.bin ]]; then
    local tmpdir
    tmpdir=$(mktemp -d)
    loopdev=$(sudo losetup --find --partscan --show ./nixos-btrfs.img)
    sudo mount "${loopdev}p1" "${tmpdir}"
    cp "${tmpdir}"/u-boot-rpi3.bin .
    sudo umount -R "${tmpdir}"
    sudo losetup -d "${loopdev}"
  fi

  chown n8henrie:n8henrie ./nixos-btrfs.img
  chmod 0600 ./nixos-btrfs.img
  qemu-img resize -f raw ./nixos-btrfs.img 4G
  ./nixos.sh
}
main "$@"
