#!/usr/bin/env bash
#
# Install the Kiwibox S6 DTB and the boot script onto the FAT boot partition
# of an Armbian SD card (typically a OneCloud image used as the base), so the
# factory Amlogic u-boot can boot it.
#
# The compiled script is installed both as boot.scr and as s805_autoscript:
# the 2015 S805 u-boot searches the medium for the latter (this is what
# Armbian's aml-s805-mxq.tvb board sets via BOOTSCRIPT_OUTPUT), so booting
# can be hands-free.
#
# Usage:
#   ./scripts/deploy.sh /Volumes/BOOT              # bootdev auto-detected
#   ./scripts/deploy.sh /Volumes/BOOT "mmc 1"      # force eMMC
#
# Requires: mkimage (brew install u-boot-tools) and a built DTB
#           (./scripts/build-dtb.sh).
#
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$here")"

name="meson8b-kiwibox-s6"
dtb="$root/out/$name.dtb"
boot="${1:-}"
bootdev="${2:-}"

if [ -z "$boot" ]; then
	echo "usage: $0 /Volumes/BOOT [bootdev]" >&2
	exit 1
fi
[ -f "$dtb" ] || { echo "error: $dtb missing, run ./scripts/build-dtb.sh" >&2; exit 1; }
command -v mkimage >/dev/null || { echo "error: mkimage not found (brew install u-boot-tools)" >&2; exit 1; }
[ -f "$boot/armbianEnv.txt" ] || {
	echo "warning: $boot/armbianEnv.txt not found - is this the Armbian boot partition?" >&2
	read -r -p "continue anyway? [y/N] " yn
	[ "$yn" = "y" ] || exit 1
}

echo ">> installing $name.dtb"
mkdir -p "$boot/dtb"
cp "$dtb" "$boot/dtb/$name.dtb"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# boot-kiwibox-s6.cmd is the single source of truth (it is also what goes
# into Armbian as config/bootscripts/boot-kiwibox-s6.cmd).
src="$root/armbian/config/bootscripts/boot-kiwibox-s6.cmd"
if [ -n "$bootdev" ]; then
	{
		echo "setenv bootdev \"$bootdev\""
		cat "$src"
	} >"$tmp/boot.cmd"
else
	cp "$src" "$tmp/boot.cmd"
fi

mkimage -A arm -T script -C none -n "Kiwibox S6 boot" \
	-d "$tmp/boot.cmd" "$tmp/boot.scr" >/dev/null

for f in boot.scr s805_autoscript; do
	# Keep the first backup ever taken: re-running deploy must not replace
	# the stock Armbian script with a previously deployed copy of ours.
	if [ -f "$boot/$f" ] && [ ! -f "$boot/$f.orig" ]; then
		cp "$boot/$f" "$boot/$f.orig"
	fi
	cp "$tmp/boot.scr" "$boot/$f"
done
cp "$tmp/boot.cmd" "$boot/boot.cmd.kwb"

echo ">> wrote $boot/boot.scr and $boot/s805_autoscript"
if [ -n "$bootdev" ]; then
	echo ">> boot script forces bootdev=\"$bootdev\""
fi

cat <<EOF

Reboot the box. The factory u-boot should find s805_autoscript and boot
without any prompt interaction.

If it drops into the u-boot prompt instead, the script name or search order
differs on this loader; boot by hand (serial, 115200 8N1):

  setenv bootdev "mmc 0"        # mmc 0 = SD card, mmc 1 = eMMC, usb 0 = USB
  fatload \${bootdev} 0x20800000 boot.scr && autoscr 0x20800000

  (some u-boot builds use "source" instead of "autoscr")

Or without a script at all:

  fatload mmc 0 0x20800000 uImage
  fatload mmc 0 0x22000000 uInitrd
  fatload mmc 0 0x21800000 dtb/$name.dtb
  setenv bootargs root=LABEL=armbi_root rootwait rw console=ttyAML0,115200n8
  bootm 0x20800000 0x22000000 0x21800000

Replaced files are kept as boot.scr.orig / s805_autoscript.orig; the script
this tool compiled is saved next to them as boot.cmd.kwb.
EOF
