#!/usr/bin/env bash

# - Create my preferred layout of subvolumes
# - Copy the boot files to the `@` (root) subvolume
# - Copy my ssh public key
# - Copy my nix configuration files

set -Eeuf -o pipefail
set -x

loopdev=
tmpmount=

cleanup() {
  mountpoint "${tmpmount}" && umount --recursive "${tmpmount}"
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}"
}
trap cleanup EXIT

main() {
  tmpmount=$(mktemp -d)
  loopdev=$(losetup --find --partscan --show ./nixos-btrfs.img)
  part=${loopdev}p2

  btrfs device scan --forget

  mount -t btrfs -o compress-force=zstd,ssd_spread "${part}" "${tmpmount}"
  btrfs filesystem resize max "${tmpmount}"

  local subvols dest
  subvols=(@ @boot @home @nix @snapshots @swap @var)
  for sv in "${subvols[@]}"; do
    dest="${tmpmount}/${sv}"
    [[ -d "${dest}" ]] || btrfs subvol create "${dest}"
  done

  for dir in nix boot; do
    find "${tmpmount}/${dir}" -mindepth 1 -maxdepth 1 -exec mv -t "${tmpmount}/@${dir}" -- {} +
    rm -r "${tmpmount:?}/${dir}"
  done
  mv "${tmpmount}/nix-path-registration" "${tmpmount}/@/"
  umount --recursive "${tmpmount}"

  # mount with compression
  local compsubvs=(@ @home @nix @snapshots @var)
  for sv in "${compsubvs[@]}"; do
    dest="${tmpmount}/${sv#@}"
    mkdir -p "${dest}"
    mount -t btrfs -o compress-force=zstd,ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done

  # name doesn't match name of subvolume
  mkdir -p "${tmpmount}/.snapshots"
  mount -t btrfs -o compress-force=zstd,ssd_spread,subvol=@snapshots "${part}" "${tmpmount}/.snapshots"

  # no compression for these
  local nocompsubvs=(@boot @swap)
  for sv in "${nocompsubvs[@]}"; do
    dest="${tmpmount}/${sv#@}"
    mkdir -p "${dest}"
    mount -t btrfs -o ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done

  mkdir -p \
    "${tmpmount}/etc/nixos" \
    "${tmpmount}/root/.ssh"

  cp /home/n8henrie/git/sd_shrink/nixpi_id_rsa.pub "${tmpmount}/root/.ssh/authorized_keys"
  cp ./mountsubvols.sh ./setup.sh "${tmpmount}/root/"
  find ./nixos -type f -name '*.nix' -not -name '*-sample.nix' -exec cp -t "${tmpmount}/etc/nixos/" {} +
}
main "$@"
