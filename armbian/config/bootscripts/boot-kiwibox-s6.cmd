# Kiwibox S6 (Amlogic S805 / Meson8b) - Armbian boot script
#
# Modeled on Armbian's aml-s805-mxq.tvb board: the factory 2015 Amlogic
# u-boot searches the boot medium for a script named "s805_autoscript"
# (BOOTSCRIPT_OUTPUT in the board config), so a compiled copy of this file
# is installed under that name.
#
# bootdev is auto-detected. Set it to skip probing, e.g. for eMMC:
#   setenv bootdev "mmc 1"
#
# Note the "test -n ..; test $? != 0" idiom: "test -z" is broken on the old
# Amlogic 2015 u-boot (see Armbian's boot-onecloud.cmd for the same remark).

setenv rootdev "LABEL=armbi_root"
setenv rootfstype "ext4"

# console: both | display | serial
setenv console "both"
# loglevel. 1 (Armbian's default) hides everything below KERN_EMERG and
# 7 prints every kernel message - useful while bringing a board up, far too
# noisy for daily use. 4 keeps errors (which is where "no support for card's
# volts", mmc timeouts and firmware failures land) and drops the rest.
# armbianEnv.txt can override this without touching the card:
#   echo 'verbosity=1' >> /boot/armbianEnv.txt
setenv verbosity "4"

# USB autosuspend is broken with 6.x kernels on these boxes
setenv usb_autosuspend "0"

# Find the boot device in the same order the factory u-boot does when it
# searches for s805_autoscript, so the same medium ends up being used.
if test -n "${bootdev}"; test $? != 0; then if fatload usb 0 11000000 s805_autoscript; then env set bootdev "usb 0"; fi; fi;
if test -n "${bootdev}"; test $? != 0; then if fatload usb 1 11000000 s805_autoscript; then env set bootdev "usb 1"; fi; fi;
if test -n "${bootdev}"; test $? != 0; then if fatload usb 2 11000000 s805_autoscript; then env set bootdev "usb 2"; fi; fi;
if test -n "${bootdev}"; test $? != 0; then if fatload usb 3 11000000 s805_autoscript; then env set bootdev "usb 3"; fi; fi;
if test -n "${bootdev}"; test $? != 0; then if fatload mmc 0 11000000 s805_autoscript; then env set bootdev "mmc 0"; fi; fi;

if test -n "${bootdev}"; test $? != 0; then
	echo 'Could not find the boot device (no s805_autoscript on usb/mmc 0)'
	echo 'Set it manually, e.g.: setenv bootdev "mmc 0"'
	exit 22
fi

echo "Kiwibox S6: booting from ${bootdev}"
fatload ${bootdev} 0x20800000 /armbianEnv.txt && env import -t 0x20800000 ${filesize}

# Fallback if armbianEnv.txt does not provide it (see config/bootenv/).
if test -n "${dtb_file}"; test $? != 0; then setenv dtb_file "/dtb/meson8b-kiwibox-s6.dtb"; fi

if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyAML0,115200n8 ${consoleargs}"; fi
setenv consoleargs "${consoleargs} no_console_suspend consoleblank=0"
if test "${usb_autosuspend}" = "0"; then setenv extraargs "usbcore.autosuspend=-1"; fi

setenv bootargs "root=${rootdev} rootwait rw ${consoleargs} rootfstype=${rootfstype} loglevel=${verbosity} ${extraargs}"

fatload "${bootdev}" 0x20800000 /uImage
fatload "${bootdev}" 0x22000000 /uInitrd
fatload "${bootdev}" 0x21800000 "${dtb_file}"

bootm 0x20800000 0x22000000 0x21800000
