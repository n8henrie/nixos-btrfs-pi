{ lib, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  nixpkgs.overlays = [
    (self: super: {
      ubootRaspberryPi3_64bit = super.ubootRaspberryPi3_64bit.overrideAttrs
        (oldAttrs: {
          extraConfig = ''
            CONFIG_CMD_BTRFS=y
            CONFIG_ZSTD=y

            CONFIG_BOOTCOMMAND="setenv boot_prefixes / /boot/ /@/ /@boot/; run distro_bootcmd;"
          '';
        });
    })
  ];

  boot = {
    # console=ttyAMA0 seems necessary for kernel boot messages in qemu
    kernelParams = [
      "console=ttyS0,115200n8"
      "console=ttyAMA0,115200n8"
      "console=tty0"
      "root=/dev/mmcblk0p3"
      "rootfstype=btrfs"
      "rootflags=subvol=@"
      "rootwait"
    ];
    initrd.kernelModules = [ "zstd" "btrfs" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible = {
        enable = false;
        configurationLimit = 20;
      };
      raspberryPi = {
        enable = true;
        version = 3;
        uboot = {
          enable = true;
          configurationLimit = 20;
        };
        firmwareConfig = ''
          gpu_mem=16
        '';
      };
    };
  };

  fileSystems =
    let
      opts = [
        "noatime"
        "ssd_spread"
        "autodefrag"
        "discard=async"
        "compress-force=zstd"
      ];
      fsType = "btrfs";
      device = "/dev/disk/by-label/NIXOS_SD";
    in
    {
      "/" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@" ];
      };
      "/boot" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@boot" ];
      };
      "/nix" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@nix" ];
      };
      "/var" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@var" ];
      };
      "/home" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@home" ];
      };
      "/.snapshots" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@snapshots" ];
      };
      "/boot/firmware" = {
        device = "/dev/disk/by-label/FIRMWARE";
        fsType = "vfat";
        options = [ "nofail" "noauto" ];
      };
    };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault
    "ondemand";
}
