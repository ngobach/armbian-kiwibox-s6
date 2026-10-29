# Kiwibox S6 — Armbian bring-up (Amlogic S805 / Meson8b)

Board support for the Kiwibox S6, an S805 (Meson8b) Android TV box that is
internally an Amlogic **M201** reference design. Everything here targets the
`meson8b` Armbian family (`ARCH=armhf`, vendor u-boot, `uImage` + `boot.scr`),
i.e. the same stack the OneCloud build uses — with a device tree that matches
this box instead of the OneCloud's.

## Where this comes from

Reconstructed from the vendor firmware `.dev/images/FW_S6_0701.rar` (Android 4.4.2,
`m201-ota-20150701.zip`), whose boot image carries the DTBs `m8b_m201_1G` and
`m8b_m201C_512M`. The device tree leans on the upstream `meson8b-mxq.dts` /
`meson8b-odroidc1.dts` references, and the boot flow (auto-probed `bootdev`,
`s805_autoscript`, `dtb_file`, `LABEL=armbi_root`) follows Armbian's
`aml-s805-mxq.tvb` board rather than the OneCloud one — see the notes on
reference boards at the end.

| Subsystem | Detail | Confidence |
| --- | --- | --- |
| SoC | Amlogic 8726-M8B (S805), 4× Cortex-A5 | verified |
| RAM | 1 GiB (`linux,total-memory = <0x3fe00000>` in vendor DTB) | verified |
| eMMC | SDHC controller, 8-bit; reset line on BOOT_9 assumed | medium |
| SD card | SDIO controller slot 1, card detect GPIO `CARD_6` | verified |
| Ethernet | internal MAC, 100 Mbit RMII; PHY model unknown | low |
| WiFi | Ampak AP6181 (BCM43362) on SDIO slot 0, IRQ GPIOX_21 | verified (unwired) |
| Bluetooth | Broadcom, reset GPIOX_20 | verified (unwired) |
| IR | internal IR decoder, NEC `factory_code 0xfe010001` | verified |
| Power key | GPIOAO_3, key code 0x74 (KEY_POWER) | verified |
| CPU rail | VCCK on PWM_C (GPIODV_9), 860–1140 mV, inverted duty | medium |
| Display | HDMI only (`ro.platform.has.cvbsmode=false`) | verified |
| I²C peripherals | none populated in the vendor DTB | verified |

## Layout

```
.
├── Makefile                      convenience targets (prepare/dtb/patch/deploy)
├── dts/
│   └── meson8b-kiwibox-s6.dts    board device tree (source of truth)
├── armbian/                      mirrors the armbian/build tree, copy-in ready
│   ├── config/boards/kiwibox-s6.csc
│   ├── config/bootenv/kiwibox-s6.txt
│   ├── config/bootscripts/boot-kiwibox-s6.cmd   (installed as s805_autoscript)
│   └── patch/kernel/archive/meson-6.12/kiwibox-0001-add-dts.patch  (generated)
└── scripts/
    ├── prepare-kernel-tree.sh    sparse kernel clone + Armbian meson8b DTS patches
    ├── build-dtb.sh              clang -E + dtc -> out/*.dtb (~50 ms)
    ├── make-armbian-patch.sh     regenerate the kernel patch from dts/
    └── deploy.sh                 install DTB + boot script on a test SD card
```

Only `out/` (build output) and `.dev/` (scratch kernel tree, patch cache, vendor
firmware in `.dev/images/`) are ignored.

## Quick start

```sh
brew install dtc u-boot-tools   # once

make prepare                    # ~50 MB sparse clone into .dev/linux, then patches it
make dtb                        # out/meson8b-kiwibox-s6.dtb
make deploy BOOT=/Volumes/BOOT  # FAT boot partition of an Armbian onecloud SD card
```

The scripts can also be called directly; `KERNEL_DIR`, `BOOT` and `BOOTDEV` are
overridable (`make deploy BOOT=/Volumes/BOOT BOOTDEV="mmc 1"`, or leave
`BOOTDEV` empty to auto-detect the boot device).

Then just reboot. The factory S805 u-boot searches the boot medium for a
script called `s805_autoscript` (that is what `BOOTSCRIPT_OUTPUT` in
`armbian/config/boards/kiwibox-s6.csc` is for), and the script probes
`usb 0..3` then `mmc 0` for itself, exactly like Armbian's MXQ board. If your
loader does not pick it up, boot by hand at the u-boot prompt (115200 8N1):

```
setenv bootdev "mmc 0"          # mmc 0 = SD card, mmc 1 = eMMC, usb 0 = USB
fatload ${bootdev} 0x20800000 boot.scr && autoscr 0x20800000
```

Older u-boot builds use `source` instead of `autoscr`. Without a boot script:

```
fatload mmc 0 0x20800000 uImage
fatload mmc 0 0x22000000 uInitrd
fatload mmc 0 0x21800000 dtb/meson8b-kiwibox-s6.dtb
setenv bootargs root=LABEL=armbi_root rootwait rw console=ttyAML0,115200n8
bootm 0x20800000 0x22000000 0x21800000
```

No Armbian build is required for this loop: the DTB is a standalone file that
`bootm` takes as its third argument, so you can iterate on the device tree
without rebuilding the kernel or the image.

## Bring-up order

1. **Serial** — `ttyAML0`. If you see `Kiwibox S6` in `/proc/device-tree/model`,
   the DTB was picked up.
2. **SD card** — `dmesg | grep -i mmc`, expect `mmc0` (vendor port 1).
3. **eMMC** — expect `mmc1` (`sdhc`). If it fails: remove `mmc-pwrseq` /
   `emmc_pwrseq` from the DTS (`BOOT_9` may not be wired as RSTn).
4. **Ethernet** — see caveats below; check `dmesg | grep -i phy` and
   `ip -br link`.
5. **USB / IR / power key** — `evtest` for the remote and KEY_POWER.
6. **HDMI** — needs the Armbian meson8b DRM/VPU patch series (already assumed
   by the DTS); `modetest`/`drm_info` to confirm.
7. **WiFi** — last; needs pinctrl work, see below.

## Folding into `armbian/build`

`armbian/` mirrors the upstream tree, so integration is a copy:

```sh
rsync -a armbian/ /path/to/armbian/build/
```

That installs:

| Source | Destination in `armbian/build` |
| --- | --- |
| `armbian/config/boards/kiwibox-s6.csc` | `config/boards/` |
| `armbian/config/bootenv/kiwibox-s6.txt` | `config/bootenv/` |
| `armbian/config/bootscripts/boot-kiwibox-s6.cmd` | `config/bootscripts/` |
| `armbian/patch/kernel/archive/meson-6.12/kiwibox-0001-add-dts.patch` | `patch/kernel/archive/meson-6.12/` |

The kernel patch is **generated** from `dts/meson8b-kiwibox-s6.dts` by
`make patch` (it also adds the `meson8b-kiwibox-s6.dtb` Makefile entry). Edit
the DTS, run `make patch`, and the patch is up to date again.

Then, on a Linux host or CI:

```sh
./compile.sh BOARD=kiwibox-s6 BRANCH=current          # full image
./compile.sh kernel BOARD=kiwibox-s6 BRANCH=current   # kernel + DTB packages only
```

If ethernet needs an IC+ PHY driver, add `CONFIG_ICPLUS_PHY=y` to
`config/kernel/linux-meson-current.config` (it is not enabled today).

## Caveats / TODO

- **Ethernet PHY is a guess.** The vendor DTB only says `amlogic,meson-eth`.
  The DTS assumes the M201-class meson8b-mxq wiring (RMII, PHY at MDIO 0,
  reset `GPIOH_4`, IRQ `GPIOH_3`). If there is no link: try another MDIO
  address, drop the reset/interrupt lines, and check the PHY markings.
- **VCCK mapping is unverified.** The vendor `cs_voltage_table` maps
  duty 28/32 → 860 mV and duty 0 → 1140 mV; the DTS uses `pwm-dutycycle-range
  = <100 0>`. Measure VCCK vs. CPU frequency before trusting it under load.
- **eMMC reset (BOOT_9)** is assumed; see step 3 above.
- **WiFi needs driver work, not just DTS.** Two blockers in v6.12: (1)
  `pinctrl-meson8b.c` has no group for the SDIO port 0 pins (`GPIOX_0..9`),
  and (2) `meson-mx-sdio.c` registers only the *first* `mmc-slot` child, so
  enabling slot@0 would displace the SD card in slot@1. The controller side
  is fine though: brcmfmac supports BCM43362, `brcmfmac43362-sdio.bin` is in
  linux-firmware, and the board NVRAM is in the vendor image at
  `system/etc/wifi/40181/nvram.txt` (use it as `brcmfmac43362-sdio.txt`).
- **IR keymap**: the vendor remote is NEC `0xfe010001`; the mainline
  `meson-ir` + `rc-core` path needs an `ir-keytable` keymap — the vendor
  `system/etc/remote.conf` in the firmware archive has the scancode map.
- **4K** HDMI modes may need a bigger CMA pool than the default 64 MiB;
  Armbian's `linux,cma` patch only covers meson8, not meson8b.

## Reference boards

Three meson8b sources in `armbian/build` matter here, and they play different
roles:

| Source | What it is used for |
| --- | --- |
| `config/boards/aml-s805-mxq.tvb` | **Primary reference for boot plumbing.** Same factory-u-boot situation as this box: `BOOTSCRIPT_OUTPUT="s805_autoscript"`, `bootdev` auto-probed over `usb 0..3` then `mmc 0`, `dtb_file` supplied by the bootenv, root by `LABEL=armbi_root`, `usbcore.autosuspend=-1`. |
| `config/boards/onecloud.csc` | DTS patterns the MXQ tree does not have: 8-bit eMMC with `mmc-pwrseq-emmc`, IR receiver, gpio-keys, LEDs, USB role switching. |
| upstream `meson8b-mxq.dts` | Hardware baseline: 1 GiB memory map, SD slot, RMII ethernet with an IP101-class PHY, USB, PWM VCCK/VDDEE regulators, SARADC. |

In short: MXQ is the closer sibling (S805 TV box, M201-class, same vendor
loader conventions) and is the better boot-flow template; the OneCloud tree
is still the better source for eMMC/IR/key/DTB details. This port takes the
boot flow from MXQ and keeps the OneCloud-style device-tree pieces.
