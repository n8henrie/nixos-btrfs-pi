{
  description = "sdimage for RPi3 on BTRFS root";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
  inputs.nixpkgsArm.url = "github:nixos/nixpkgs/nixos-22.05-aarch64";
  outputs = { self, nixpkgs, nixpkgsArm }: {
    packages.x86_64-linux =
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.${system};
        pkgsArm = nixpkgsArm.legacyPackages.${system};
      in
      {
        default =
          (import ./btrfs-sd-image.nix {
            inherit pkgs;
          });
        runVm =
          let
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            qemuImage = pkgs.stdenv.mkDerivation
              {
                name = "aarch64-qemu.img";
                dontUnpack = true;
                installPhase = ''
                  img=./nixos-aarch64.img
                  cp ${self.outputs.packages.${system}.default}/*.iso "$img"
                  chmod 0640 "$img"
                  ${pkgs.qemu}/bin/qemu-img resize -f raw "$img" 4G
                  cp "$img" $out
                '';
              };

            vmScript = pkgs.writeScript "run-nixos-vm" ''
              #!${pkgs.runtimeShell}

              img=aarch64-qmu.img
              cp "${qemuImage}" "$img"
              chmod 0640 "$img"

              ${pkgs.qemu}/bin/qemu-system-aarch64 \
                -machine raspi3b \
                -cpu max \
                -m 1G \
                -smp 4 \
                -drive file="$img",format=raw \
                -device usb-net,netdev=net0 \
                -netdev user,id=net0,hostfwd=tcp::2222-:22 \
                -serial null \
                -serial mon:stdio
            '';
          in
          vmScript;
      };
  };
}
