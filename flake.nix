{
  description = "sdimage for RPi3 on BTRFS root";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };
  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    armSystem = "aarch64-linux";
  in {
    packages.${system} = let
      pkgs = nixpkgs.legacyPackages.${system};
      pkgsArm = nixpkgs.legacyPackages.${armSystem};
      ubootPkgs =
        (import nixpkgs
          {
            localSystem.system = system;
            crossSystem.system = armSystem;
            inherit
              ((import ./nixos/hardware-configuration.nix
                {
                  inherit (pkgsArm) lib;
                  pkgs = pkgsArm;
                  modulesPath = pkgsArm.path + "/nixos/modules";
                })
              .nixpkgs)
              overlays
              ;
          })
        .pkgs;
      btrfsPi = {piVersion ? 3}:
        import ./btrfs-sd-image.nix {
          inherit inputs pkgs piVersion;
          bootFromBTRFS = true;
          BTRFSDupData = false;
          subvolumes = ["@" "@boot" "@gnu" "@home" "@nix" "@snapshots" "@var"];
        };
    in {
      default = self.outputs.packages.${system}.btrfsPi3;
      btrfsPi3 = btrfsPi {};
      btrfsPi4 = btrfsPi {piVersion = 4;};
      uboot3 = ubootPkgs.ubootRaspberryPi3_64bit;
      uboot4 = ubootPkgs.ubootRaspberryPi4_64bit;
      runVm = let
        uboot =
          (import nixpkgs
            {
              localSystem.system = system;
              crossSystem.system = armSystem;
              inherit
                ((import ./nixos/hardware-configuration.nix
                  {
                    inherit (pkgsArm) lib;
                    pkgs = pkgsArm;
                    modulesPath = pkgsArm.path + "/nixos/modules";
                  })
                .nixpkgs)
                overlays
                ;
            })
          .pkgs
          .ubootRaspberryPi3_64bit;
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
