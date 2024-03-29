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

  local img=${1:-./btrfspi.iso}

  local loopnum loopdev
  loopdev=$(losetup --find --partscan --show "${img}")
  loopnum=${loopdev#/dev/loop}

  local parts
  mapfile -t parts < <(find /dev -name "${loopdev#/dev/}p*")

  for part in "${parts[@]}"; do
    partnum=${part#"${loopdev}p"}

    partdest="${dest}_${loopnum}_${partnum}"
    mkdir -p "${partdest}"
    mountpoint "${partdest}" && {
      echo "already mounted!"
      exit 1
    }
    mount "${part}" "${partdest}" || echo "Unable to mount ${part}"
  done
  echo "mounted at ${partdest}"
}
main "$@"
