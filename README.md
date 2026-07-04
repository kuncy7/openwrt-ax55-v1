# OpenWrt for TP-Link Archer AX55 v1 (IPQ5018)

Work-in-progress OpenWrt port for the **TP-Link Archer AX55 v1** (Qualcomm IPQ5018),
built on a **mainline DWMAC + DSA** ethernet base (kernel **6.12.92**) — no QSDK/NSS.

Forum thread: https://forum.openwrt.org/t/add-support-for-tp-link-ax55-v1/158384

## Hardware
- SoC: Qualcomm **IPQ5018** (Cortex-A53, 64-bit)
- RAM: 512 MB (ESMT DDR3L) · Flash: 128 MB SPI-NAND (ESMT F50L1G41LB)
- LAN switch: **Realtek RTL8367S** (external, on MDIO) — OEM DTS mislabels it "qca83xx"
- WiFi: 2.4 GHz integrated IPQ5018 + 5 GHz **QCN6102** (ath11k)
- 4×LAN + 1×WAN (all 1 GbE) · 1×USB 3.0

## Ethernet topology
- **WAN** = IPQ5018 internal GE PHY @ mdio0:7 → `gmac0` (SGMII)
- **LAN** = `gmac1` → UNIPHY0 PCS → **2.5G HSGMII trunk** → RTL8367S → 4×LAN front ports
- The RTL8367S trunk needs the `rtl8365mb` **SGMII/HSGMII** datapath, which mainline
  lacks. This repo carries a rebased version of Hauke Mehrtens' 2022 patch
  (`src/0918-*.patch`) plus the 8051 SerDes firmware (`rtl8367s-sgmii-firmware`).

## Status (2026-07-04)
| Area | State |
|---|---|
| Builds (initramfs + factory.ubi + sysupgrade) | ✅ clean on 6.12.92 |
| `rtl8365mb` HSGMII patch 0918 | ✅ applies + compiles in-tree |
| No-serial install to NAND (`mtd write`) | ✅ works (see below) |
| Boots the FIT (U-Boot loads slot, no fallback) | ✅ (indirect) |
| Reaches userspace / network | ❓ **unconfirmed — no serial console** |
| RTL8367S LAN trunk passes traffic | ❌ open problem (SerDes/MDIO) |

**We flashed the image via the no-serial path and the router did NOT come up on
WiFi, WAN or LAN.** U-Boot did *not* fall back to stock (192.168.0.1 stays dead),
so the FIT loaded but the kernel either panics early or boots with no usable
interface. **Without a serial console we cannot see why.** Boot-log help wanted —
see the forum thread and `FINDINGS.md`.

## Build
```sh
# base branch: Julius's pcs-uniphy-psgmii-25m (kernel 6.12.92, IPQ5018 DWMAC/UNIPHY)
git apply src/ax55-dwmac-support.patch          # or cherry-pick the individual files
./scripts/feeds update -a && ./scripts/feeds install -a
make menuconfig    # Target: qualcommax / ipq50xx / TP-Link Archer AX55 v1
# IMPORTANT: the DEVICE_PACKAGES kmods are NOT auto-selected by defconfig — enable them:
#   CONFIG_PACKAGE_kmod-dsa-realtek=y
#   CONFIG_PACKAGE_kmod-dsa-rtl8365mb=y
#   CONFIG_PACKAGE_rtl8367s-sgmii-firmware=y
make -j$(nproc)
```
Artifacts (attached to the GitHub Release):
`...-initramfs-uImage.itb`, `...-squashfs-factory.ubi`, `...-squashfs-sysupgrade.bin`.

## Install (NO serial required)
The stock userland is **32-bit ARMv7**. First get a **root shell**:
1. Repack an *older, unencrypted* stock firmware (2022/2024) with telnet enabled
   (the MD5-only "Proud" flag disables the RSA path) — see
   github.com/lmadarassy/tp-link-ax55-fw-hacks — and flash it via the **stock web UI
   Firmware Upgrade** page (the runtime upgrade checks MD5, not RSA).
2. `telnet 192.168.0.1` → root.

Then write OpenWrt into the **inactive** rootfs slot and switch the boot flag:
```sh
# transfer factory.ubi to /tmp (e.g. wget from a PC http server)
# stock boots from slot 1 (rootfs_1); write OpenWrt to slot 0 (rootfs = mtd11):
cat /proc/mtd | grep -E '"rootfs"|"rootfs_1"'      # confirm rootfs = mtd11
mtd erase /dev/mtd11
mtd write /tmp/factory.ubi /dev/mtd11
fw_setenv tp_boot_idx 0
fw_setenv config_name config@mp03.3
reboot
```
> **Do NOT use the stock `ubiformat`** — it throws `Arithmetic exception` (SIGFPE)
> on this old QSDK mtd-utils, even with `-s`. `mtd erase` + `mtd write` is the
> working method. Stock stays untouched in slot 1 as a fallback.

## Recovery / back to stock
- **U-Boot web recovery** (hold Reset at power-on → PC 192.168.0.10 →
  http://192.168.0.1 → upload firmware) is **RSA-signature gated** — it accepts
  **only genuine TP-Link signed** `.bin`, not OpenWrt and not the telnet-modified
  image. Use it with an official firmware to restore stock, then re-do the web-UI
  telnet trick if you need root again.
- There is **no boot-attempt counter**: U-Boot (`cmd_bootqca.c` / `do_bootipq`) only
  falls back to the other slot if the FIT fails to *load*. A kernel that loads then
  hangs will **not** auto-revert, and power-cycling will not switch slots.

See `FINDINGS.md` for the full MTD layout, U-Boot boot logic, and the open RTL8367S
SerDes/MDIO problem.

## Credits
DWMAC/UNIPHY IPQ5018 base by Julius Bairaktaris. HSGMII datapath from Hauke
Mehrtens' 2022 rtl8365mb series. No-serial root method from lmadarassy & Sunshainy
(forum 158384).
