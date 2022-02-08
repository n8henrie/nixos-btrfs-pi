{ config, pkgs, lib, ... }:
{
  imports = [
    ./inputrc.nix
  ];

  boot = {
    kernelParams = [ "console=tty0" "console=ttyS0" "root=LABEL=NIXOS_SD" "rootfstype=btrfs" "rootflags=subvol=@" ];
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

  # This probably doesn't need to be in here, but thought it might be handy if
  # I need to regenerate `u-boot.bin`
  nixpkgs.overlays = [
    (self: super: {
      ubootRaspberryPi3_64bit = super.ubootRaspberryPi3_64bit.overrideAttrs (oldAttrs: {
        extraConfig = ''
          CONFIG_CMD_BTRFS=y
        '';
      });
    })
  ];

  hardware.enableRedistributableFirmware = true;

  networking = {
    hostName = "nixpi";
    useDHCP = false;
    interfaces = {
      eth0.useDHCP = true;
    };
    firewall.enable = false;
    wireless = {
      enable = true;
      networks = {
        "MyNetwork" = {
          pskRaw = "put your psk here";
        };
      };
    };
  };

  time.timeZone = "America/Denver";

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

  systemd.services = {
    wpa_supplicant.wantedBy = lib.mkOverride 10 [ "default.target" ];
    sshd.wantedBy = lib.mkOverride 40 [ "multi-user.target" ];
  };

  environment = {
    systemPackages = with pkgs; [
      git
      wget
      tmux
      neovim
      # (import ./vim.nix)
      # (import ./nvim.nix)
    ];
    variables = {
      EDITOR = "nvim";
    };
  };
  # Uncomment this once things seem to be going well
  # system = {
  #   autoUpgrade = {
  #     enable = true;
  #     allowReboot = true;
  #   };
  # };

  users = {
    users.root.password = "nixos-btrfs"; # you should probably change this
    mutableUsers = false;
    users.yournamehere = {
      isNormalUser = true;
      home = "/home/yournamehere";
      description = "Your Name";
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ "your ssh pubkey here" ];
      hashedPassword = "your hashed password here";
    };
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "autodefrag" "subvol=@boot" ];
      neededForBoot = true;
    };
    "/var" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@var" ];
      # https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html
      neededForBoot = true;
    };
    "/home" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@home" ];
    };
    "/nix" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@nix" ];
    };
    "/swap" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "subvol=@swap" ];
    };
    "/.snapshots" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "noatime" "ssd_spread" "compress-force=zstd" "autodefrag" "subvol=@snapshots" ];
    };
  };

  swapDevices = [{ device = "/swap/swapfile"; size = 1024; }];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?
}
