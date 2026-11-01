#!/bin/bash
#
# Armbian image-build host hook.
#
# Sourced on the build host from customize_image(), before
# userpatches/customize-image.sh is copied into the chroot. It is the right
# place to put board files into $SDCARD: no chroot, no package manager.
#
# Purpose here: install the AP6181 (BCM43362) NVRAM. linux-firmware ships the
# matching brcmfmac43362-sdio.bin but no NVRAM for this board, and without it
# brcmfmac loads the firmware and then fails calibration -> no wlan0.
#
# The file is NOT duplicated in this overlay. It is uploaded next to it:
#
#   rsync -a firmware/ <builder>:~/build/userpatches/kiwibox-firmware/
#
# and this hook copies it into the image. A no-op for any other board.

# Sourced, not executed: use return, never exit.
if [[ "${BOARD:-}" != "kiwibox-s6" ]]; then
	return 0
fi

kwb_fw_src="${SRC}/userpatches/kiwibox-firmware/brcmfmac43362-sdio.txt"
kwb_fw_dst="${SDCARD}/usr/lib/firmware/brcm"

kwb_log() {
	if declare -F display_alert >/dev/null; then
		display_alert "$1" "$2" "$3"
	else
		echo "[kiwibox-s6] $1: $2" >&2
	fi
}

if [[ ! -f "${kwb_fw_src}" ]]; then
	kwb_log "Kiwibox S6 firmware not found" "${kwb_fw_src} (rsync firmware/ into userpatches/kiwibox-firmware/)" "wrn"
	return 0
fi

install -d "${kwb_fw_dst}"
install -m 644 "${kwb_fw_src}" "${kwb_fw_dst}/brcmfmac43362-sdio.txt"
kwb_log "Kiwibox S6 firmware" "installed brcmfmac43362-sdio.txt into ${kwb_fw_dst}" "info"

return 0
