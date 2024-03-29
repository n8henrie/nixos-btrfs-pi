{
  pkgs,
  inputs,
  bootFromBTRFS ? true,
  BTRFSDupData ? false,
  subvolumes ? ["@" "@boot" "@gnu" "@home" "@nix" "@snapshots" "@var"],
  piVersion ? 3,
}: let
  pkgsArm = import pkgs.path {
    localSystem.system = "aarch64-linux";
  };
  pkgsCross = import pkgs.path {
    localSystem.system = "x86_64-linux";
    crossSystem.system = "aarch64-linux";
  };

  extraConfigTxt = [
    "gpu_mem=16"
    "program_usb_boot_mode=1"
    "program_usb_boot_timeout=1"
  ];

  btrfspi = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "aarch64-linux";
    specialArgs = {inherit inputs;};
    modules = [
      {
        imports =
          [
            ./nixos/configuration-sample.nix
          ]
          ++ pkgs.lib.optional (piVersion == 4) inputs.nixos-hardware.nixosModules.raspberry-pi-4;

        boot.postBootCommands = with pkgsCross; ''
          # On the first boot do some maintenance tasks
          set -Eeuf -o pipefail

          if [ -f /nix-path-registration ]; then
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

            if [ ${toString BTRFSDupData} ]; then
              ${btrfs-progs}/bin/btrfs balance start -dconvert=DUP /
            fi

            # Register the contents of the initial Nix store
            ${btrfspi.config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

            # Prevents this from running on later boots.
            rm -f /nix-path-registration
          fi
        '';
      }
    ];
  };

  inherit (btrfspi.config.system.build) toplevel;
  channelSources = let
    nixpkgs = pkgs.lib.cleanSource pkgs.path;
  in
    pkgs.runCommand "nixos-${btrfspi.config.system.nixos.version}" {} ''
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
    rootPaths = [toplevel channelSources];
  };

  firmwarePartOpts = let
    opts = {
      inherit (btrfspi) pkgs config;
      inherit (btrfspi.pkgs) lib;
    };
    inherit ((import (pkgsCross.path + "/nixos/modules/installer/sd-card/sd-image.nix") opts).options) sdImage;
    sdImageAarch64 = import (pkgsCross.path + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix");
  in {
    firmwarePartID = sdImage.firmwarePartitionID.default;
    firmwarePartName = sdImage.firmwarePartitionName.default;
    inherit ((sdImageAarch64 opts).sdImage) populateFirmwareCommands;

    inherit
      (
        (import (pkgs.path + "/nixos/modules/system/boot/loader/generic-extlinux-compatible") {
          inherit pkgs;
          inherit (pkgs) lib;
          inherit (btrfspi) config;
        })
        .config
        .content
        .boot
        .loader
        .generic-extlinux-compatible
      )
      populateCmd
      ;
  };

  # Take contents of ./nixos/*.nix and make list of derivations
  configFiles = with builtins;
    dir:
      attrValues (mapAttrs
        (
          name: value: let
            filename =
              if name == "configuration-sample.nix"
              then "configuration.nix"
              else name;
          in
            pkgs.writeTextDir "share/${filename}" (readFile "${dir}/${name}")
        )
        (pkgs.lib.filterAttrs (n: _: pkgs.lib.strings.hasSuffix ".nix" n) (readDir dir)));
in
  assert pkgs.lib.assertMsg (!(bootFromBTRFS && BTRFSDupData)) "bootFromBTRFS and BTRFSDupData are mutually exclusive";
    pkgs.vmTools.runInLinuxVM
    (pkgs.runCommand "btrfspi-sd"
      {
        enableParallelBuildingByDefault = true;
        nativeBuildInputs = with pkgs; [
          btrfs-progs
          dosfstools
          e2fsprogs
          git # initialize repo at `/etc/nixos`
          nix # mv, cp
          util-linux # sfdisk
          btrfspi.config.system.build.nixos-install
        ];

        preVM = ''
          ${pkgs.vmTools.qemu}/bin/qemu-img create -f raw ./btrfspi.iso 8G
        '';
        postVM = with pkgs; ''
          # Truncate the file at the end of the last partition
          PATH=${util-linux}/bin:${jq}/bin:${zstd}/bin:$PATH
          img=./btrfspi.iso

          json=$(sfdisk --json --output end "$img")
          start=$(jq .partitiontable.partitions[-1].start <<< "$json")
          size=$(jq .partitiontable.partitions[-1].size <<< "$json")
          sectsize=$(jq .partitiontable.sectorsize <<< "$json")
          endbytes=$((("$start" + "$size" + 1) * "$sectsize"))

          truncate --size "$endbytes" "$img"

          zstd --compress "$img"

          mkdir -p $out
          mv "$img".zst $out/
        '';
        memSize = "4G";
        QEMU_OPTS =
          "-drive "
          + builtins.concatStringsSep "," [
            "file=./btrfspi.iso"
            "format=raw"
            "if=virtio"
            "cache=unsafe"
            "werror=report"
          ];
      } ''

        # NB: Don't set -f, as some of the builtin nix stuff depends on globbing
        set -Eeu -o pipefail
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

          partNum=$(
            lsblk --paths --list --noheadings --output name,type "$blockDev" |
              awk \
                -v blockdev="$blockDev" \
                '
                  # Assume lsblk has output these in order, get the name of
                  # last device it identifies as a partition
                  $2 == "part" {
                    partname = $1
                  }

                  # Strip out the blockdev so we get just partition number
                  END {
                      gsub(blockdev, "", partname)
                      print partname
                  }
                '
          )

          echo ",$sizeInK" | sfdisk -N"$partNum" "$blockDev"
          ${pkgs.udev}/bin/udevadm settle
        }

        ${pkgs.kmod}/bin/modprobe btrfs
        ${pkgs.udev}/lib/systemd/systemd-udevd &

        # Gap before first partition
        gap=1

        firmwareSize=512
        firmwareSizeBlocks=$(( $firmwareSize * 1024 * 1024 / 512 ))

        # type=b is 'W95 FAT32', 83 is 'Linux'.
        # The "bootable" partition is where u-boot will look file for the bootloader
        # information (dtbs, extlinux.conf file).
        # Setting the bootable flag on the btrfs partition allows booting directly

        fatBootable=
        BTRFSBootable=bootable
        if [ ! ${toString bootFromBTRFS} ]; then
          fatBootable=bootable
          BTRFSBootable=
        fi

        sfdisk /dev/vda <<EOF
          label: dos
          label-id: ${firmwarePartOpts.firmwarePartID}

          start=''${gap}M,size=$firmwareSizeBlocks, type=b, $fatBootable
          start=$(( $gap + $firmwareSize ))M, type=83, $BTRFSBootable
        EOF

        ${pkgs.udev}/bin/udevadm settle

        # rpi firmware
        mkfs.vfat -n ${firmwarePartOpts.firmwarePartName} /dev/vda1

        # btrfs root
        mkfs.btrfs \
          --label NIXOS_SD \
          --uuid "44444444-4444-4444-8888-888888888889" \
          /dev/vda2

        ${pkgs.udev}/bin/udevadm trigger
        ${pkgs.udev}/bin/udevadm settle

        mkdir -p /mnt /btrfs /tmp/firmware

        btrfsopts=space_cache=v2,compress-force=zstd
        mount -t btrfs -o "$btrfsopts" /dev/disk/by-label/NIXOS_SD /btrfs
        btrfs filesystem resize max /btrfs

        for sv in ${toString subvolumes}; do
          btrfs subvolume create /btrfs/"$sv"

          dest="/mnt/''${sv#@}"
          if [[ "$sv" = "@snapshots" ]]; then
            dest=/mnt/.snapshots
          fi
          mkdir -p "$dest"
          mount -t btrfs -o "$btrfsopts,subvol=$sv" /dev/disk/by-label/NIXOS_SD "$dest"
        done
        mkdir -p /mnt/boot/firmware

        # All subvols should now be properly mounted at /mnt
        umount -R /btrfs

        # Enabling compression on /boot prevents uboot from booting directly from
        # BTRFS for some reason. Instead of `chattr +C` could also use
        # `btrfs property set /mnt/boot compression none` but this gets overridden by
        # the `compress-force=zstd` (as opposed to `compress=zstd`) option
        chattr +C /mnt/boot

        # Populate firmware files into FIRMWARE partition
        mount /dev/disk/by-label/${firmwarePartOpts.firmwarePartName} /tmp/firmware
        ${firmwarePartOpts.populateFirmwareCommands}

        echo "${pkgs.lib.concatStringsSep "\n" extraConfigTxt}" >> /tmp/firmware/config.txt

        if [ ${toString bootFromBTRFS} ]; then
          bootDest=/mnt/boot
        else
          bootDest=/tmp/firmware
        fi

        ${firmwarePartOpts.populateCmd} -c ${toplevel} -d "$bootDest" -g 0

        for config in ${toString (configFiles ./nixos)}; do
          install -Dm0644 -t /mnt/etc/nixos "$config"/share/*
        done

        export NIX_STATE_DIR=$TMPDIR/state
        nix-store < ${closure}/registration \
          --load-db \
          --option build-users-group ""

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
          --system ${toplevel}

        # Disable automatic creation of a default nix channel
        # See also `nix-daemon.nix`
        mkdir -p /mnt/root
        touch /mnt/root/.nix-channels

        # Initialize a repo to keep track of config changes and automatic flake input
        # updates
        pushd /mnt/etc/nixos
        git init
        git add .
        popd

        shrinkBTRFSFs /mnt

        local sizeInK
        sizeInK=$(
          btrfs filesystem usage -b /mnt |
          awk '/Device size:/ { print ($NF / 1024) "KiB" }'
        )

        umount -R /mnt /tmp/firmware

        shrinkLastPartition /dev/vda "$sizeInK"
        btrfs check /dev/disk/by-label/NIXOS_SD
      '')
