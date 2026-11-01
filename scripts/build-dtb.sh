#!/usr/bin/env bash
#
# Build meson8b-kiwibox-s6.dtb on macOS (or any host with clang + dtc).
#
# The board DTS references labels that only exist after Armbian's
# patch/kernel/archive/meson-6.12 patches are applied to the kernel tree,
# so KERNEL_DIR must point at a prepared tree (see prepare-kernel-tree.sh).
#
# Usage:
#   ./scripts/build-dtb.sh [KERNEL_DIR]
#
# Environment:
#   KERNEL_DIR  kernel source tree (default: <repo>/.dev/linux)
#   CC          C preprocessor to use (default: clang)
#
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$here")"          # repo root

KERNEL_DIR="${1:-${KERNEL_DIR:-$root/.dev/linux}}"
CC="${CC:-clang}"
dts="$root/dts/meson8b-kiwibox-s6.dts"
out="$root/out"
name="meson8b-kiwibox-s6"

command -v dtc >/dev/null || { echo "error: dtc not found (brew install dtc)" >&2; exit 1; }
command -v "$CC" >/dev/null || { echo "error: $CC not found (Xcode command line tools)" >&2; exit 1; }

[ -d "$KERNEL_DIR/arch/arm/boot/dts/amlogic" ] || {
	echo "error: no kernel tree at $KERNEL_DIR" >&2
	echo "       run ./scripts/prepare-kernel-tree.sh first" >&2
	exit 1
}

# Refuse to build against a vanilla tree: the board DTS needs the
# Armbian-added hdmi_tx / vpu / hhi labels.
if ! grep -q 'hdmi_tx: hdmi-tx@42000' "$KERNEL_DIR/arch/arm/boot/dts/amlogic/meson8b.dtsi"; then
	echo "error: $KERNEL_DIR/arch/arm/boot/dts/amlogic/meson8b.dtsi is missing the" >&2
	echo "       Armbian meson8b HDMI/VPU patches (label hdmi_tx)." >&2
	echo "       run ./scripts/prepare-kernel-tree.sh to prepare a patched tree." >&2
	exit 1
fi

# The board DTS references the SDIO port 0 / 32 kHz pinctrl labels added by
# kiwibox-0002; without them dtc fails with an unhelpful unknown-label error.
if ! grep -q 'sd_a_pins: sd-a' "$KERNEL_DIR/arch/arm/boot/dts/amlogic/meson8b.dtsi"; then
	echo "error: $KERNEL_DIR/arch/arm/boot/dts/amlogic/meson8b.dtsi is missing the" >&2
	echo "       kiwibox-0002 pinctrl labels (sd_a_pins, xtal_32k_out_pins)." >&2
	echo "       run ./scripts/prepare-kernel-tree.sh to prepare a patched tree." >&2
	exit 1
fi

mkdir -p "$out"

"$CC" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
	-I"$KERNEL_DIR/include" \
	-I"$KERNEL_DIR/arch/arm/boot/dts" \
	-I"$KERNEL_DIR/arch/arm/boot/dts/amlogic" \
	-o "$out/$name.dts.pre" \
	"$dts"

dtc -q -I dts -O dtb -o "$out/$name.dtb" "$out/$name.dts.pre"

printf '%s\n' "built $out/$name.dtb ($(wc -c <"$out/$name.dtb" | tr -d ' ') bytes)"
