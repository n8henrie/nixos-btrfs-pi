# Building a BTRFS-root NixOS on a Raspberry Pi 3

This repo contains tools to build an image for a Raspberry Pi 3 on a BTRFS
root. I have been using these scripts from my Arch-based x86_64 server and they
work pretty well. You can probably get a good idea of how to do the same on
e.g. Ubuntu, but you're on your own with regards to QEMU and nix installation.

## Quickstart

```console
$ sudo pacman -S nix
$ yay -S qemu-user-static-bin
$ echo 'extra-platforms = aarch64-linux' | sudo tee -a /etc/nix/nix.conf
$ nix build \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    --show-trace \
    config.system.build.sdImage
```

This should give you `./result/sd-image/nixos-btrfs.img`

- Test run in QEMU: `./nixos.sh`
    - You'll first need to `qemu-img resize`, which requires ownership
    - You'll also need a copy of the `dtb` file and kernel
    - I've scripted the above `nix build` step and starting QEMU in
      `./build.sh`
    - In QEMU, I can't get the keyboard to work consistently (once in a blue
      moon via `device_add usb-host,hostbus=001,hostaddr=002`) or SSH to work
      at all
- Burn to your sd card: `sudo ./burn.sh`
- Boot it up

## Configuration

If it boots, your next steps will be setting up your installation.

- I prefer to use a `@` root subvolume with several other subvolumes (which
  help avoid shenanigans with snapshots taking up all available space)
    - To customize your subvolume setup you'll likely need to make some changes
      in `nixos/hardware-configuration.nix`:
        - `filesystems`
        - `kernelParams` (specifically `rootflags=subvol=@`)
- To save me a lot of effort in setting up my subvolumes across the dozens of
  times I re-ran this script, I added `customize-image.sh`, which will run
  during `build.sh` if you `export CUSTOMIZE_NIX_IMAGE=1`; you'll have to look
  through to see what it does exactly, to hopefully give you some ideas
- A lot of this can be set up in nix (e.g. in `boot.postBootCommands` in
  `sd-image-btrfs.nix`), but I didn't want to make my preferences default for
  others that might find this useful
- `customize_image.sh` also:
    - copies over some utility scripts for post-boot, more info on them below:
        - `mountsubvols.sh`
        - `setup.sh`
    - copies over my config from `./nixos` to the SD card's `/mnt/etc/nixos`
    - copies over my SSH public key
- This makes it fairly simple for me to burn the image, boot, ssh in, and then:

```console
# ./setup.sh
```

Without using my setup script, it would look something like this:

```console
# echo "Make swapfile -- see setup.sh, you're on your own here"
# nix-channel --update
# nixos-install --root /
# reboot
```

Obviously on the next boot one would want to:

```console
# nixos-rebuild switch
# nixos-rebuild switch --upgrade
```

## WIP / Known issues / Notes

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

#### BTRFS dup

One of the reasons I like BTRFS on an RPi is the ability to set dup data on an
SD card, which *might* be helpful for recovery in case of corruption (although
it will also be causing twice as many writes, so maybe it's worse? Who knows --
let me know if you do).

`sudo btrfs balance start -dconvert=dup /`

### u-boot with BTRFS root

The *easy* way is to copy `/boot/nixos` and `/boot/extlinux` onto your
FAT-based `/dev/disk/by-label/FIRMWARE` partition. This seems to work fine.

However, it won't support all the fancy BTRFS features, and won't necessarily
get updated (unless you update it manually).

*AND*, it ends up that `u-boot` supports booting from BTRFS just fine! The
`ubootRaspberryPi3_64bit` overlay in `sd-image.nix` seems to take care of that.
It didn't seem to work at first, until I discovered that u-boot wanted the
bootable flag to be set on the btrfs partition as well.

*HOWEVER*, it seems that `u-boot` has trouble booting from a *subvolume*, and
as I noted, I like subvolumes; in this case `@boot`. It looks for boot files in
`/` and `/boot/`, configurable by `boot_prefixes`, and normally finds
`/boot/extlinux/extlinux.conf` and goes from there.

I can help `u-boot` find the necessary files if I run from the u-boot prompt:

```
setenv boot_prefixes / /boot/ /@/ /@boot/
saveenv
boot
```

(I only add `/@/` in case others want to keep `/boot` on their `@` subvolume.)

At this point it goes into a boot loop where it *looks* like it's going to
work, but not quite.

**UPDATE 20220217**: I have subvolumes and booting from root subvolume working,
had to modify uboot's `boot_prefixes`

Currently it is *not* working if:
- `/boot` is compressed (see `customize-image.sh` and
  `hardware-configuration.nix`)

### With compression *disabled* on these 3 subvols, all is well:

- `@` (root)
- `@boot`
- `@nix`

Doesn't seem to work with any of those compressed, even using u-boot's
`CONFIG_ZSTD=y`.

### [BTRFS related](BTRFS-related) errors

Including but not limited to:

-     Error mounting ... mount(2)
      system call failed: File exists
- `ERROR: non-unique UUID`
- `BTRFS error (device ...): open_ctree failed`

I don't know. BTRFS is weird. There are some good SO threads, but a few
recurring issues I noted:

- The BTRFS part of the image is created from a directory using the `--shrink`
  flag, which means there's not much room left for additions
  - This is why I call `customize-image.sh` *after* `qemu-img resize` in
    `build.sh`, since that likely gives it a little extra space
- I guess in order to be more deterministic / reproducible, the UUID is
  pre-specified. This confuses and upsets BTRFS sometimes. I was able to fix it
  a few times by:
  - Make sure no images are still mounted or dangling:
    - `mount | grep loop`
    - `losetup`
  - `sudo btrfs device scan --forget` helps fix things, not sure if this is
    dangerous (my Arch box is also BTRFS root and nothing seemed to break)
  - When all else fails, reboot

This was also helpful at some point:

```
setenv boot_syslinux_conf /@boot/extlinux/extlinux.conf
```

Prior to figuring out the `bootable` flag issue, this got things going:

```
setenv distro_bootpart 2
boot
```

## Overview of shell scripts in this repo

- `inspect.sh`: Convenience script to set up loop devices which are then
  mounted to some temporary directories. Don't forget to `umount` and `losetup
  -D` afterwards
- `nixos.sh`: Run qemu to see if the image boots
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
- `customize-image.sh`: Self explanatory, creates subvolumes and copies other
  scripts to the image
- `setup.sh`: a convenience script to make swapfile (since certain builds die
  OOM without swap, and swap on BTRFS requires some special configuration),
  update nix-channel, nixos-install, and reboot all in one go

NB: I've given myself `NOPASSWD` permissions to run the following so that I can
fire and forget `./build.sh`:

- `customize-image.sh`
- `copy-kernel.sh`
- `rebuild.sh`
- `inspect.sh`

## License

My changes and modifications are MIT as per `/LICENSE`, to the extent
permitted.

Substantial portions of this project were copied from work by `c00w` on the
NixOS forums:
<https://discourse.nixos.org/t/raspberry-pi-nixos-on-btrfs-root/14081/11>; he
included a similarly permissive license
[here](https://git.sr.ht/~c00w/useful-nixos-aarch64/tree/pi4bbtrfs/item/pi4bbtrfs/LICENSE).

## Learning Resources

- https://github.com/lucernae/nixos-pi/blob/main/README.md
