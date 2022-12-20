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
      enable = false;
      interfaces = [ "wlan0" ];
      networks = { };
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
    nscd.enableNsncd = true;
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
      # (import ./vim.nix { inherit pkgs; })
      # (import ./nvim.nix { inherit pkgs; })
    ];
    variables = {
      EDITOR = "nvim";
    };
  };

  users = {
    mutableUsers = false;
    users = {
      root = {
        password = "nixos-btrfs";
        openssh.authorizedKeys.keyFiles = [
          (builtins.fetchurl {
            url = "https://github.com/n8henrie.keys";
            sha256 = "1zhq1r83v6sbrlv1zh44ja70kwqjifkqyj1c258lki2dixqfnjk7";
          })
        ];
      };
    };
  };

  i18n.supportedLocales = [ "en_US.UTF-8/UTF-8" ];

  nixpkgs.config.allowUnfree = true;
  nix = {
    # Disable nix channel lookups, use flakes instead
    nixPath = [ ];
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
      flake = "/etc/nixos";
      flags = [
        "--update-input"
        "nixpkgs"
        "--commit-lock-file"
      ];
      dates = "02:00";
      allowReboot = true;
      rebootWindow = {
        upper = "03:00";
        lower = "04:00";
      };
    };

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.11"; # Did you read the comment?
  };
}
