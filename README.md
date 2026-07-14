# OpenWrt for TP-Link Archer AX55 v1 (IPQ5018)

OpenWrt port for the **TP-Link Archer AX55 v1** (Qualcomm IPQ5018), on the
**mainline DWMAC + DSA** ethernet stack — no QSDK, no NSS, no SerDes firmware blob.

- Upstream PR: **https://github.com/openwrt/openwrt/pull/24197** (draft)
- Forum thread: https://forum.openwrt.org/t/add-support-for-tp-link-ax55-v1/158384

> ⚠️ **Board revision matters.** This targets **v1** with the **Realtek RTL8367S**
> switch. Some v1 units ship an **RTL8367D** instead — *not supported yet* (mainline
> `rtl8365mb` rejects it as "unrecognized switch"), so such a unit would boot with
> Ethernet down and Wi-Fi disabled by default. **v2 is a different SoC entirely.**
> Check your switch chip before flashing.

## Hardware
- SoC: Qualcomm **IPQ5018** (dual Cortex-A53, 64-bit)
- RAM: 512 MB · Flash: 128 MB SPI-NAND (dual firmware slots)
- LAN switch: **Realtek RTL8367S** (external, on MDIO; OEM DTS mislabels it)
- WiFi: 2.4 GHz integrated IPQ5018 + 5 GHz **QCN6122** (ath11k)
- 4×LAN + 1×WAN + 1×USB 3.0

## Ethernet topology
All **five** front jacks are RTL8367S ports — the SoC's internal GE PHY is *not*
bonded out, so `gmac0` is disabled:

```
IPQ5018 gmac1 (stmmac) → uniphy0 PCS → 2.5G HSGMII trunk → RTL8367S (DSA)
                                                            ├─ port0  = WAN  (blue jack)
                                                            └─ port1-4 = LAN1-4
```

The RTL8367S trunk needs SGMII/HSGMII support in the `rtl8365mb` DSA driver, which
mainline lacks. This is provided by **Johan Alvarado's netdev v6 series** (patches
`0001`/`0002`), which brings the SerDes up as a phylink PCS with the **DW8051 kept
in reset — no firmware blob**. Patch `0003` is Mieczysław Nalewaj's cold-start fix
(busy-wait on the SDS indirect-access engine). Once the netdev series lands, the PR
will switch to a backport of the merged patches.

## Status
| Area | State |
|---|---|
| Boot to userspace (kernel 6.12) | ✅ |
| WAN + NAT + IPv4/IPv6 | ✅ |
| 4×LAN (DSA) + labels | ✅ |
| 2.5G HSGMII trunk (warm boot / short power-cycle) | ✅ |
| WiFi 2.4 GHz + 5 GHz (ath11k, board-specific BDFs) | ✅ |
| Factory MACs (label/wan/radios from `tp_data`) | ✅ |
| USB 2.0 (HS) | ✅ |
| USB 3.0 (SuperSpeed) | ⚠️ PHY patch present; SS bring-up WIP |
| Software flow offload | ✅ (`kmod-nft-offload`) |
| **Cold boot after hours powered off** | ⚠️ **under investigation** — see below |

**This is a fully functional router**: ~275 Mb/s NAT over Wi-Fi, the 2.5G internal
trunk runs faster than stock (which caps it at 1G), and the whole port was done
without soldering a serial console.

### Known issue: cold-start trunk degradation
After the router has been **powered off for several hours**, the first boot may bring
the HSGMII trunk up (link reports 2.5Gbps/Full) but with the data path degraded —
heavy packet loss, no CRC/symbol errors, frames discarded inside the switch on the
port-6 egress path. A full re-probe (soft reboot) recovers it, sometimes on the
second try. Patch `0003` (busy-wait after SerDes indirect writes) is the current
candidate fix and is under testing. Warm reboots and short power-cycles are unaffected.
Diagnostics and discussion: forum thread *"reduce number of drivers for rtl8367s"*.

## Build
```sh
# Base: openwrt/openwrt main (kernel 6.12) — it already carries PR #22381
#       (UNIPHY-PCS + IPQ5018 DWMAC). No out-of-tree base patch is needed anymore.
git clone https://github.com/openwrt/openwrt.git && cd openwrt

# Drop in this device + the rtl8365mb SGMII/HSGMII datapath:
cp .../src/0001-*.patch .../src/0002-*.patch .../src/0003-*.patch \
   .../src/0004-*.patch .../src/0005-*.patch target/linux/qualcommax/patches-6.12/
# plus the device support (DTS, base-files, image recipe, ipq-wifi, BDFs) from PR #24197
#   https://github.com/openwrt/openwrt/pull/24197  (or git fetch the branch)

./scripts/feeds update -a && ./scripts/feeds install -a
make menuconfig    # Target: qualcommax / ipq50xx / TP-Link Archer AX55 v1
make -j$(nproc)
```
The simplest route is to fetch the PR branch directly and add patch `0003`; the PR
already contains the device commit, USB PHY patches and the ipq-wifi BDFs.

Artifacts: `...-initramfs-uImage.itb`, `...-squashfs-factory.ubi`,
`...-squashfs-sysupgrade.bin` (attached to the GitHub **Release**).

## Install (NO serial required)
Get a **root shell on stock** first:
1. Repack an *older, unencrypted* stock firmware with telnet enabled (the MD5-only
   flag disables the RSA path) — see github.com/lmadarassy/tp-link-ax55-fw-hacks —
   and flash it via the **stock web UI Firmware Upgrade** page (runtime upgrade checks
   MD5, not RSA). For a passwordless root telnet, the repack adds `telnetd -l /bin/sh &`
   to `/etc/rc.local` (bypasses `/bin/login` entirely).
2. `telnet 192.168.0.1` → root.

Then write OpenWrt into the **inactive** rootfs slot and switch the boot flag:
```sh
# transfer factory.ubi to /tmp (e.g. wget from a PC http server)
cat /proc/mtd | grep -E '"rootfs"|"rootfs_1"'     # note which slot you booted
cat /proc/cmdline | grep -o 'ubi.mtd=[^ ]*'       # e.g. rootfs_1 = slot 1
# write to the slot you did NOT boot (example: booted slot 1 → write slot 0 = rootfs):
mtd erase rootfs
mtd write /tmp/...-squashfs-factory.ubi rootfs
echo '/dev/mtd7 0x0 0x40000 0x00020000 0x2' > /etc/fw_env.config
fw_setenv tp_boot_idx 0
fw_printenv tp_boot_idx        # confirm it reads 0
reboot
```
> Use `mtd erase` + `mtd write`, **not** the stock `ubiformat` (SIGFPE on the old QSDK
> mtd-utils). Stock stays intact in the other slot as a fallback. Write the raw
> **`factory.ubi`** here — *not* the `sysupgrade.bin`, which is a different format.

Updating an already-OpenWrt unit is a normal `sysupgrade` (or LuCI):
```sh
sysupgrade -v /tmp/...-squashfs-sysupgrade.bin
```

## Recovery / back to stock
- **U-Boot web recovery** (hold Reset at power-on → PC 192.168.0.10 →
  http://192.168.0.1) is **RSA-signature gated** — it accepts only genuine TP-Link
  signed `.bin`. Use it with an official firmware to restore stock, then redo the
  telnet trick if you need root again.
- There is **no boot-attempt counter**: U-Boot only falls back to the other slot if
  the FIT fails to *load*. A kernel that loads then hangs will **not** auto-revert —
  keep the other slot bootable.

See `FINDINGS.md` for the historical debug record (MTD layout, U-Boot boot logic,
and the RTL8367S SerDes/MDIO investigation).

## Credits
IPQ5018 DWMAC/UNIPHY-PCS base merged upstream (OpenWrt PR #22381). RTL8367S
SGMII/HSGMII datapath by **Johan Alvarado** (netdev). Cold-start SerDes busy-wait fix
by **Mieczysław Nalewaj**. No-serial root method from lmadarassy & the forum 158384
contributors. Port & hardware validation: Stanisław Pal (kuncy7).
