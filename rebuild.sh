#!/usr/bin/env bash
# rebuild.sh: Deletes the images, tries to do some garbage collection and
# delete a few dependencies from the nix store, then runs `build.sh`. Useful
# when it seemed that my changes to `.nix` files weren't being picked up for
# whatever reason.

set -Eeuf -o pipefail
set -x

main() {
  rm -f ./btrfspi.iso ./result
  find /nix/store \
    \( -name '*nixos-btrfs*' -o -name '*btrfs-fs*' \) \
    -exec nix store delete --ignore-liveness -v {} +
  sudo -u "${SUDO_USER}" ./build.sh
}
main "$@"
