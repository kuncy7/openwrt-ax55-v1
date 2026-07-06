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

## Status (2026-07-06, v0.5)
| Area | State |
|---|---|
| Builds (initramfs + factory.ubi + sysupgrade) | ✅ clean on 6.12.92 |
| No-serial install to NAND (`mtd write`) | ✅ works (see below) |
| Boots to userspace | ✅ |
| WiFi 2.4 GHz + 5 GHz (ath11k, own BDFs) | ✅ AP works, clients get DHCP |
| **LAN: RTL8367S ↔ SoC trunk** | ✅ **2.5G HSGMII, from cold boot** |
| **WAN + NAT + internet** | ✅ **works — the blue jack is RTL8367S port 0** |
| All 5 jacks mapped + labeled correctly | ✅ (wan + lan1-4; GE PHY is not bonded out) |
| Factory MACs (label/wan/radios from tp_data) | ✅ |
| U-Boot env tools (fw_printenv/fw_setenv) | ✅ |

**This is a fully functional router now** — WAN DHCP + NAT + IPv6, 4×1G LAN,
WiFi 2.4+5 GHz, 2.5G internal trunk (faster than stock, which runs it at 1G).
The whole port was done **without ever soldering a serial console**.

**2026-07-06: the LAN datapath is solved.** Two `rtl8365mb` driver pieces were
missing, and **both are required** — each alone leaves a link-up trunk that
silently drops every frame in both directions:
1. **Disable SGMII in-band autoneg in the SerDes** (SDS reg `0x0002`: clear bit 9,
   set bit 8 = commit; vendor `rtl8367c_setSgmiiNway`, with the switch's 8051
   paused via `0x130C` bit 5 around the access).
2. **Force link/speed/duplex/pause in `SDS_MISC` (`0x1D11`) from `mac_link_up`**
   (vendor `setAsicPortForceLinkExt`, type-1 chips) — bit 9 of `SDS_MISC`
   directly gates the SerDes TX.

Debug notes that cost us days (see `FINDINGS.md`): never dump the full switch
regmap over MDIO (it wedges the MDIO slave until a power cycle), and the 8051
firmware polls the SDS status register through the same INDACS engine your
accesses use — pause it first.

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
