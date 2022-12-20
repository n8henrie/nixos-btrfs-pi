{
  description = "RPi3 on BTRFS root";
  inputs.nixpkgs.url = "nixpkgs/nixos-22.11";
  outputs =
    { self
    , nixpkgs
    } @ attrs:
    let
      system = "aarch64-linux";
    in
    {
      nixosConfigurations.nixpi = nixpkgs.lib.nixosSystem
        {
          inherit system;
          specialArgs = attrs;
          modules = [
            ./configuration.nix
          ];
        };
    };
}
