{
  description = "sdimage for RPi3 on BTRFS root";
  inputs.nixpkgs.url = "nixpkgs/nixos-22.05";
  inputs.nixpkgsArm.url = "nixpkgs/nixos-22.05-aarch64";
  outputs = { self, nixpkgs, nixpkgsArm }:
    let
      system = "x86_64-linux";
      armSystem = "aarch64-linux";
    in
    {
      packages.${system} =
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsArm = nixpkgsArm.legacyPackages.${armSystem};
        in
        {
          default =
            (import ./btrfs-sd-image.nix {
              inherit pkgs;
            });
          runVm =
            let
              inherit pkgs;
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

              uboot =
                let
                  overlays = (import ./nixos/hardware-configuration.nix
                    {
                      pkgs = pkgsArm;
                      lib = pkgsArm.lib;
                      modulesPath = pkgsArm.path + "/nixos/modules";
                    }).nixpkgs.overlays;
                in
                (import nixpkgs
                  {
                    localSystem.system = system;
                    crossSystem.system = armSystem;
                    inherit overlays;
                  }).pkgs.ubootRaspberryPi3_64bit;

              vmScript = pkgs.writeScript "run-nixos-vm" ''
                #!${pkgs.runtimeShell}

                img=aarch64-qmu.img
                cp "${qemuImage}" "$img"
                chmod 0640 "$img"

                ${pkgs.qemu}/bin/qemu-system-aarch64 \
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
            in
            vmScript;
        };
    };
}
