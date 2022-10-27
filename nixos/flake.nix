{
  description = "RPi3 on BTRFS root";
  inputs.nixpkgs.url = "nixpkgs/nixos-22.05-aarch64";
  outputs = { self, nixpkgs }@attrs:
    let
      system = "aarch64-linux";
    in
    {
      nixosConfigurations.machine = nixpkgs.lib.nixosSystem
        {
          inherit system;
          specialArgs = attrs;
          modules = [
            ./configuration.nix
          ];
        };
    };
}
