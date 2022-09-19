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
    kernelParams = [ "console=ttyAMA0" "root=UUID=44444444-4444-4444-8888-888888888889" "rootfstype=btrfs" "rootflags=subvol=@" "rootwait" ];
    initrd.kernelModules = [ "zstd" "btrfs" ];
    kernelPackages = pkgs.linuxPackages_5_18;
    loader = {
      grub.enable = false;
      generic-extlinux-compatible = {
        enable = true;
        configurationLimit = 20;
      };
      raspberryPi = {
        enable = false;
        version = 3;
        firmwareConfig = ''
          gpu_mem=16
        '';
      };
    };
  };

  # hardware = {
  #   enableRedistributableFirmware = false;
  #   firmware = [ pkgs.raspberrypiWirelessFirmware ];
  # };

  fileSystems =
    let
      opts = [
        "noatime"
        "ssd_spread"
        "autodefrag"
        "discard=async"
        "compress=zstd"
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

  swapDevices = [
    {
      device = "/dev/disk/by-label/SWAP";
    }
  ];

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault
    "ondemand";
}
