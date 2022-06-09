{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
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
