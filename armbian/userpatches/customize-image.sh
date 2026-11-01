#!/bin/bash
#
# Armbian image customization, executed *inside* the image chroot
# (copied to /tmp/customize-image.sh and run as root). Arguments:
#   $1 RELEASE  $2 LINUXFAMILY  $3 BOARD  $4 BUILD_DESKTOP
#
# Purpose: make the image fit a 2 GiB SD card on a NAS box that keeps its
# data on USB. Nothing here changes functionality on this board; it only
# removes firmware and documentation for hardware an Amlogic S805 TV box
# cannot have.
#
# The firmware package ships blobs for every board Armbian supports. On the
# CLI trixie image /usr/lib/firmware is ~525 MiB, of which qcom alone is
# 325 MiB (Qualcomm modem/DSP) and the ath*/rkwifi/mediatek/rtw89 trees are
# PCIe WiFi for completely different SoCs. Only brcm is needed here (the
# AP6181), plus regulatory.db which cfg80211 reads at module load.
#
# Kept on purpose: brcm/, regulatory.db*, rtl_*/ (cheap USB WiFi dongles),
# updates/, and every small tree not listed below.

set -u

FIRMWARE=/usr/lib/firmware

echo "[kiwibox] pruning firmware for hardware this SoC cannot have"
for tree in qcom ath10k ath11k ath12k adsp.b26 adsp.b41 \
            rkwifi aic8800 uwe5622 rtw89 mediatek intel \
            iwlwifi i915 amdgpu nvidia amd-ucode; do
	[ -e "$FIRMWARE/$tree" ] || continue
	rm -rf "$FIRMWARE/$tree" || true
done

# NOTE: do not "fix up" /lib/firmware here. On merged-usr systems /lib is a
# symlink to usr/lib, so /lib/firmware *is* /usr/lib/firmware: touching it
# deletes the very tree we just pruned (and recreates it as a symlink to
# itself). Verified the hard way - the resulting image booted but had no
# brcmfmac firmware at all.

echo "[kiwibox] removing documentation and package caches"
rm -rf /usr/share/doc/* 2>/dev/null || true
rm -rf /usr/share/man/* 2>/dev/null || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb 2>/dev/null || true
rm -rf /var/cache/ldconfig/aux-cache 2>/dev/null || true

# plymouth has no use on a headless board and only delays the boot.
if command -v dpkg >/dev/null && dpkg -s plymouth >/dev/null 2>&1; then
	echo "[kiwibox] removing plymouth"
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq remove --purge --auto-remove plymouth >/dev/null 2>&1 || true
	rm -rf /usr/share/plymouth /etc/plymouth 2>/dev/null || true
fi

apt-get clean >/dev/null 2>&1 || true

echo "[kiwibox] rootfs after pruning: $(du -sh --apparent-size / 2>/dev/null | cut -f1)"

exit 0
