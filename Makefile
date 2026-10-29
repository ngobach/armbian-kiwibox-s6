# Kiwibox S6 (Amlogic S805 / Meson8b) - Armbian board port
#
#   make prepare   sparse kernel clone + Armbian meson8b DTS patches (.dev/linux)
#   make dtb       compile dts/ -> out/meson8b-kiwibox-s6.dtb
#   make patch     regenerate armbian/patch/.../kiwibox-0001-add-dts.patch
#   make deploy    install DTB + boot.scr on an Armbian OneCloud SD card
#
# Override as needed:
#   make dtb KERNEL_DIR=~/linux
#   make deploy BOOT=/Volumes/BOOT BOOTDEV="mmc 1"

KERNEL_DIR ?= $(CURDIR)/.dev/linux
BOOT       ?=
BOOTDEV    ?= mmc 0

.PHONY: all prepare dtb patch deploy clean

all: dtb

prepare:
	KERNEL_DIR="$(KERNEL_DIR)" ./scripts/prepare-kernel-tree.sh

dtb:
	KERNEL_DIR="$(KERNEL_DIR)" ./scripts/build-dtb.sh

patch: prepare
	KERNEL_DIR="$(KERNEL_DIR)" ./scripts/make-armbian-patch.sh

deploy: dtb
	@test -n "$(BOOT)" || { \
		echo 'usage: make deploy BOOT=/Volumes/BOOT [BOOTDEV="mmc 0"]'; \
		exit 1; \
	}
	./scripts/deploy.sh "$(BOOT)" "$(BOOTDEV)"

clean:
	rm -rf out
