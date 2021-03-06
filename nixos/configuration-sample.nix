{ config, pkgs, lib, ... }:
{
  imports = [
    ./inputrc.nix
    ./hardware-configuration.nix
  ];

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
      wget
      tmux
      neovim
      libraspberrypi
      # (import ./vim.nix)
      # (import ./nvim.nix)
    ];
    variables = {
      EDITOR = "nvim";
    };
  };

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

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
      max-jobs = auto
      auto-optimise-store = true
    '';
  };

  system = {
    # Uncomment this once things seem to be going well
    # autoUpgrade = {
    #   enable = true;
    #   allowReboot = true;
    # };
    #
    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It???s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.05"; # Did you read the comment?
  };
}
