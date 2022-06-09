{
  description = "Flake to build nixos-btrfs-pi.img";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05-aarch64";
  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-linux =
      let
        nixosConfiguration = nixpkgs.lib.nixosSystem
          {
            system = "aarch64-linux";
            modules = [ ./sd-image.nix ];
          };
      in
      nixosConfiguration.config.system.build.sdImage;
  };
}
