#!/usr/bin/env bash
# build.sh: Runs `nix build`, makes a user-owned copy of the image, resizes
# image, runs `nixos.sh`

set -Eeuf -o pipefail
set -x

loopdev=
tmpdir=

cleanup() {
  sudo -n umount -R "${tmpdir}" || true
  sudo -n losetup -d "${loopdev}" || true
}

trap cleanup INT TERM ERR

user_main() {
  [[ -r ./config.env ]] && source ./config.env
  nix build

  local result img
  result=${1:-./result/btrfspi.iso}
  img=btrfspi.iso

  cp "${result}" "${img}"
  chown "${USER}:${USER}" "${img}"
  chmod 0600 "${img}"

  # Resize to a a size that qemu finds acceptable
  if [[ -z "${NO_RESIZE:-}" ]]; then
    local sz FOUR_GB
    FOUR_GB=$(numfmt --from=iec 4G)
    sz=$(du -b "${img}" | awk '{ print $1 }')
    if [[ "${sz}" -lt "${FOUR_GB}" ]]; then
      newsz=4G
    else
      newsz=8G
    fi
    qemu-img resize -f raw "${img}" "${newsz}"
  fi

  sudo ./copy-kernel.sh "${img}"

  sudo ./burn.sh ./result/btrfspi.iso
  ./nixos.sh "${img}"
  noti -m "burn done"
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    sudo "$0" "$@"
    exit $?
  fi

  export -f user_main
  sudo -u "${SUDO_USER:-}" bash << EOF
  set -Eeuf -o pipefail
  set -x
  $(declare -f user_main)
  user_main
EOF

}

main "$@"
