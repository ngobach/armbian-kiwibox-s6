# Kiwibox S6 — Armbian bring-up (Amlogic S805 / Meson8b)

Board support for the Kiwibox S6, an S805 (Meson8b) Android TV box that is
internally an Amlogic **M201** reference design. Everything here targets the
`meson8b` Armbian family (`ARCH=armhf`, vendor u-boot, `uImage` + `boot.scr`),
i.e. the same stack the OneCloud build uses — with a device tree that matches
this box instead of the OneCloud's.

## Where this comes from

Reconstructed from the vendor firmware in `.dev/FW/` (`m201-ota-20150701.zip`,
Android 4.4.2), whose boot image carries the DTBs `m8b_m201_1G` and
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
| WiFi | Ampak AP6181 (BCM43362) on SDIO slot 0, IRQ GPIOX_21 | verified (DTS wired; SD+WiFi needs kiwibox-0003) |
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
├── firmware/
│   └── brcmfmac43362-sdio.txt    AP6181 NVRAM from the vendor image
├── armbian/                      mirrors the armbian/build tree, copy-in ready
│   ├── config/boards/kiwibox-s6.csc
│   ├── config/bootenv/kiwibox-s6.txt
│   ├── config/bootscripts/boot-kiwibox-s6.cmd   (installed as s805_autoscript)
│   └── patch/kernel/archive/meson-6.12/
│       ├── kiwibox-0001-add-dts.patch                  (generated)
│       ├── kiwibox-0002-meson8b-sdio-port0-pins.patch  SDIO port 0 + 32 kHz pins
│       └── kiwibox-0003-meson-mx-sdio-multi-slot.patch SD card + WiFi together
└── scripts/
    ├── prepare-kernel-tree.sh    sparse kernel clone + Armbian meson8b DTS patches
    ├── build-dtb.sh              clang -E + dtc -> out/*.dtb (~50 ms)
    ├── make-armbian-patch.sh     regenerate the kernel patch from dts/
    └── deploy.sh                 install DTB + boot script on a test SD card
```

Only `out/` (build output) and `.dev/` (scratch kernel tree, patch cache, vendor
firmware in `.dev/FW/`) are ignored.

## Quick start

```sh
brew install dtc u-boot-tools   # once

make prepare                    # ~50 MB sparse clone into .dev/linux, then patches it
make dtb                        # out/meson8b-kiwibox-s6.dtb
make deploy BOOT=/Volumes/BOOT  # FAT boot partition of an Armbian onecloud SD card
```

The scripts can also be called directly; `KERNEL_DIR`, `KVER`, `PATCH_REFRESH`,
`BOOT` and `BOOTDEV` are overridable (`make deploy BOOT=/Volumes/BOOT
BOOTDEV="mmc 1"`, or leave `BOOTDEV` empty to auto-detect the boot device).

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
7. **WiFi** — last; needs `kiwibox-0003` in the kernel and the board NVRAM,
   see below.

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
| `armbian/patch/kernel/archive/meson-6.12/kiwibox-0002-meson8b-sdio-port0-pins.patch` | `patch/kernel/archive/meson-6.12/` |
| `armbian/patch/kernel/archive/meson-6.12/kiwibox-0003-meson-mx-sdio-multi-slot.patch` | `patch/kernel/archive/meson-6.12/` |
| `armbian/userpatches/customize-image-host.sh` | `userpatches/` |

The DTS patch (`kiwibox-0001`) is **generated** from
`dts/meson8b-kiwibox-s6.dts` by `make patch` (it also adds the
`meson8b-kiwibox-s6.dtb` Makefile entry). Edit the DTS, run `make patch`, and
that patch is up to date again. `kiwibox-0002` (pinctrl labels) and
`kiwibox-0003` (driver) are hand-maintained.

The board NVRAM is deliberately *not* duplicated inside `armbian/`. The image
build picks it up from `userpatches/kiwibox-firmware/`, so upload it once:

```sh
rsync -a firmware/ /path/to/armbian/build/userpatches/kiwibox-firmware/
```

`userpatches/customize-image-host.sh` installs it into
`/usr/lib/firmware/brcm/` of the image (it is a no-op for other boards; the
log warns when the file is missing).

Then, on a Linux host (Debian/Ubuntu, no Docker needed):

```sh
# kernel + DTB + headers packages only
./compile.sh kernel BOARD=kiwibox-s6 BRANCH=current PREFER_DOCKER=no

# full image - note the command is `build`; there is no `image` artifact
./compile.sh build BOARD=kiwibox-s6 BRANCH=current RELEASE=trixie \
    BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no PREFER_DOCKER=no
```

Without `RELEASE`, `BUILD_MINIMAL` or `KERNEL_CONFIGURE`, Armbian opens a
`dialog` menu and aborts with "stdin is not a terminal". The image lands in
`output/images/Armbian-unofficial_*_Kiwibox-s6_trixie_current_*.img` and
contains the multi-slot kernel, the DTB, `s805_autoscript` and the NVRAM, with
`BOARD=kiwibox-s6` in `/etc/armbian-release`.

If ethernet needs an IC+ PHY driver, add `CONFIG_ICPLUS_PHY=y` to
`config/kernel/linux-meson-current.config` (it is not enabled today).

## WiFi (AP6181 / BCM43362)

The WiFi chip is on SDIO port 0 of the same `meson-mx-sdio` controller as the
SD card (port 1). The mainline driver registers only the first `mmc-slot`
child, so the DTS lists the SD card first: a stock kernel boots from the card
and simply omits WiFi. To have **SD + eMMC + WiFi at the same time**, build a
kernel with `kiwibox-0002` and `kiwibox-0003` (the Armbian patches installed
above), which registers a host for each slot and serializes access to the
shared command engine.

1. Boot a stock OneCloud image with this DTB and install to eMMC, or build and
   install the patched kernel first:
   `./compile.sh kernel BOARD=kiwibox-s6 BRANCH=current`, then install the
   `linux-image-current-meson` package from `output/debs/`.
2. Install the board NVRAM (the rootfs is ext4, so do this on the box):
   `sudo cp firmware/brcmfmac43362-sdio.txt /lib/firmware/brcm/`
3. Reboot and check `dmesg | grep -i brcmfmac` and `ip -br link` (`wlan0`).
4. Join a network with `nmtui` or `armbian-config`.

Debug: `dmesg | grep -i mmc` should list the SD card (`mmc0`), the eMMC
(`mmc1`) and one `mmc` host for the SDIO slot. The 32 kHz output is muxed on
`GPIOX_10`, power comes from `GPIOAO_6` + `GPIOX_11`, and the out-of-band IRQ
is `GPIOX_21` (gpio_intc hwirq 17).

## Caveats / TODO

- **Ethernet PHY is a guess.** The vendor DTB only says `amlogic,meson-eth`.
  The DTS assumes the M201-class meson8b-mxq wiring (RMII, PHY at MDIO 0,
  reset `GPIOH_4`, IRQ `GPIOH_3`). If there is no link: try another MDIO
  address, drop the reset/interrupt lines, and check the PHY markings.
- **VCCK mapping is unverified.** The vendor `cs_voltage_table` maps
  duty 28/32 → 860 mV and duty 0 → 1140 mV; the DTS uses `pwm-dutycycle-range
  = <100 0>`, which extrapolates past the vendor's 87.5 % endpoint. Prefer
  `<88 0>` until VCCK has been measured against CPU frequency under load.
- **This box has no eMMC.** The factory u-boot boots from NAND and reports
  `detect NAND device: A serials NAND 8GiB SDTNQGAMA-008G`; mainline has no
  meson8b NAND driver, and `meson-mx-sdhc` finds nothing to enumerate, so
  `mmc1`/`sdhc` stays unused and logs "Failed to initialize a non-removable
  card" after a few retries. SD is the only supported boot medium. The
  `emmc_pwrseq` node and `&sdhc` enablement are kept until a second unit is
  checked.
- **There is no power button.** The vendor firmware declares an Amlogic
  `gpio_keypad` on `GPIOAO_3`, but nothing is wired to it on this box. Exposing
  it as `gpio-keys-polled` makes the key read as permanently pressed, and
  `systemd-logind` then powers the box off ~35 s after boot (seen on hardware:
  clean shutdown, no panic). Keep the node out of the DTS.
- **Partition offset is untested on this loader.** The image uses Armbian's
  default `OFFSET=4` (MiB), the same as the MXQ board it is modelled on;
  `onecloud.csc` pins `OFFSET="16"` instead. If the factory u-boot cannot find
  the FAT partition, set `OFFSET="16"` in `kiwibox-s6.csc` and rebuild.
- **WiFi multi-slot support is experimental.** `meson-mx-sdio` shares one
  command engine and the CONF register between ports. `kiwibox-0003`
  registers one host per enabled slot and serializes requests, re-applying
  the per-slot bus width and clock at every request. Upstream nevertheless
  considers multi-slot support broken by design without MMC core changes, so
  this patch is out-of-tree and needs hardware validation. Without it, a
  stock kernel registers only the first slot (the SD card). brcmfmac itself
  supports BCM43362 and the board NVRAM is shipped in `firmware/`.

  If the patched driver misbehaves, set `status = "disabled"` on `slot@0` in
  the DTS (SD card only) or boot a stock kernel; the DT ordering keeps the
  card working there.
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
