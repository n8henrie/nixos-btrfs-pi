#!/usr/bin/env bash
# inspect.sh: Convenience script to set up loop devices which are then mounted
# to some temporary directories. Don't forget to `umount` and `losetup -D`
# afterwards

set -Eeuf -o pipefail
set -x

loopdev=
readonly dest=/tmp/inspect

cleanup() {
  umount -R "${dest}1" || true
  umount -R "${dest}2" || true

  [[ -n "${loopdev}" ]] && losetup -d "${loopdev}"
}
trap cleanup INT TERM ERR

main() {
  local img
  img=${1:-nixos-btrfs.img}
  mkdir -p "${dest}"{1,2}
  for d in 1 2; do
    mountpoint "${dest}${d}" && {
      echo "already mounted!"
      exit 1
    }
  done

  loopdev=$(losetup --find --partscan --show "${img}")
  mount "${loopdev}p1" "${dest}1"
  mount "${loopdev}p2" "${dest}2"
}
main "$@"
