{ config, lib, pkgs, modulesPath, ... }:
{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot = {
    kernelParams = [ "console=tty1" "console=ttyAMA0" "console=ttyS0,1115200" "root=LABEL=NIXOS_SD" "rootfstype=btrfs" "rootflags=subvol=@" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible = {
        enable = true;
        configurationLimit = 20;
      };
      raspberryPi.firmwareConfig = ''
        gpu_mem=16
      '';
    };
  };

  nixpkgs.overlays = [
    (self: super: {
      ubootRaspberryPi3_64bit = super.ubootRaspberryPi3_64bit.overrideAttrs (oldAttrs: {
        # defconfig = "rpi_3_b_plus_defconfig";
        extraConfig = ''
          CONFIG_CMD_BTRFS=y
          CONFIG_ZSTD=y
          CONFIG_BOOTCOMMAND="setenv boot_prefixes / /boot/ /@/ /@boot/; run distro_bootcmd;"
        '';
      });
    })
  ];

  hardware = {
    enableRedistributableFirmware = false;
    firmware = [ pkgs.firmwareLinuxNonfree ];
  };


  fileSystems =
    let
      opts = [ "noatime" "ssd_spread" "autodefrag" "discard=async" "compress-force=zstd" ];
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
      "/swap" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@swap" ];
      };
      "/.snapshots" = {
        inherit fsType device;
        options = opts ++ [ "subvol=@snapshots" ];
      };
      "/firmware" = {
        device = "/dev/disk/by-label/FIRMWARE";
        fsType = "vfat";
      };
    };

  swapDevices = lib.mkIf (builtins.pathExists "/swap/swapfile") [
    {
      device = "/swap/swapfile";
    }
  ];

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
