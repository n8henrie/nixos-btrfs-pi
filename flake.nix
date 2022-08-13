{
  description = "sdimage for RPi3 on BTRFS root";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default =
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.${system};
      in
      (import ./btrfs-sd-image.nix {
        inherit pkgs;
      });
  };
}
