{ config, lib, pkgs, ... }:
{
  imports = [
    ./sd-image-btrfs.nix
  ];

  boot = {
    kernelParams = [ "console=tty1" "console=ttyAMA0" "console=ttyS0,1115200" "root=LABEL=NIXOS_SD" "rootfstype=btrfs" ];
    initrd.availableKernelModules = [ "btrfs" "usbhid" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  nixpkgs.overlays = [
    (self: super: {
      ubootRaspberryPi3_64bit = super.ubootRaspberryPi3_64bit.overrideAttrs (oldAttrs: {
        extraConfig = ''
          CONFIG_CMD_BTRFS=y
        '';
      });
    })
  ];

  sdImage = {
    inherit ((import <nixpkgs/nixos/modules/installer/sd-card/sd-image-aarch64.nix> {
      inherit config lib pkgs;
    }).sdImage) populateRootCommands populateFirmwareCommands;
    compressImage = false;
    imageName = "nixos-btrfs.img";
  };
  hardware.enableRedistributableFirmware = true;

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" ];
    };
    "/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
    };
  };

  networking = {
    firewall.enable = false;
    hostName = "nixpi";
    wireless = {
      enable = true;
    };
  };

  services = {
    timesyncd.enable = true;
    avahi = {
      enable = true;
      publish = {
        enable = true;
        addresses = true;
      };
    };
    openssh = {
      enable = true;
      permitRootLogin = "yes";
    };
  };

  users.users.root.password = "nixos-btrfs";

  environment = {
    systemPackages = with pkgs; [
      git
      wget
      tmux
      neovim
    ];
    variables = {
      EDITOR = "nvim";
    };
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
