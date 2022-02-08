#!/usr/bin/env bash
# build.sh: Runs `nix build`, makes a user-owned copy of the image, resizes
# image, runs `nixos.sh`

set -Eeuf -o pipefail
set -x

loopdev=
tmpdir=

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
    -v \
    config.system.build.sdImage

  local result img
  result=${1:-./result/sd-image/nixos-btrfs.img}
  img=nixos-btrfs.img

  cp "${result}" "${img}"
  chown "${USER}:${USER}" "${img}"
  chmod 0600 "${img}"

  # Resize to a a size that qemu finds acceptable
  local sz FOUR_GB
  FOUR_GB=$(numfmt --from=iec 4G)
  sz=$(du -b "${img}" | awk '{ print $1 }')
  if [[ "${sz}" -lt "${FOUR_GB}" ]]; then
    newsz=4G
  else
    newsz=8G
  fi
  qemu-img resize -f raw "${img}" "${newsz}"

  if [[ -n "${CUSTOMIZE_NIX_IMAGE}" ]]; then
    sudo ./customize-image.sh "${img}"
  fi

  if [[ ! -r ./u-boot-rpi3.bin ]]; then
    sudo ./copy-kernel.sh "${img}"
  fi

  ./nixos.sh "${img}"

}
main "$@"
