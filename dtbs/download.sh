#!/usr/bin/env bash

set -Eeu -o pipefail

main() {
  sha256sum -c checksums && exit 0

  local urls
  urls=(
    "https://github.com/raspberrypi/firmware/blob/master/boot/bcm2710-rpi-3-b.dtb?raw=true"
    "https://github.com/raspberrypi/firmware/blob/master/boot/bcm2710-rpi-3-b-plus.dtb?raw=true"
  )

  local url
  for url in "${urls[@]}"; do
    wget --content-disposition "${url}"
  done

  sha256sum -- *.dtb > checksums
  sha256sum -c checksums
}
main "$@"
