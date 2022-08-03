#!/usr/bin/env bash
# inspect.sh: Convenience script to set up loop devices which are then mounted
# to some temporary directories. Don't forget to `umount` and `losetup -D`
# afterwards

set -Eeuf -o pipefail
set -x

loopdev=
readonly dest=/tmp/inspect

cleanup() {
  umount -R "${dest}?" || true
  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}"
}
trap cleanup INT TERM ERR

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    sudo bash "$0" "$@"
    exit $?
  fi

  local img
  img=${1:-nixos-btrfs.img}

  loopdev=$(losetup --find --partscan --show "${img}")

  mkdir -p "${dest}"{1,3}
  for d in 1 3; do
    mountpoint "${dest}${d}" && {
      echo "already mounted!"
      exit 1
    }
  done

  mount "${loopdev}p1" "${dest}1"
  mount "${loopdev}p3" "${dest}3"
}
main "$@"
