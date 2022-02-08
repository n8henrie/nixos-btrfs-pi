# This doesn't work yet

At least `download.sh` isn't there. Apparently the dtbs have to be compiled
from the linux source, I don't feel like doing that yet.

The `dtbs/nixos2205` are just copied from a raspberry pi SD image.

NB: There is some disagreement between the names and what we're actually
getting; for example:

<https://github.com/NixOS/nixpkgs/blob/bcec18a34572a5f72091eb22b9a544e4094a4684/pkgs/os-specific/linux/kernel/linux-rpi.nix#L58>

```
copyDTB bcm2710-rpi-3-b.dtb bcm2837-rpi-3-b.dtb
copyDTB bcm2710-rpi-3-b-plus.dtb bcm2837-rpi-3-a-plus.dtb
copyDTB bcm2710-rpi-3-b-plus.dtb bcm2837-rpi-3-b-plus.dtb
```
