# Building a BTRFS-root NixOS on a Raspberry Pi 3

https://github.com/lucernae/nixos-pi/blob/main/README.md

```console
$ echo 'extra-platforms = aarch64-linux' | sudo tee -a /etc/nix/nix.conf
$ yay -S qemu-user-static-bin
$ nix build \
    --include nixos-config=./sd-image.nix \
    --argstr system aarch64-linux \
    --file '<nixpkgs/nixos>' \
    --show-trace \
    config.system.build.sdImage
```

- set up /etc/nixos/configuration.nix

```console
# nix-channel --update
# nixos-install
# cp -r /mnt/boot/* /firmware
# cd /mnt/swap
# touch ./swapfile
# chattr +C ./swapfile
# btrfs property set ./swapfile compression none
# fallocate -l 1G ./swapfile
# chmod 0600 ./swapfile
# mkswap ./swapfile
# reboot
# nixos-rebuild switch
# nixos-rebuild switch --upgrade-all
# btrfs balance start -dconvert=dup /
```

```
setenv boot_syslinux_conf /@boot/extlinux/extlinux.conf
```
