#!/usr/bin/env bash
#
# Install the Kiwibox S6 DTB and a matching boot script onto an Armbian
# OneCloud SD card (the FAT boot partition), so the existing vendor
# Amlogic u-boot can boot it.
#
# Usage:
#   ./scripts/deploy.sh /Volumes/BOOT            # SD card, bootdev default "mmc 0"
#   ./scripts/deploy.sh /Volumes/BOOT "mmc 1"    # override default bootdev
#
# Options:
#   --autoscript   also write an "aml_autoscript" (hands-free boot attempt;
#                  behaviour depends on your u-boot, untested on this box)
#
# Requires: mkimage (brew install u-boot-tools) and a built DTB
#           (./scripts/build-dtb.sh).
#
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$here")"

name="meson8b-kiwibox-s6"
dtb="$root/out/$name.dtb"
autoscript=0

args=()
for a in "$@"; do
	case "$a" in
	--autoscript) autoscript=1 ;;
	*) args+=("$a") ;;
	esac
done

boot="${args[0]:-}"
bootdev="${args[1]:-mmc 0}"

if [ -z "$boot" ]; then
	echo "usage: $0 /Volumes/BOOT [bootdev] [--autoscript]" >&2
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

[ -f "$boot/boot.scr" ] && cp "$boot/boot.scr" "$boot/boot.scr.orig"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# boot-kiwibox-s6.cmd is the single source of truth (it is also what goes
# into Armbian as config/bootscripts/boot-kiwibox-s6.cmd).
sed "s|^\([[:space:]]*setenv bootdev \).*|\1\"$bootdev\"|" \
	"$root/armbian/config/bootscripts/boot-kiwibox-s6.cmd" >"$tmp/boot.cmd"

mkimage -A arm -T script -C none -n "Kiwibox S6 boot" \
	-d "$tmp/boot.cmd" "$boot/boot.scr" >/dev/null

cp "$tmp/boot.cmd" "$boot/boot.cmd.kwb"

if [ "$autoscript" = 1 ]; then
	cat >"$boot/aml_autoscript" <<EOF
setenv bootdev "$bootdev"
fatload $bootdev 0x20800000 boot.scr && autoscr 0x20800000
EOF
	echo ">> wrote $boot/aml_autoscript"
fi

echo ">> wrote $boot/boot.scr (from boot.cmd, bootdev default: $bootdev)"

cat <<EOF

Next step, in the u-boot prompt (serial, 115200 8N1):

  setenv bootdev "$bootdev"
  fatload \${bootdev} 0x20800000 boot.scr && autoscr 0x20800000

  (some u-boot builds use "source" instead of "autoscr")

Without a boot script:

  fatload $bootdev 0x20800000 uImage
  fatload $bootdev 0x22000000 uInitrd
  fatload $bootdev 0x21800000 dtb/$name.dtb
  setenv bootargs root=/dev/mmcblk0p1 rootwait rw console=ttyAML0,115200n8
  bootm 0x20800000 0x22000000 0x21800000

Replaced files are backed up as boot.scr.orig; the script this tool
compiled is also saved next to it as boot.cmd.kwb.
EOF
