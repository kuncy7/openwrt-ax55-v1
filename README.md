# OpenWrt test builds — TP-Link Archer AX55 v1 (IPQ5018)

Unofficial test builds for adding OpenWrt support to the TP-Link Archer AX55 v1.

**Forum thread:** https://forum.openwrt.org/t/add-support-for-tp-link-ax55-v1/158384/

> ⚠️ These are **RAM-only test images** (initramfs). They are booted over the
> network from U-Boot and **never write anything to flash**. Returning to the
> stock TP-Link firmware is simply a matter of power-cycling the router — see
> [Reverting to stock firmware](#reverting-to-stock-firmware).

## Hardware

| Component | Details |
|-----------|---------|
| SoC | Qualcomm IPQ5018 |
| RAM | 512 MB DDR3 (ESMT) |
| Flash | 128 MB SPI-NAND (ESMT F50L1G41LB) |
| Switch (LAN) | Realtek RTL8367S (external, 4×1G LAN) |
| WiFi 2.4 GHz | Integrated in IPQ5018 |
| WiFi 5 GHz | Qualcomm QCN6102 |
| WAN | 1G via IPQ5018 internal GE PHY |

## Status

| Stage | Status | Notes |
|-------|--------|-------|
| UART (serial console) | ✅ Fixed | RX resistor R102/R216 area, JP1 header (ToRX/ToTX/GND/3.3V) |
| Kernel boots | ✅ | IPQ5018, SPI-NAND, UBI |
| **WiFi** | 🧪 stage 3d — **in this build** | Both radios enabled as an AP for testing; needs HW confirmation |
| **WAN** | ⏳ stage 3b | |
| **LAN (RTL8367S DSA)** | ⏳ stage 3c | Requires HSGMII patch for rtl8365mb driver |
| Factory/sysupgrade image | ⏳ stage 3e | Do **not** flash the `.ubi`/`.bin` files yet |

## WiFi test defaults (stage 3d build)

To make the board reachable without staying tethered to the serial cable, this
build comes up with WiFi enabled:

| | |
|---|---|
| SSID | `OpenWrt-AX55` |
| Password (WPA2) | `ax55test` |
| Router IP | `192.168.1.3` |
| SSH | `ssh root@192.168.1.3` (no password) |

Connect a laptop/phone to the `OpenWrt-AX55` network, then SSH to
`192.168.1.3`. (Ethernet is not wired up yet — that is stages 3b/3c.)

## Requirements for booting the test image

- **Serial console with working RX** — you must restore the series resistor near
  R102/R216 (see forum post for photos). Without RX you cannot interact with
  U-Boot to start the network boot.
- A TFTP server on your LAN.
- 3.3V USB-to-serial adapter.

> After the first boot you only need the serial cable to *start* the image.
> Everything else (logs, config, debugging) can be done over WiFi via SSH.

## How to boot the initramfs test image

1. Connect serial (115200 8N1) to the JP1 header (ToRX=pin1, ToTX=pin2, GND=pin3).
2. Power on the router and interrupt U-Boot (press any key).
3. Boot over TFTP:
   ```
   setenv ipaddr 192.168.1.1
   setenv serverip 192.168.1.254
   tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-tplink_archer-ax55-v1-initramfs-uImage.itb
   bootm 0x44000000
   ```
4. OpenWrt boots from RAM. **Nothing is written to flash.**

## Reverting to stock firmware

Because these are RAM-only images, the stock firmware on flash is left
completely untouched:

- **Just power-cycle the router.** It boots back into the original TP-Link
  firmware as if nothing happened.

There is no flashing, no partition change and no risk to the stock firmware in
this stage. (A permanent, flashable image with a proper sysupgrade/revert path
is planned for stage 3e.)

## Useful things to check / report

- Full boot log over serial.
- WiFi: does `OpenWrt-AX55` appear and can you associate + SSH to `192.168.1.3`?
- `dmesg | grep -iE 'ath11k|qcn|q6'` — WiFi firmware/calibration load.
- `iw dev` and `wifi status` — radio/AP state.
- `cat /proc/mtd` — are all 16 MTD partitions visible?
- `dmesg | grep -iE 'nand|rtl'` — NAND and RTL8367S messages.

## Key patches

- `rtl8365mb`: adds SGMII/HSGMII (2.5G) external-port support — required because
  the RTL8367S is connected to the IPQ5018 over a 2.5G HSGMII backhaul. This
  re-derives [Hauke Mehrtens' 2022 series](https://lore.kernel.org/netdev/YnkBSTbn04SYyV+J@lunn.ch/T/)
  (never merged upstream due to firmware licensing — not an issue in OpenWrt as
  the blob is already in-tree under GPL-2.0).
- `rtl8367s-sgmii-firmware` package: ships
  `/lib/firmware/rtl_switch/rtl8367s-sgmii.bin` (8051 SerDes init firmware,
  GPL-2.0, extracted from the in-tree mediatek vendor driver).
