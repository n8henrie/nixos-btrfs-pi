{
  description = "RPi3 (or 4) on BTRFS root";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };
  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "aarch64-linux";
  in {
    nixosConfigurations = {
      nixpi =
        nixpkgs.lib.nixosSystem
        {
          inherit system;
          modules = [
            ./configuration.nix
          ];
        };
      nixpi4 =
        nixpkgs.lib.nixosSystem
        {
          inherit system;
          modules = [
            ./configuration.nix
            inputs.nixos-hardware.nixosModules.raspberry-pi-4
          ];
        };
    };
  };
}
