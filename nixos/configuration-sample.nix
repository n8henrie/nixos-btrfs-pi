{ config, pkgs, lib, ... }:
{
  imports = [
    ./inputrc.nix
    ./hardware-configuration.nix
  ];

  networking = {
    hostName = "nixpi";
    domain = "home.arpa";
    useDHCP = false;
    interfaces = {
      eth0.useDHCP = true;
      wlan0.useDHCP = true;
    };
    firewall.enable = false;
    wireless = {
      enable = true;
      interfaces = [ "wlan0" ];
      networks = {
        "MyWifi" = {
          pskRaw = "totally Real";
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
    fstrim.enable = true;
  };

  systemd.services = {
    wpa_supplicant.wantedBy = lib.mkOverride 10 [ "default.target" ];
    sshd.wantedBy = lib.mkOverride 40 [ "multi-user.target" ];
  };

  environment = {
    systemPackages = with pkgs; [
      compsize
      git
      libraspberrypi
      neovim
      nixpkgs-fmt
      tmux
      wget
      # (import ./vim.nix)
      # (import ./nvim.nix)
    ];
    variables = {
      EDITOR = "nvim";
    };
  };

  users = {
    users.root = {
      password = "nixos-btrfs";
      openssh.authorizedKeys.keyFiles = [
        (builtins.fetchurl {
          url = "https://github.com/n8henrie.keys";
          sha256 = "0f5zh39s2xdr6hw3i8q2p3yr713wjj5h7sljgxfkysfsrmf99ypb";
        })
      ];
    };
    mutableUsers = false;
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

  nix = {
    settings = {
      max-jobs = "auto";
      auto-optimise-store = true;
      cores = 0;
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system = {
    autoUpgrade = {
      enable = true;
      allowReboot = true;
    };

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.05"; # Did you read the comment?
  };
}
