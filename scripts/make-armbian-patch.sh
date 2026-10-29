#!/usr/bin/env bash
#
# Regenerate the Armbian kernel patch from dts/meson8b-kiwibox-s6.dts:
#
#   armbian/patch/kernel/archive/meson-6.12/kiwibox-0001-add-dts.patch
#
# The DTS is the source of truth; the patch is a generated artifact kept in
# the repo so it can be copied into armbian/build as-is.
#
# Requires a prepared kernel tree (./scripts/prepare-kernel-tree.sh), which
# provides the Armbian meson8b patches this DTS depends on.
#
# Usage:
#   ./scripts/make-armbian-patch.sh [KERNEL_DIR]
#
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$here")"          # repo root

KERNEL_DIR="${1:-${KERNEL_DIR:-$root/.dev/linux}}"

name="meson8b-kiwibox-s6"
src="$root/dts/$name.dts"
kdir="$KERNEL_DIR/arch/arm/boot/dts/amlogic"
dst="$kdir/$name.dts"
out="$root/armbian/patch/kernel/archive/meson-6.12/kiwibox-0001-add-dts.patch"

[ -f "$src" ] || { echo "error: $src missing" >&2; exit 1; }
[ -d "$kdir" ] || { echo "error: no kernel tree at $KERNEL_DIR (run make prepare)" >&2; exit 1; }
grep -q 'hdmi_tx: hdmi-tx@42000' "$kdir/meson8b.dtsi" || {
	echo "error: $KERNEL_DIR is not prepared (run make prepare)" >&2
	exit 1
}

cleanup() {
	git -C "$KERNEL_DIR" reset -q HEAD -- "arch/arm/boot/dts/amlogic/$name.dts" 2>/dev/null || true
	rm -f "$dst"
	git -C "$KERNEL_DIR" checkout -- arch/arm/boot/dts/amlogic/Makefile 2>/dev/null || true
}
trap cleanup EXIT

cp "$src" "$dst"

# Same insertion point as the committed patch: after meson8b-odroidc1.dtb.
python3 - "$kdir/Makefile" <<'PY'
import sys

path = sys.argv[1]
line = "\tmeson8b-kiwibox-s6.dtb \\\n"
text = open(path).read()
if line not in text:
    text = text.replace("\tmeson8b-odroidc1.dtb \\\n",
                        "\tmeson8b-odroidc1.dtb \\\n" + line, 1)
    open(path, "w").write(text)
PY

git -C "$KERNEL_DIR" add -N "arch/arm/boot/dts/amlogic/$name.dts"
mkdir -p "$(dirname "$out")"
git -C "$KERNEL_DIR" diff -- \
	"arch/arm/boot/dts/amlogic/Makefile" \
	"arch/arm/boot/dts/amlogic/$name.dts" >"$out"

echo ">> wrote ${out#"$root"/}"
