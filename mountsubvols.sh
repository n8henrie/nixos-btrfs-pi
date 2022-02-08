#!/usr/bin/env bash

set -Eeuf -o pipefail
set -x

main() {
  local mpoint part
  mpoint=${1:-/mnt}
  part=$(findmnt -n -o SOURCE --nofsroot /)

  for sv in @ @home @nix @var; do
    dest=${mpoint}/${sv#@}
    mkdir -p "${dest}"
    mount -o compress-force=zstd,ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done
  # no compression for these
  for sv in @boot @swap; do
    dest=${mpoint}/${sv#@}
    mkdir -p "${dest}"
    mount -o ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done

  # name doesn't match subvol name
  mkdir -p "${mpoint}/.snapshots"
  mount -o compress-force=zstd,ssd_spread,subvol=@snapshots "${part}" "${mpoint}/.snapshots"
}
main "$@"
