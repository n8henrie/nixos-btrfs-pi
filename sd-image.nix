{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    # <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
    ./sd-image-btrfs.nix
    ./nixos/hardware-configuration.nix
  ];

  sdImage = {
    inherit ((import (modulesPath + "/installer/sd-card/sd-image-aarch64.nix") {
      inherit config lib pkgs;
    }).sdImage) populateRootCommands populateFirmwareCommands;
    compressImage = false;
    imageName = "nixos-btrfs.img";
  };

  networking = {
    firewall.enable = false;
    hostName = "nixpi";
    wireless = {
      enable = true;
    };
  };

  services = {
    # qemuGuest.enable = true;
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

  systemd.services.autoinstall = {
    path = [ pkgs.bash pkgs.nix pkgs.nixos-rebuild pkgs.nixos-install-tools ];
    script = ''
      [[ -f /root/setup.sh ]] && /root/setup.sh || nixos-rebuild --upgrade --install-bootloader switch
    '';
    wantedBy = [ "network-online.target" ];
    serviceConfig = {
      Restart = "on-failure";
    };
  };

  users.users.root.password = "nixos-btrfs";

  environment = {
    systemPackages = with pkgs; [
      git
      libraspberrypi
      neovim
      tmux
      wget
      compsize
    ];
    variables = {
      EDITOR = "nvim";
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

  system.stateVersion = "22.05";
}
