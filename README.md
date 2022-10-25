# Building a BTRFS-root NixOS on a Raspberry Pi 3

This repo contains tools to build an image for a Raspberry Pi 3 on a BTRFS
root. I have been using these scripts from my Arch-based x86_64 server and they
work pretty well. You can probably get a good idea of how to do the same on
e.g. Ubuntu, but you're on your own with regards to QEMU and nix installation.

I have a decent threadripper with plenty of ram and fairly slow internet; it
takes my machine a little over an hour to build the image.

## Quickstart

```console
$ sudo pacman -S nix
$ yay -S qemu-user-static-bin
$ cat <<'EOF' | sudo tee -a /etc/nix/nix.conf
extra-platforms = aarch64-linux
experimental-features = nix-command flakes repl-flake
max-jobs = auto
cores = 0
EOF
$ sudo systemctl restart nix-daemon.service
$ git clone https://github.com/n8henrie/nixos-btrfs-pi && cd nixos-btrfs-pi
$ nix build
```

This should give you `./result/btrfspi.img.zst`

- Test run in QEMU:
    - `nix build .#runVm && ./result`
    - You can also look at `nixos.sh`, which works similarly, but requires:
        - You'll first need to `qemu-img resize`, which requires ownership
        - You'll also need a copy of the `dtb` file and kernel
        - I've scripted builting + these steps into `build.sh`
    - In QEMU, I can't get the keyboard to work consistently (once in a blue
      moon via `device_add usb-host,hostbus=001,hostaddr=002`) or SSH to work
      at all
- Burn to your sd card: `sudo ./burn.sh`
    - To be save you might want to set your `OUTDEV` in `config.env` and source
      this first
- Boot it up

## Configuration

This image is on BTRFS, using the subvolumes as specified in
`btrfs-sd-image.nix`. The root subvolume is `@`, home is `@home`, etc.

The `FAT`-based `FIRMWARE` partition has important Raspberry Pi config files
such as `config.txt` and can be mounted to its default location with `mount
/boot/firmware`. To help protect these critical files it is not mounted by
default.

### `bootFromBTRFS`

When `true`, this option puts the boot files into the `@boot` subvolume, which
gets mounted at `/boot`. When `false`, the boot files go onto the `FAT`-based
`FIRMWARE` partition. See the **Booting** section below for additional details.

### `BTRFSDupData`

This option runs `btrfs balance start -dconvert=DUP /` on the system's first
boot, duplicating all data on the SD card. Please see the `DUP PROFILES ON A
SINGLE DEVICE` section of `man mkfs.btrfs` for additional details; I'm not sure
whether this would increase or harm the robustness of a NixOS system on an SD
card.

Please note that setting data to `DUP` seems to be incompatible with booting
directly from BTRFS, so one must set `bootFromBTRFS` to `false`. (If you are
booting from the `FAT` partition but did not set `BTRFSDupData` to true, you
can choose to convert your data to `DUP` at any time.)

## Booting

By default this image has `@boot` mounted to `/boot` and the initrd and
required boot files are installed there. It uses a patched u-boot that has
support for BTRFS and zstd compression.

Unfortunately, u-boot doesn't seem to work from a compressed subvolume for
whatever reason; after over a year or work I've basically given up:

- <https://lists.denx.de/pipermail/u-boot/2022-May/484855.html>
- <https://discourse.nixos.org/t/btrfs-pi-wont-boot-from-compressed-subvolume/18462>

For now, the workaround is to disable compression (and COW) via `chattr +C` on
this subvolume. (You can also `btrfs property set /boot compression none`, but
this gets overridden and breaks if one uses the `compress-force` mount option,
where as `chattr +C` works even then).

If anyone has other ideas on how I can get u-boot to boot from `@boot` without
disabling compression, I'd be interested to hear about it.

## WIP / Known issues / Notes

- I'd still love to figure out why I can't boot from my zstd-compressed `@boot`
  BTRFS subvolume; seems like u-boot supports the right stuff
- I'd like my channel to default to `nixos-22.05-aarch64`, but it *looks* like
  it's just defaulting to `nixos-22.05`. [See
  also](https://discourse.nixos.org/t/can-i-create-an-sdimage-with-a-preconfigured-default-channel/19593)
- I spent a good while putting together a flake that would use
  `nixos-generators` to create a standard sdImage based on
  `nixos/configuration-sample.nix` (which includes BTRFS kernel modules), use
  the u-boot strategy from this repo, then copy the contents and updated u-boot
  over to a blank BTRFS-based partition. It ran *much* faster than this
  approach, but wouldn't boot. Why doesn't this work?

### Debugging

This seems handy. Still trying to figure out how to inspect the value of
`fileSystems` and whether I'm setting it correctly.

```console
$ nix show-derivation \
    --include nixos-config=sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    config.system.build.sdImage
```

**UPDATE 20220301:** Finally figured out how to debug a value:


```console
$ nix repl \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux
    '<nixpkgs/nixos>'
nix-repl> :p config.fileSystems
```

Or even better:

```console
$ nix eval \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    config.fileSystems
```

With color and formatting in a pager:

```console
$ nix eval \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    config.fileSystems \
    --json |
    jq --color-output |
    bat
```

## Overview of shell scripts in this repo

- `inspect.sh`: Convenience script to set up loop devices which are then
  mounted to some temporary directories. Don't forget to `umount` and `losetup
  -D` afterwards
- `nixos.sh`: Run qemu to see if the image boots (see also the `.#runVm` flake
  output)
- `copy-kernel.sh`: Convenience script to mount the image and copy the kernel
  locally for use with `nixos.sh`. Delete `./u-boot-rpi3.bin` to copy a fresh
  version next run.
- `build.sh`: Runs `nix build`, makes a user-owned copy of the image, resizes
  image, runs `nixos.sh`
- `rebuild.sh`: Deletes the images, tries to do some garbage collection and
  delete a few dependencies from the nix store, then runs `build.sh`. Useful
  when it seemed that my changes to `.nix` files weren't being picked up for
  whatever reason.
- `burn.sh`: Wrapper around `dd` to write the image to my SD card after I
  somehow blew away a different drive (recovered thank goodness for ZFS) one
  time, then another time wrote everything out to a file named `/dev/sde` and
  couldn't figure out why the SD card wouldn't boot.
- `dtbs/download.sh`: Not currently functional

NB: I've given myself `NOPASSWD` permissions to run the following so that I can
fire and forget `./build.sh`:

- `burn.sh`
- `copy-kernel.sh`
- `inspect.sh`
- `rebuild.sh`

## License

My changes and modifications are MIT as per `/LICENSE`, to the extent
permitted.

Substantial portions of this project were copied from:

- <https://gist.github.com/lheckemann/f265f155e9e7a7d05028eacfa6e96114>
- <https://discourse.nixos.org/t/raspberry-pi-nixos-on-btrfs-root/14081/11>

## Learning Resources

- https://github.com/lucernae/nixos-pi/blob/main/README.md
