{ pkgs }:
let
  pkgsArm = import pkgs.path {
    system = "x86_64-linux";
    crossSystem = {
      config = "aarch64-unknown-linux-gnu";
    };
    overlays = [
      (self: super: {
        ubootRaspberryPi3_64bit = super.ubootRaspberryPi3_64bit.overrideAttrs (oldAttrs: {
          # defconfig = "rpi_3_b_plus_defconfig";
          extraConfig = ''
            CONFIG_CMD_BTRFS=y
            CONFIG_ZSTD=y
            CONFIG_BOOTCOMMAND="setenv boot_prefixes / /boot/ /@/ /@boot/; run distro_bootcmd;"
          '';
        });
      })
    ];
  };

  btrfspi = import (pkgsArm.path + "/nixos") {
    configuration = {
      nixpkgs.system = "aarch64-linux";
      imports = [
        ./nixos/configuration-sample.nix
      ];
    };
  };

  toplevel = btrfspi.config.system.build.toplevel;
  closure = pkgsArm.closureInfo
    { rootPaths = [ toplevel ]; };
  # uboot = btrfspi.config.system.build.uboot;

  subvolumes = [ "@" "@boot" "@home" "@nix" "@snapshots" "@var" ];

  firmwarePartOpts =
    let
      sdImage = (import (pkgs.path + "/nixos/modules/installer/sd-card/sd-image.nix") {
        inherit pkgs;
        config = pkgs.config;
        lib = pkgs.lib;
      }).options.sdImage;
    in
    {
      firmwarePartID = sdImage.firmwarePartitionID.default;
      firmwarePartName = sdImage.firmwarePartitionName.default;
      inherit ((import (pkgs.path + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix") {
        pkgs = pkgsArm;
        config = pkgsArm.config;
        lib = pkgsArm.lib;
      }).sdImage) populateFirmwareCommands;

    };

  populateCmd = (import (pkgs.path + "/nixos/modules/system/boot/loader/generic-extlinux-compatible")
    {
      inherit pkgs;
      config = btrfspi.config;
      lib = btrfspi.pkgs.lib;
    }).config.content.boot.loader.generic-extlinux-compatible.populateCmd;

  configFiles = builtins.mapAttrs (name: val: (name: builtins.readFile val) (pkgs.lib.filterAttrs (n: _: pkgs.lib.strings.hasSuffix ".nix" n) (builtins.readDir ./nixos)));
  writeConfigFiles = dest: builtins.mapAttrs (name: val: builtins.toFile (dest + name) configFiles);
in

pkgs.vmTools.runInLinuxVM (pkgs.runCommand "btrfspi-sd"
  {

    buildInputs = [
      # pkgsArm.nixos-install-tools
      btrfspi.config.system.build.nixos-enter
      btrfspi.config.system.build.nixos-install
    ];

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
      ];

    preVM = ''
      ${pkgs.vmTools.qemu}/bin/qemu-img create -f raw ./btrfspi.iso 4G
    '';
    postVM = ''
      img=./btrfspi.iso

      json=$(${pkgs.util-linux}/bin/sfdisk --json --output end "$img")
      start=$(${pkgs.jq}/bin/jq .partitiontable.partitions[-1].start <<< "$json")
      size=$(${pkgs.jq}/bin/jq .partitiontable.partitions[-1].size <<< "$json")
      sectsize=$(${pkgs.jq}/bin/jq .partitiontable.sectorsize <<< "$json")
      endbytes=$((("$start" + "$size" + 1) * "$sectsize"))

      truncate --size "$endbytes" "$img"

      mkdir -p $out
      mv "$img" $out/
    '';
    memSize = "4G";
    QEMU_OPTS = "-drive format=raw,file=./btrfspi.iso,if=virtio -smp 4";
    # passthru.uboot = uboot;
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
  # cp ''${uboot}/u-boot.bin /tmp/firmware/u-boot-rpi3.bin

  umount -R /tmp/firmware

  ## populate partition 3
  mount -t btrfs -o space_cache=v2,compress-force=zstd /dev/vda3 /btrfs
  btrfs filesystem resize max /btrfs

  for sv in ${builtins.toString subvolumes}; do
    echo "working with $sv"
    btrfs subvolume create /btrfs/"$sv"

    dest="/mnt/''${sv#@}"
    if [[ "$sv" = "@snapshots" ]]; then
      dest=/mnt/.snapshots
    fi
    mkdir -p "$dest"
    mount -t btrfs -o space_cache=v2,compress=zstd,subvol=$sv /dev/vda3 "$dest"
  done

  # All subvols should now be properly mounted at /mnt
  umount -R /btrfs

  ${populateCmd} -c ${toplevel} -d /mnt/boot -g 0

  mkdir -p /mnt/etc/nixos
  # ''${writeConfigFiles "/mnt/etc/nixos/"} # not working yet

  export NIX_STATE_DIR=$TMPDIR/state
  nix-store --load-db < ${closure}/registration

  # mkdir -p /mnt/nix/var/nix/profiles /mnt/etc /mnt/boot
  # ln -s ${toplevel} /mnt/nix/var/nix/profiles/system
  # chroot /mnt ${toplevel}/bin/switch-to-configuration boot --install-bootloader

  echo "running nixos-install..."
  nixos-install \
    --max-jobs 4 \
    --cores 0 \
    --root /mnt \
    --no-root-passwd \
    --system ${toplevel} \
    --no-bootloader \
    --substituters ""

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
    shrink_by=$(python3 -c "print(int($free_min * 0.90))")
    btrfs filesystem resize -"$shrink_by" /mnt || break
  done

  local size
  size=$(btrfs filesystem usage -b /mnt | awk '/Device size:/ { print $NF }')

  btrfs scrub start -B /mnt
  # btrfs filesystem balance --full-balance /mnt
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
