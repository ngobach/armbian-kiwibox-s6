#!/bin/bash
#
# Armbian image-build host hooks.
#
# Sourced on the build host from customize_image(), before
# userpatches/customize-image.sh is copied into the chroot. It is the right
# place to put board files into $SDCARD: no chroot, no package manager.
#
# The hook file is sourced, so everything below either defines a function or
# runs inline - and any early `return` exits the whole file, so the function
# definitions come first.
#
# Two jobs:
#
#  1. install the AP6181 (BCM43362) NVRAM. linux-firmware ships the matching
#     brcmfmac43362-sdio.bin but no NVRAM for this board, and without it
#     brcmfmac loads the firmware and then fails calibration -> no wlan0.
#     The file is NOT duplicated in this overlay; it is uploaded next to it:
#
#       rsync -a firmware/ <builder>:~/build/userpatches/kiwibox-firmware/
#
#  2. retag the boot partition from MBR type 0xEA to 0x0C so macOS mounts it.
#
# A no-op for any other board.

# ---------------------------------------------------------------------------
# post_build_image_modify - called by Armbian after the final .img is produced,
# before fingerprinting and compression (lib/functions/image/rootfs-to-image.sh
# checks for this function with `type -t`, so simply defining it here is
# enough; no extension machinery and no extra build flag).
#
# Armbian hardcodes MBR type 0xEA ("Linux extended boot") for the boot
# partition on all non-GPT images. macOS refuses to mount a 0xEA partition, so
# the FAT boot partition is invisible there and "reuse the card and deploy over
# /Volumes/BOOT" needs a manual sudo mount. Retagging it as 0x0C (FAT32 LBA)
# makes macOS mount it automatically.
#
# The factory 2015 Amlogic u-boot scans for a FAT filesystem and ignores the
# type byte - verified on hardware by booting an image with this modified
# table. Only byte 450 (partition entry 1, the type field) is changed.
# ---------------------------------------------------------------------------
post_build_image_modify() {
	local img="${1:-}"

	[[ -n $img && -f $img ]] || return 0
	[[ "${BOARD:-}" == "kiwibox-s6" ]] || return 0

	local cur
	cur=$(od -An -tx1 -j 450 -N 1 "$img" | tr -d ' \n')

	case "$cur" in
	ea)
		printf '\x0c' | dd of="$img" bs=1 seek=450 count=1 conv=notrunc status=none
		kwb_log "Kiwibox S6 partition type" "boot partition 0xEA -> 0x0C (macOS mountable)" "info"
		;;
	0c)
		kwb_log "Kiwibox S6 partition type" "already 0x0C, nothing to do" "debug"
		;;
	*)
		kwb_log "Kiwibox S6 partition type" "unexpected type 0x${cur} in ${img}, left alone" "wrn"
		;;
	esac

	return 0
}

# ---------------------------------------------------------------------------
# Inline part: install the board NVRAM into the image rootfs.
# ---------------------------------------------------------------------------

kwb_log() {
	if declare -F display_alert >/dev/null; then
		display_alert "$1" "$2" "$3"
	else
		echo "[kiwibox-s6] $1: $2" >&2
	fi
}

# Sourced, not executed: use return, never exit.
if [[ "${BOARD:-}" != "kiwibox-s6" ]]; then
	return 0
fi

kwb_fw_src="${SRC}/userpatches/kiwibox-firmware/brcmfmac43362-sdio.txt"
kwb_fw_dst="${SDCARD}/usr/lib/firmware/brcm"

if [[ ! -f "${kwb_fw_src}" ]]; then
	kwb_log "Kiwibox S6 firmware not found" "${kwb_fw_src} (rsync firmware/ into userpatches/kiwibox-firmware/)" "wrn"
	return 0
fi

install -d "${kwb_fw_dst}"
install -m 644 "${kwb_fw_src}" "${kwb_fw_dst}/brcmfmac43362-sdio.txt"
kwb_log "Kiwibox S6 firmware" "installed brcmfmac43362-sdio.txt into ${kwb_fw_dst}" "info"

return 0
