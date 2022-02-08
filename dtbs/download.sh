#!/usr/bin/env bash

set -Eeuf -o pipefail

readonly TAG=1.20210805

compile() {
  find . -maxdepth 1 -name '*.dts' | while read f; do
    dtc -O dtb -o "${f%.dtbs}.dtb" "${f}"
  done
}

main() {
  sha256sum -c checksums && {
    compile
    exit 0
  }

  local urls
  urls=(
    "https://raw.githubusercontent.com/raspberrypi/linux/${TAG}/arch/arm/boot/dts/bcm2710-rpi-3-b.dts"
    "https://raw.githubusercontent.com/raspberrypi/linux/${TAG}/arch/arm/boot/dts/bcm2710-rpi-3-b-plus.dts"
    "https://raw.githubusercontent.com/raspberrypi/linux/${TAG}/arch/arm/boot/dts/bcm2837-rpi-3-b.dts"
    "https://raw.githubusercontent.com/raspberrypi/linux/${TAG}/arch/arm/boot/dts/bcm2837-rpi-3-b-plus.dts"
  )

  local url
  for url in "${urls[@]}"; do
    wget "${url}"
  done
  sha256sum -c checksums
  compile
}
main "$@"
