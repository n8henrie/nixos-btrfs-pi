#!/usr/bin/env bash
# burn.sh: Wrapper around `dd` to write the image to my SD card after I somehow
# blew away a different drive (recovered thank goodness for ZFS) one time, then
# another time wrote everything out to a file named `/dev/sde` and couldn't
# figure out why the SD card wouldn't boot.

set -Eeuf -o pipefail
set -x

main() {
  local img outdev
  img=./nixos-btrfs.img
  outdev='/dev/disk/by-id/usb-TS-RDF5_SD_Transcend_000000000039-0:0'
  [[ -b "${outdev}" ]] || exit 1

  dd \
    if="${img}" \
    of="${outdev}" \
    bs=4M \
    status=progress \
    conv=fsync
  noti -m "burn done"
}
main "$@"
