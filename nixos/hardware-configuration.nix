{ lib, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
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

  system.build.uboot = pkgs.ubootRaspberryPi3_64bit.overrideAttrs (oldAttrs: {
    defconfig = "rpi_3_defconfig";
    extraConfig = ''
      CONFIG_CMD_BTRFS=y
      CONFIG_ZSTD=y
      CONFIG_BOOTCOMMAND="setenv boot_prefixes / /boot/ /@/ /@boot/; run distro_bootcmd;"
    '';
  });

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

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking = {
    useDHCP = lib.mkDefault false;
    interfaces.eth0.useDHCP = lib.mkDefault true;
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault
    "ondemand";
}
