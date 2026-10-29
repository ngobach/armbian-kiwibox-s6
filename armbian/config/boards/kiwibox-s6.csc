# Amlogic S805 (Meson8b) Android TV box, M201 reference design
#
# No u-boot is built (BOOTCONFIG="none"): the vendor 2015 Amlogic bootloader
# already in eMMC/SD boots uImage + boot.scr, same as the OneCloud board.
BOARD_NAME="Kiwibox S6"
BOARD_VENDOR="amlogic"
BOARDFAMILY="meson8b"
BOARD_MAINTAINER="bachnx"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOTCONFIG="none"
BOOTSCRIPT="boot-kiwibox-s6.cmd:boot.cmd"
BOOTENV_FILE="kiwibox-s6.txt"
OFFSET="16"
BOOTSIZE="512"
BOOTFS_TYPE="fat"
