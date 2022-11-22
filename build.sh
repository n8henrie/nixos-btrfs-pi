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

cli() {
  local arg
  for arg; do
    case "${arg}" in
      --)
        shift
        break
        ;;
      -h | --help)
        help
        exit 0
        ;;
      --no-burn)
        burn=""
        ;;
      --vm)
        run_vm=1
        ;;
      -?*)
        err "Unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
    shift
  done
}

log() {
  printf '%s :: %s\n' "$(date)" "$*" > /dev/stderr
}

err() {
  log "$*"
  exit 1
}

help() {
  cat << EOF
Usage:
  ./build.sh [--vm] [--no-burn]
EOF
}

user_main() {
  local run_vm="" burn=1
  cli "$@"

  [[ -r ./config.env ]] && source ./config.env
  time nix build \
    --option keep-outputs true \
    --print-build-logs \
    --show-trace |&
    tee build.log

  local result img
  result=./result/btrfspi.iso.zst
  img=btrfspi.iso

  rm -f "${img}"
  zstd --decompress "${result}" -o "${img}"
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

  if [[ -n "${CI:-}" ]]; then
    burn=""
    run_vm=""
  fi

  if [[ -n "${burn}" ]]; then
    # Don't fail if my SD card isn't present
    sudo ./burn.sh ./result/btrfspi.iso.zst || true

    # Dont' fail if user doesn't have noti set up
    noti -m "burn done" || true
  fi

  if [[ -n "${run_vm}" ]]; then
    ./nixos.sh "${img}"
  fi
}

main() {
  if [[ "${EUID}" -ne 0 ]]; then
    sudo "$0" "$@"
    exit $?
  fi

  export -f cli err help log user_main
  sudo -u "${SUDO_USER:-}" bash << EOF
  set -Eeuf -o pipefail
  set -x
  $(declare -f cli err help log user_main)
  user_main "$@"
EOF

}

main "$@"
