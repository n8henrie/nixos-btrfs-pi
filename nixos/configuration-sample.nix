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
    extraOptions = ''
      experimental-features = nix-command flakes
      max-jobs = auto
      auto-optimise-store = true
    '';
  };

  boot.postBootCommands = with pkgs; ''
    # On the first boot do some maintenance tasks
    if [ -f /nix-path-registration ]; then
      set -euo pipefail
      set -x
      # Figure out device names for the boot device and root filesystem.
      rootPart=$(${util-linux}/bin/findmnt -nvo SOURCE /)
      firmwareDevice=$(lsblk -npo PKNAME $rootPart)
      partNum=$(
        lsblk -npo MAJ:MIN "$rootPart" |
        ${gawk}/bin/awk -F: '{print $2}' |
        tr -d '[:space:]'
      )

      # Resize the root partition and the filesystem to fit the disk
      echo ',+,' | sfdisk -N"$partNum" --no-reread "$firmwareDevice"
      ${parted}/bin/partprobe
      ${btrfs-progs}/bin/btrfs filesystem resize max /

      # Register the contents of the initial Nix store
      ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

      # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
      touch /etc/NIXOS
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
      # Prevents this from running on later boots.
      rm -f /nix-path-registration
    fi
  '';

  system = {
    # Uncomment this once things seem to be going well
    # autoUpgrade = {
    #   enable = true;
    #   allowReboot = true;
    # };
    #
    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.05"; # Did you read the comment?
  };
}
