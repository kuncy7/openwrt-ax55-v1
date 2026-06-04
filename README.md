# OpenWrt test builds — TP-Link Archer AX55 v1 (IPQ5018)

Unofficial test builds for adding OpenWrt support to the TP-Link Archer AX55 v1.

**Forum thread:** https://forum.openwrt.org/t/add-support-for-tp-link-ax55-v1/158384/

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
| **WAN** | ⏳ stage 3b | |
| **LAN (RTL8367S DSA)** | ⏳ stage 3c | Requires HSGMII patch for rtl8365mb driver |
| **WiFi** | ⏳ stage 3d | |
| Factory/sysupgrade image | ⏳ stage 3e | |

## Key patches

- `rtl8365mb`: adds SGMII/HSGMII (2.5G) external-port support — required because the RTL8367S is connected to the IPQ5018 over a 2.5G HSGMII backhaul. This re-derives [Hauke Mehrtens' 2022 series](https://lore.kernel.org/netdev/YnkBSTbn04SYyV+J@lunn.ch/T/) (never merged upstream due to firmware licensing — not an issue in OpenWrt as the blob is already in-tree under GPL-2.0).
- `rtl8367s-sgmii-firmware` package: ships `/lib/firmware/rtl_switch/rtl8367s-sgmii.bin` (8051 SerDes init firmware, GPL-2.0, extracted from the in-tree mediatek vendor driver).

## Requirements for testing

- **Serial console with working RX** — you must restore the series resistor near R102/R216 (see forum post for photos). Without RX you cannot interact with U-Boot.
- A TFTP server on your LAN.
- 3.3V USB-to-serial adapter.

## How to boot the initramfs test image

1. Connect serial (115200 8N1) to JP1 header (ToRX=pin1, ToTX=pin2, GND=pin3).
2. Power on the router and interrupt U-Boot (press any key).
3. Set up TFTP:
   ```
   setenv ipaddr 192.168.1.1
   setenv serverip 192.168.1.254
   tftpboot 0x44000000 openwrt-qualcommax-ipq50xx-tplink_archer-ax55-v1-initramfs-uImage.itb
   bootm 0x44000000
   ```
4. OpenWrt should boot from RAM. Nothing is written to flash.

## Useful things to check / report

- Does the kernel boot cleanly? Paste the full boot log.
- `cat /proc/mtd` — are all 16 MTD partitions visible?
- Does `ip link` show `br-lan`, `eth0`, `eth1`? (stage 3b/3c not done yet — expected missing)
- `dmesg | grep -i rtl` — RTL8367S detection messages.
- `dmesg | grep -i nand` — NAND detection messages.
