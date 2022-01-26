{ config, lib, pkgs, ... }:
{
  imports = [
    ./sd-image-btrfs.nix
  ];

  boot = {
    kernelParams = [ "console=tty0" "console=ttyS0" "root=LABEL=NIXOS_SD" "rootfstype=btrfs" ];
    initrd.availableKernelModules = [ "usbhid" ];
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

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" ];
    };
  };
  # fileSystems = {
  #   "/boot" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "autodefrag" "subvol=@boot" ];
  #   };
  #   "/" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@" ];
  #   };
  #   "/var" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@var" ];
  #     # https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html
  #     neededForBoot = true;
  #   };
  #   "/home" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@home" ];
  #   };
  #   "/nix" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@nix" ];
  #   };
  #   "/swap" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@swap" ];
  #   };
  #   "/.snapshots" = {
  #     device = "/dev/disk/by-label/NIXOS_SD";
  #     fsType = "btrfs";
  #     options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@snapshots" ];
  #   };
  # };

  networking = {
    hostName = "nixpi";
    wireless = {
      enable = true;
      interfaces = [ "wlan0" ];
    };
    interfaces = {
      wlan0.useDHCP = true;
      eth0.useDHCP = true;
    };
  };

  services = {
    avahi = {
      enable = true;
      nssmdns = true;
      publish.enable = true;
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
      EDITOR = "vim";
    };
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];
}
