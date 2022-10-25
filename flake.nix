{
  description = "sdimage for RPi3 on BTRFS root";
  inputs.nixpkgs.url = "nixpkgs/nixos-22.05-aarch64";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      armSystem = "aarch64-linux";
    in
    {
      packages.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsArm = nixpkgs.legacyPackages.${armSystem};
        in
        {
          default =
            (import ./btrfs-sd-image.nix {
              inherit pkgs;
              bootFromBTRFS = true;
              BTRFSDupData = false;
              subvolumes = [ "@" "@boot" "@gnu" "@home" "@nix" "@snapshots" "@var" ];
            });
          runVm =
            let
              uboot = (import nixpkgs
                {
                  localSystem.system = system;
                  crossSystem.system = armSystem;
                  overlays = (import ./nixos/hardware-configuration.nix
                    {
                      pkgs = pkgsArm;
                      lib = pkgsArm.lib;
                      modulesPath = pkgsArm.path + "/nixos/modules";
                    }).nixpkgs.overlays;
                }).pkgs.ubootRaspberryPi3_64bit;
            in
            pkgs.writeScript "run-nixos-vm" ''
              #!${pkgs.runtimeShell}

              img=aarch64-qemu.img
              zstd \
                --decompress \
                ${self.outputs.packages.${system}.default}/*.iso.zst \
                -o "$img"
              chmod 0640 "$img"
              qemu-img resize -f raw "$img" 4G

              qemu-system-aarch64 \
                -machine raspi3b \
                -kernel "${uboot}/u-boot.bin" \
                -cpu max \
                -m 1G \
                -smp 4 \
                -drive file="$img",format=raw \
                -device usb-net,netdev=net0 \
                -netdev user,id=net0,hostfwd=tcp::2222-:22 \
                -serial null \
                -serial mon:stdio
            '';
        };
    };
}
