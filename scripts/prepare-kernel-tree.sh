#!/usr/bin/env bash
#
# Prepare a kernel tree that matches Armbian's meson8b kernel: v6.12.28 with
# the DTS parts of patch/kernel/archive/meson-6.12 applied.
#
# Only arch/arm/boot/dts and include/dt-bindings are checked out (sparse),
# which keeps this at ~50 MB instead of ~1.5 GB.
#
# Usage:
#   ./scripts/prepare-kernel-tree.sh [DEST]
#
# Environment:
#   KVER           kernel tag to fetch (default: v6.12.28, matching
#                  config/sources/families/include/meson_common.inc)
#   PATCH_REFRESH  re-download the cached Armbian patches (PATCH_REFRESH=1)
#
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$here")"          # repo root

KVER="${KVER:-v6.12.28}"
DEST="${1:-$root/.dev/linux}"

PATCH_BASE="https://raw.githubusercontent.com/armbian/build/main/patch/kernel/archive/meson-6.12"

# DTS-only patches needed by this board (mirrors the family's patch order).
# 0011 only affects usb0_phy (OTG ID gpio), but it is included so the DTB
# built here is identical to the one Armbian packages.
PATCHES=(
	0011-ARM-dts-meson-Add-GPIO-controller-capabilities-to-th.patch
	0028-ARM-dts-meson-Add-address-cells-size-cells-and-range.patch
	0059-ARM-dts-meson-add-the-VPU-WiP.patch
	0061-ARM-dts-meson8-Add-the-shared-CMA-dma-memory-pool.patch
	0063-ARM-dts-meson8b-add-the-HDMI-controller-WiP.patch
	0064-ARM-dts-meson8b-add-the-AO-CEC-controller-WiP.patch
)

if [ ! -d "$DEST/.git" ]; then
	echo ">> sparse clone linux $KVER -> $DEST"
	mkdir -p "$(dirname -- "$DEST")"
	git clone --depth 1 --filter=blob:none --sparse --branch "$KVER" \
		https://github.com/gregkh/linux.git "$DEST"
	git -C "$DEST" sparse-checkout set arch/arm/boot/dts include/dt-bindings include/uapi
else
	have="$(git -C "$DEST" describe --tags --always 2>/dev/null || true)"
	if [ "$have" != "$KVER" ]; then
		echo "error: $DEST is at ${have:-an unknown revision}, expected $KVER" >&2
		echo "       remove the tree (rm -rf \"$DEST\") and re-run" >&2
		exit 1
	fi
	echo ">> reusing existing tree $DEST"
fi

dts="$DEST/arch/arm/boot/dts/amlogic"
cache="$root/.dev/patches"
mkdir -p "$cache"

# Start from a pristine device-tree directory: re-running this script is then
# safe and always produces the same tree (like a fresh Armbian build).
echo ">> resetting $dts"
git -C "$DEST" reset -q HEAD -- arch/arm/boot/dts
git -C "$DEST" checkout -- arch/arm/boot/dts
git -C "$DEST" clean -fdq arch/arm/boot/dts

# -f: never prompt (stdin is the patch itself).
apply() {
	patch -d "$DEST" -p1 -f --no-backup-if-mismatch -s <"$1"
}

for p in "${PATCHES[@]}"; do
	if [ -n "${PATCH_REFRESH:-}" ] || [ ! -f "$cache/$p" ]; then
		rm -f "$cache/$p"
		curl -sSfL -o "$cache/$p" "$PATCH_BASE/$p"
	fi
	apply "$cache/$p"
	echo ">> $(echo "$p" | cut -c1-4) applied"
done

# Only the Armbian family patches are applied here; the board DTS is
# compiled straight from dts/ (see build-dtb.sh) and turned into an Armbian
# patch on demand by make-armbian-patch.sh.
rejects="$(find "$dts" -name '*.rej')"
if [ -n "$rejects" ]; then
	echo "error: some hunks were rejected:" >&2
	echo "$rejects" >&2
	exit 1
fi
if ! grep -q 'hdmi_tx: hdmi-tx@42000' "$dts/meson8b.dtsi"; then
	echo "error: patching did not produce the expected meson8b.dtsi" >&2
	exit 1
fi

echo ">> kernel tree ready: $DEST"
