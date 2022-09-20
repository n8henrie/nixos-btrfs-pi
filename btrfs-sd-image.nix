{ pkgs }:
let
  pkgsArm = import pkgs.path {
    system = "aarch64-linux";
  };
  pkgsCross = import pkgs.path {
    system = "x86_64-linux";
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
  };

  btrfspi = import (pkgs.path + "/nixos") {
    configuration = {
      nixpkgs = {
        system = "aarch64-linux";
      };
      imports = [
        ./nixos/configuration-sample.nix
      ];
    };
  };

  toplevel = btrfspi.config.system.build.toplevel;
  channelSources =
    let
      nixpkgs = pkgs.lib.cleanSource pkgs.path;
    in
    pkgs.runCommand "nixos-${btrfspi.config.system.nixos.version}" { } ''
      mkdir -p $out
      cp -prd ${nixpkgs.outPath} $out/nixos
      chmod -R u+w $out/nixos
      if [ ! -e $out/nixos/nixpkgs ]; then
        ln -s . $out/nixos/nixpkgs
      fi
      rm -rf $out/nixos/.git
      echo -n ${btrfspi.config.system.nixos.versionSuffix} > $out/nixos/.version-suffix
    '';

  closure = pkgs.closureInfo {
    rootPaths = [ toplevel channelSources ];
  };

  subvolumes = [ "@" "@boot" "@home" "@nix" "@snapshots" "@var" ];

  firmwarePartOpts =
    let
      opts = {
        inherit (btrfspi) pkgs config;
        inherit (btrfspi.pkgs) lib;
      };
      sdImage = (import (pkgsArm.path + "/nixos/modules/installer/sd-card/sd-image.nix") opts).options.sdImage;
      sdImageAarch64 = import (pkgsArm.path + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix");
    in
    {
      firmwarePartID = sdImage.firmwarePartitionID.default;
      firmwarePartName = sdImage.firmwarePartitionName.default;
      populateFirmwareCommands = (sdImageAarch64 opts).sdImage.populateFirmwareCommands;

      populateCmd = (import (pkgs.path + "/nixos/modules/system/boot/loader/generic-extlinux-compatible") {
        inherit pkgs;
        config = btrfspi.config;
        lib = pkgs.lib;
      }).config.content.boot.loader.generic-extlinux-compatible.populateCmd;
    };


  # Take contents of ./nixos/*.nix and make list of derivations
  configFiles = with builtins; dir:
    attrValues (mapAttrs
      (name: value:
        let
          filename = if name == "configuration-sample.nix" then "configuration.nix" else name;
        in
        pkgs.writeTextDir "share/${filename}" (readFile "${dir}/${name}")
      )
      (pkgs.lib.filterAttrs (n: _: pkgs.lib.strings.hasSuffix ".nix" n) (readDir dir)));
in

pkgs.vmTools.runInLinuxVM
  (pkgs.runCommand "btrfspi-sd"
    {
      enableParallelBuilding = true;
      nativeBuildInputs =
        with pkgs;
        [
          btrfs-progs
          dosfstools
          e2fsprogs
          jq
          nix # mv, cp
          python3
          util-linux # sfdisk
          btrfspi.config.system.build.nixos-enter
          btrfspi.config.system.build.nixos-install
        ];

      preVM = ''
        ${pkgs.vmTools.qemu}/bin/qemu-img create -f raw ./btrfspi.iso 8G
      '';
      postVM = ''
        img=./btrfspi.iso

        json=$(${pkgsArm.util-linux}/bin/sfdisk --json --output end "$img")
        start=$(${pkgsArm.jq}/bin/jq .partitiontable.partitions[-1].start <<< "$json")
        size=$(${pkgsArm.jq}/bin/jq .partitiontable.partitions[-1].size <<< "$json")
        sectsize=$(${pkgsArm.jq}/bin/jq .partitiontable.sectorsize <<< "$json")
        endbytes=$((("$start" + "$size" + 1) * "$sectsize"))

        truncate --size "$endbytes" "$img"

        mkdir -p $out
        mv "$img" $out/
      '';
      memSize = "4G";
      QEMU_OPTS = "-drive format=raw,file=./btrfspi.iso,if=virtio -smp 16";
    } ''

  set -x
  ${pkgs.kmod}/bin/modprobe btrfs
  ${pkgs.udev}/lib/systemd/systemd-udevd &

  # Gap before first partition
  gap=1

  swapSize=1024
  swapSizeBlocks=$(( $swapSize * 1024 * 1024 / 512 ))

  firmwareSize=512
  firmwareSizeBlocks=$(( $firmwareSize * 1024 * 1024 / 512 ))

  # type=b is 'W95 FAT32', 82 is swap, 83 is 'Linux'.
  # The "bootable" partition is where u-boot will look file for the bootloader
  # information (dtbs, extlinux.conf file).
  # Setting the bootable flag on the btrfs partition allows booting directly

  sfdisk /dev/vda <<EOF
    label: dos
    label-id: ${firmwarePartOpts.firmwarePartID}

    start=''${gap}M,size=$firmwareSizeBlocks, type=b
    start=$(( $gap + $firmwareSize ))M, size=$swapSizeBlocks, type=82
    start=$(( $gap + $firmwareSize + $swapSize ))M, type=83, bootable
  EOF

  ${pkgs.udev}/bin/udevadm settle

  ## partition 1: rpi firmware
  mkfs.vfat -n ${firmwarePartOpts.firmwarePartName} /dev/vda1
  ## partition 2: swap (maybe don't need with zram enabled?)
  mkswap --label SWAP /dev/vda2
  ## partition 3: btrfs root
  mkfs.btrfs -L NIXOS_SD -U "44444444-4444-4444-8888-888888888889" /dev/vda3

  ${pkgs.udev}/bin/udevadm settle

  mkdir -p /mnt /btrfs /tmp/firmware

  ## populate partition 1
  mount /dev/vda1 /tmp/firmware
  ${firmwarePartOpts.populateFirmwareCommands}

  umount -R /tmp/firmware

  btrfsopt=space_cache=v2,compress-force=zstd
  ## populate partition 3
  mount -t btrfs -o "$btrfsopts" /dev/vda3 /btrfs
  btrfs filesystem resize max /btrfs

  for sv in ${toString subvolumes}; do
    btrfs subvolume create /btrfs/"$sv"

    dest="/mnt/''${sv#@}"
    if [[ "$sv" = "@snapshots" ]]; then
      dest=/mnt/.snapshots
    fi
    mkdir -p "$dest"
    mount -t btrfs -o "''${btrfsopts},subvol=$sv" /dev/vda3 "$dest"
  done

  # All subvols should now be properly mounted at /mnt
  umount -R /btrfs

  # Enabling compression prevents uboot from booting for some reason
  chattr +C /mnt/boot

  ${firmwarePartOpts.populateCmd} -c ${toplevel} -d /mnt/boot -g 0

  mkdir -p /mnt/etc/nixos
  for config in ${toString (configFiles ./nixos)}; do
    cp -a "$config"/share/. /mnt/etc/nixos
  done
  chmod +w /mnt/etc/nixos/*.nix

  export NIX_STATE_DIR=$TMPDIR/state
  nix-store --load-db < ${closure}/registration

  cp ${closure}/registration /mnt/nix-path-registration

  echo "running nixos-install..."
  nixos-install \
    --max-jobs 16 \
    --cores 0 \
    --root /mnt \
    --no-root-passwd \
    --system ${toplevel} \
    --no-bootloader \
    --substituters "" \
    --channel ${channelSources}

  # Shrink BTRFS filesystem
  while :; do
    local free_min
    free_min=$(
      btrfs filesystem usage -b /mnt |
        awk '
        /Free.*min:/ {
          gsub(/[^0-9]/, "", $NF)
          print $NF
        }
      '
    )

    local shrink_by
    shrink_by=$(python3 -c "print(int($free_min * 0.9))")
    btrfs filesystem resize -"$shrink_by" /mnt || break
  done

  local size
  size=$(btrfs filesystem usage -b /mnt | awk '/Device size:/ { print $NF }')

  btrfs scrub start -B /mnt
  umount -R /mnt

  btrfs check /dev/vda3

  # Shrink partition
  local json sectsize
  json=$(sfdisk --json --output end /dev/vda)
  sectsize=$(jq .partitiontable.sectorsize <<< "$json")

  local num_sects
  num_sects=$(("$size" / "$sectsize" + 1))
  echo ",$num_sects" | sfdisk -N 3 /dev/vda

  btrfs check /dev/vda3
'')
