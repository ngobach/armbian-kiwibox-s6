# Board firmware

`brcmfmac43362-sdio.txt` is the AP6181 (BCM43362) NVRAM taken verbatim from
the vendor Android image (`system/etc/wifi/40181/nvram.txt` inside
`.dev/FW/m201-ota-20150701.zip`). It carries the board calibration values
(`boardtype=0x0598`, `xtalfreq=26000`) and is required for the module to
initialise; linux-firmware ships the matching `brcmfmac43362-sdio.bin` but no
NVRAM for this board.

Install it on the box (the rootfs is ext4, so it cannot be copied from macOS):

```sh
sudo cp brcmfmac43362-sdio.txt /lib/firmware/brcm/
sudo modprobe -r brcmfmac; sudo modprobe brcmfmac
```

See the main README for the experimental multi-slot kernel patch that lets the
SD card and WiFi be used at the same time.
