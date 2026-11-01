#!/bin/sh
#
# set-parttype.sh - retag the Kiwibox boot partition 0xEA <-> 0x0C (MBR)
#
# Armbian tags the FAT boot partition as MBR type 0xEA ("Linux extended boot").
# macOS refuses to mount that, so /Volumes/BOOT never appears and deploying a
# new DTB means a manual `sudo mount -t msdos`. Retagging it 0x0C (FAT32 LBA)
# makes macOS mount it like any other stick.
#
# The factory 2015 Amlogic u-boot looks for a FAT filesystem and ignores the
# type byte, so this does not affect booting (verified on hardware).
#
# Only byte 450 of sector 0 is changed - partition entry 1, the type field.
# Boot code, disk signature, the other three entries and the 55AA signature are
# written back exactly as read.
#
# Usage:
#   sudo ./scripts/set-parttype.sh --show              # print layout, change nothing
#   sudo ./scripts/set-parttype.sh /dev/disk4          # 0xEA -> 0x0C (asks first)
#   sudo ./scripts/set-parttype.sh /dev/disk4 --yes    # no prompt
#   sudo ./scripts/set-parttype.sh /dev/disk4 --restore    # back to 0xEA
#
# macOS only (uses diskutil and /dev/rdiskN). On Linux the equivalent is:
#   sudo sfdisk --part-type /dev/sdX 1 c
#
# Writes go out with bs=512 because macOS rejects byte-granular writes to
# /dev/rdiskN with EINVAL.

set -u

TYPE_OFF=450 # partition entry 1 type field: 446 + 4
TYPE_FAT32=0c
TYPE_LINUXBOOT=ea

MODE=patch
ASSUME_YES=no
DEV=/dev/rdisk4

for arg in "$@"; do
	case "$arg" in
	--show) MODE=show ;;
	--restore) MODE=restore ;;
	--yes | -y) ASSUME_YES=yes ;;
	-h | --help)
		sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	/dev/*) DEV="$arg" ;;
	*)
		echo "unknown argument: $arg" >&2
		exit 2
		;;
	esac
done

[ "$(id -u)" -eq 0 ] || {
	echo "run this with sudo" >&2
	exit 1
}
command -v diskutil >/dev/null || {
	echo "this script is for macOS; on Linux use: sudo sfdisk --part-type <dev> 1 c" >&2
	exit 1
}

# Accept /dev/diskN and use the raw node for I/O.
case "$DEV" in
/dev/disk*) DEV="/dev/r${DEV#/dev/}" ;;
esac
DK="/dev/${DEV#/dev/r}"

[ -e "$DEV" ] || {
	echo "no such device: $DEV" >&2
	exit 1
}

TMP=$(mktemp /tmp/kwb-mbr.XXXXXX) || exit 1
TMP2=$(mktemp /tmp/kwb-mbr.XXXXXX) || exit 1
trap 'rm -f "$TMP" "$TMP2"' EXIT

get8() { od -An -tx1 -j "$1" -N 1 "$TMP2" | tr -d ' \n'; }
get32() { od -An -tu4 -j "$1" -N 4 "$TMP2" | tr -d ' '; }

read_mbr() {
	dd if="$DEV" bs=512 count=1 of="$TMP2" 2>/dev/null || {
		echo "cannot read $DEV" >&2
		exit 1
	}
	SIG=$(od -An -tx1 -j 510 -N 2 "$TMP2" | tr -d ' \n')
	[ "$SIG" = "55aa" ] || {
		echo "no MBR signature in sector 0 - refusing (GPT disk?)" >&2
		exit 1
	}
	TYPE1=$(get8 $TYPE_OFF)
	TYPE2=$(get8 466)
	START1=$(get32 454)
	SIZE1=$(get32 458)
	START2=$(get32 470)
	SIZE2=$(get32 474)
}

show() {
	echo "device: $DEV  ($DK)"
	echo "  partition 1: type 0x$TYPE1  start sector $START1  $SIZE1 sectors (~$((SIZE1 / 2048)) MiB)"
	echo "  partition 2: type 0x$TYPE2  start sector $START2  $SIZE2 sectors (~$((SIZE2 / 2048)) MiB)"
}

read_mbr
show

[ "$MODE" = show ] && exit 0

if [ "$MODE" = patch ]; then
	if [ "$TYPE1" = "$TYPE_FAT32" ]; then
		echo "partition 1 is already 0x0C - nothing to do"
		exit 0
	fi
	[ "$TYPE1" = "$TYPE_LINUXBOOT" ] || {
		echo "partition 1 is 0x$TYPE1, expected 0xEA - refusing to touch it" >&2
		exit 1
	}
	NEW=$TYPE_FAT32
	WHAT="0xEA -> 0x0C (macOS will mount it)"
else
	if [ "$TYPE1" = "$TYPE_LINUXBOOT" ]; then
		echo "partition 1 is already 0xEA - nothing to do"
		exit 0
	fi
	NEW=$TYPE_LINUXBOOT
	WHAT="0x$TYPE1 -> 0xEA (original)"
fi

echo
echo "about to change partition 1 type $WHAT"
echo "this edits ONLY byte $TYPE_OFF of the MBR; the filesystems are untouched."
if [ "$ASSUME_YES" != yes ]; then
	printf 'proceed? type yes: '
	read -r answer
	[ "$answer" = yes ] || {
		echo "aborted"
		exit 1
	}
fi

BACKUP="/tmp/kwb-mbr-$(basename "$DEV")-$(date +%Y%m%d-%H%M%S).bin"
cp "$TMP2" "$BACKUP" || {
	echo "cannot write backup" >&2
	exit 1
}
echo "original MBR saved to $BACKUP"

cp "$TMP2" "$TMP"
printf "\\x$NEW" | dd of="$TMP" bs=1 seek=$TYPE_OFF count=1 conv=notrunc 2>/dev/null

echo "writing sector 0 back..."
dd if="$TMP" of="$DEV" bs=512 count=1 conv=notrunc 2>/dev/null || {
	echo "write failed (macOS may need Full Disk Access for your terminal)" >&2
	exit 1
}

read_mbr
if [ "$TYPE1" != "$NEW" ]; then
	echo "verification failed: partition 1 is 0x$TYPE1 after the write" >&2
	exit 1
fi

echo "ok, partition 1 is now 0x$TYPE1"
show
echo
diskutil unmountDisk "$DK" >/dev/null 2>&1 || true
diskutil list "$DK" 2>/dev/null || true
echo
echo "next:     diskutil mount ${DK}s1    (replug the reader if the old type is cached)"
echo "rollback: sudo dd if=$BACKUP of=$DEV bs=512 count=1 conv=notrunc"
