# Kiwibox S6 (Amlogic S805 / Meson8b) - Armbian boot script
#
# Only "bootdev" is needed. It defaults to the SD card ("mmc 0"); set it in
# u-boot, or change the default line below ("mmc 1" = eMMC, "usb 0" = USB).
#
# Note the "test -n ..; test $? != 0" idiom: "test -z" is broken on the old
# Amlogic 2015 u-boot (same workaround as Armbian's boot-onecloud.cmd).

if test -n "${bootdev}"; test $? != 0; then
	setenv bootdev "mmc 0"
fi

echo "Kiwibox S6: booting from ${bootdev}"
fatload ${bootdev} 0x20800000 /armbianEnv.txt && env import -t 0x20800000 ${filesize}

if test -n "${rootdev}"; test $? != 0; then
	echo 'Please set "rootdev" in armbianEnv.txt'
	exit 22
fi

if test -n "${consoleargs}"; test $? != 0; then
	test -n "${console}" || setenv console "both"

	setenv consoleargs ""
	test "${console}" = "display" || test "${console}" = "both" && setenv consoleargs "${consoleargs} console=tty1"
	test "${console}" = "serial" || test "${console}" = "both" && setenv consoleargs "${consoleargs} console=ttyAML0,115200n8"
	setenv consoleargs "${consoleargs} no_console_suspend consoleblank=0"

	test -n "${bootlogo}" || setenv bootlogo "false"
	if test "${bootlogo}" = "true"; then
		setenv consoleargs "${consoleargs} splash plymouth.ignore-serial-consoles"
	else
		setenv consoleargs "${consoleargs} splash=verbose"
	fi
fi

setenv bootargs ""
setenv bootargs "${bootargs} root=${rootdev} rootwait rw"
setenv bootargs "${bootargs} ${consoleargs}"
setenv bootargs "${bootargs} ${extraargs}"

fatload ${bootdev} 0x20800000 /uImage || exit 1
fatload ${bootdev} 0x22000000 /uInitrd || exit 1
fatload ${bootdev} 0x21800000 /dtb/meson8b-kiwibox-s6.dtb || exit 1

bootm 0x20800000 0x22000000 0x21800000
