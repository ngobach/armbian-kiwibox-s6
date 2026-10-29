# Amlogic S805 (Meson8b) Android TV box, M201 reference design
#
# No u-boot is built (BOOTCONFIG="none"): the factory 2015 Amlogic
# bootloader already in eMMC/SD boots the kernel, same as the OneCloud and
# MXQ boards. BOOTSCRIPT_OUTPUT is the name that loader searches for.
BOARD_NAME="Kiwibox S6"
BOARD_VENDOR="amlogic"
BOARDFAMILY="meson8b"
BOARD_MAINTAINER="bachnx"
INTRODUCED="2015"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOTCONFIG="none"
BOOTSCRIPT="boot-kiwibox-s6.cmd:boot.cmd"
BOOTSCRIPT_OUTPUT="s805_autoscript"
BOOTENV_FILE="kiwibox-s6.txt"
BOOTSIZE="512"
BOOTFS_TYPE="fat"
