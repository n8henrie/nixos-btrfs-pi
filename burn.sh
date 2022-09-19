#!/usr/bin/env bash
# burn.sh: Wrapper around `dd` to write the image to my SD card after I somehow
# blew away a different drive (recovered thank goodness for ZFS) one time, then
# another time wrote everything out to a file named `/dev/sde` and couldn't
# figure out why the SD card wouldn't boot.

set -Eeuf -o pipefail
set -x

err() {
  log "$*"
  exit 1
}

log() {
  printf '%s\n' "$*" > /dev/stderr
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    sudo "$0" "$@"
    exit $?
  fi

  local img outdev
  img=${1:-./result/btrfspi.iso}
  outdev='/dev/disk/by-id/usb-TS-RDF5_SD_Transcend_000000000039-0:0'
  [[ -b "${outdev}" ]] || err "device not found: ${outdev}"

  dd \
    if="${img}" \
    of="${outdev}" \
    bs=4M \
    status=progress \
    conv=fsync
  noti -m "burn done"
}
main "$@"
