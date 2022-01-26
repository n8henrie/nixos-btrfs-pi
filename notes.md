# Building a BTRFS-root NixOS on a Raspberry Pi 3

https://github.com/lucernae/nixos-pi/blob/main/README.md



```
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

```
# nix-channel --update
# nixos-generate-config --dir .
# nixos-install --root /
# reboot
```
