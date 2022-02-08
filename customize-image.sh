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

  mount -t btrfs "${part}" "${tmpmount}"
  btrfs filesystem resize max "${tmpmount}"
  mkdir -p "${tmpmount}/root/.ssh"
  cp /home/n8henrie/git/sd_shrink/nixpi_id_rsa.pub "${tmpmount}/root/.ssh/authorized_keys"
  cp ./mountsubvols.sh ./make_swap.sh "${tmpmount}/root/"

  local subvols dest
  subvols=(@ @boot @home @nix @snapshots @swap @var)
  for sv in "${subvols[@]}"; do
    dest="${tmpmount}/${sv}"
    [[ -d "${dest}" ]] || btrfs subvol create "${dest}"
  done
  umount --recursive "${tmpmount}"

  for sv in @ @home @nix @var; do
    dest="${tmpmount}/${sv#@}"
    mkdir -p "${dest}"
    mount -t btrfs -o compress-force=zstd,ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done

  # no compression for these
  for sv in @boot @swap; do
    dest="${tmpmount}/${sv#@}"
    mkdir -p "${dest}"
    mount -o ssd_spread,subvol="${sv}" "${part}" "${dest}"
  done

  # name doesn't match subvol name
  mkdir -p "${tmpmount}/.snapshots"
  mount -o compress-force=zstd,ssd_spread,subvol=@snapshots "${part}" "${tmpmount}/.snapshots"

  mkdir -p "${tmpmount}/etc/nixos"
  find ./nixos -type f -name '*.nix' -exec cp -t "${tmpmount}/etc/nixos/" {} +

  # Populate a little script for making a swapfile
  # I create this script instead of creating the actual swapfile so I don't
  # have an empty 1G file sitting around in the image
  cat << 'EOF' > /mnt/root/make_swap.sh
#!/usr/bin/env bash
cd /mnt/swap
touch ./swapfile
chattr +C ./swapfile
btrfs property set ./swapfile compression none
fallocate -l 1G ./swapfile
chmod 0600 ./swapfile
mkswap ./swapfile
EOF
  chmod +x /mnt/root/make_swap.sh
}
main "$@"
