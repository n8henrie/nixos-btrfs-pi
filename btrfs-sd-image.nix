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
      boot.postBootCommands = with pkgsCross; ''
        # On the first boot do some maintenance tasks
        if [ -f /nix-path-registration ]; then
          set -Eeuf -o pipefail
          set -x

          # Figure out device names for the boot device and root filesystem.
          rootPart=$(${pkgsArm.util-linux}/bin/findmnt -nvo SOURCE /)
          firmwareDevice=$(lsblk -npo PKNAME $rootPart)
          partNum=$(
            lsblk -npo MAJ:MIN "$rootPart" |
            ${gawk}/bin/awk -F: '{print $2}' |
            tr -d '[:space:]'
          )

          # Resize the root partition and the filesystem to fit the disk
          echo ',+,' | sfdisk -N"$partNum" --no-reread "$firmwareDevice"
          ${parted}/bin/partprobe
          ${btrfs-progs}/bin/btrfs filesystem resize max /

          # Register the contents of the initial Nix store
          ${btrfspi.config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

          # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
          touch /etc/NIXOS
          ${btrfspi.config.nix.package.out}/bin/nix-env \
            -p /nix/var/nix/profiles/system \
            --set /run/current-system

          # Prevents this from running on later boots.
          rm -f /nix-path-registration
        fi
      '';
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

  subvolumes = [ "@" "@boot" "@gnu" "@home" "@nix" "@snapshots" "@var" ];

  firmwarePartOpts =
    let
      opts = {
        inherit (btrfspi) pkgs config;
        inherit (btrfspi.pkgs) lib;
      };
      sdImage = (import (pkgsCross.path + "/nixos/modules/installer/sd-card/sd-image.nix") opts).options.sdImage;
      sdImageAarch64 = import (pkgsCross.path + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix");
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
          nix # mv, cp
          util-linux # sfdisk
          btrfspi.config.system.build.nixos-enter
          btrfspi.config.system.build.nixos-install
        ];

      preVM = ''
        ${pkgs.vmTools.qemu}/bin/qemu-img create -f raw ./btrfspi.iso 8G
      '';
      postVM = ''
        # Truncate the file at the end of the last partition
        PATH=${pkgs.util-linux}/bin:${pkgs.jq}/bin:$PATH
        img=./btrfspi.iso

        json=$(sfdisk --json --output end "$img")
        start=$(jq .partitiontable.partitions[-1].start <<< "$json")
        size=$(jq .partitiontable.partitions[-1].size <<< "$json")
        sectsize=$(jq .partitiontable.sectorsize <<< "$json")
        endbytes=$((("$start" + "$size" + 1) * "$sectsize"))

        truncate --size "$endbytes" "$img"

        mkdir -p $out
        mv "$img" $out/
      '';
      memSize = "16G";
      QEMU_OPTS = "-drive format=raw,file=./btrfspi.iso,if=virtio";
    } ''

  set -x

  shrinkBTRFSFs() {
    local mpoint shrinkBy
    mpoint=''${1:-/mnt}

    while :; do
      shrinkBy=$(
        btrfs filesystem usage -b "$mpoint" |
        awk \
          -v fudgeFactor=0.9 \
          -F'[^0-9]' \
          '
            /Free.*min:/ {
              sz = $(NF-1) * fudgeFactor
              print int(sz)
              exit
            }
          '
      )
      btrfs filesystem resize -"$shrinkBy" "$mpoint" || break
    done
    btrfs scrub start -B "$mpoint"
  }

  shrinkLastPartition() {
    local blockDev sizeInK partNum

    blockDev=''${1:-/dev/vda}
    sizeInK=$2
    partNum=$(ls "$blockDev"?* | wc -l)

    echo ",$sizeInK" | sfdisk -N"$partNum" "$blockDev"
  }

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

    start=''${gap}M,size=$firmwareSizeBlocks, type=b, bootable
    start=$(( $gap + $firmwareSize ))M, size=$swapSizeBlocks, type=82
    start=$(( $gap + $firmwareSize + $swapSize ))M, type=83
  EOF

  ${pkgs.udev}/bin/udevadm settle

  # partition 1: rpi firmware
  mkfs.vfat -n ${firmwarePartOpts.firmwarePartName} /dev/vda1

  # partition 2: swap (maybe don't need with zram enabled?)
  mkswap --label SWAP /dev/vda2

  # partition 3: btrfs root
  mkfs.btrfs \
    --label NIXOS_SD \
    --uuid "44444444-4444-4444-8888-888888888889" \
    /dev/vda3

  ${pkgs.udev}/bin/udevadm settle

  mkdir -p /mnt /btrfs /tmp/firmware

  btrfsopt=space_cache=v2,compress-force=zstd
  mount -t btrfs -o "$btrfsopts" /dev/disk/by-label/NIXOS_SD /btrfs
  btrfs filesystem resize max /btrfs

  for sv in ${toString subvolumes}; do
    btrfs subvolume create /btrfs/"$sv"

    dest="/mnt/''${sv#@}"
    if [[ "$sv" = "@snapshots" ]]; then
      dest=/mnt/.snapshots
    fi
    mkdir -p "$dest"
    mount -t btrfs -o "''${btrfsopts},subvol=$sv" /dev/disk/by-label/NIXOS_SD "$dest"
  done

  # All subvols should now be properly mounted at /mnt
  umount -R /btrfs

  # Enabling compression (or COW?) prevents uboot from booting directly from
  # BTRFS for some reason
  chattr +C /mnt/boot

  # Populate firmware files into FIRMWARE partition
  mount /dev/disk/by-label/${firmwarePartOpts.firmwarePartName} /tmp/firmware
  ${firmwarePartOpts.populateFirmwareCommands}

  # populate boot files into FIRMWARE partition
  ${firmwarePartOpts.populateCmd} -c ${toplevel} -d /tmp/firmware -g 0

  # populate boot files into NIXOS_SD partition
  ${firmwarePartOpts.populateCmd} -c ${toplevel} -d /mnt/boot -g 0

  mkdir -p /mnt/{etc/nixos,boot/firmware}
  for config in ${toString (configFiles ./nixos)}; do
    cp -a "$config"/share/. /mnt/etc/nixos
  done
  chmod +w /mnt/etc/nixos/*.nix

  export NIX_STATE_DIR=$TMPDIR/state
  nix-store --load-db \
    --option build-users-group "" \
    < ${closure}/registration

  cp ${closure}/registration /mnt/nix-path-registration

  echo "running nixos-install..."
  nixos-install \
    --max-jobs auto \
    --cores 0 \
    --root /mnt \
    --no-root-passwd \
    --no-bootloader \
    --substituters "" \
    --option build-users-group "" \
    --system ${toplevel} \
    --channel ${channelSources}

  shrinkBTRFSFs /mnt

  local size
  sizeInK=$(
    btrfs filesystem usage -b /mnt |
    awk '/Device size:/ { print ($NF / 1024) "KiB" }'
  )

  umount -R /mnt /tmp/firmware

  shrinkLastPartition /dev/vda "$sizeInK"
  btrfs check /dev/disk/by-label/NIXOS_SD
'')
