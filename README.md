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

The RTL8367S trunk needs SGMII/HSGMII support in the `rtl8365mb` DSA driver.
**Johan Alvarado's series is now merged** (netdev, backported into OpenWrt main in
July 2026) — it brings the SerDes up as a phylink PCS with the **DW8051 kept in
reset, no firmware blob** — so a current OpenWrt main tree needs nothing extra for
the trunk itself. What remains out of tree lives in [`src/`](src/):

| file | what it does |
|---|---|
| `0001-…-wait-out-full-chip-reset.patch` | the reset bit clears long before the switch finishes bring-up; configuring too early loses register writes (cold-boot half-dead switch) |
| `0002-…-let-the-serdes-pll-settle-after-dp-reset.patch` | ~98 ms SerDes PLL settle after the data-path reset, as the vendor firmware does (cold-boot TX-dead SGMII) |
| `0003-usb-dwc3-qcom-select-tcsr-phy-mux-before-reset.patch` | **the USB3 SuperSpeed fix**: optional `qcom,phy-mux-regs` DT hook + the mux write as the *first* thing in probe, before the controller reset |
| `0004-phy-qcom-add-ipq5018-usb-ss-phy.patch` | IPQ5018 USB SS uni PHY driver (faithful port of the vendor init sequence) |
| `ipq5018-tplink-archer-ax55-v1.dts` | current board DTS (incl. the USB SS phy node and the mux register) |

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
| USB 3.0 (SuperSpeed) | ✅ 5 Gbps, 112–116 MB/s sustained (patches `0003`+`0004`) |
| Software flow offload | ✅ (`kmod-nft-offload`) |
| Cold boot after hours powered off | ✅ (patches `0001`+`0002`) |

**This is a fully functional router**: ~275 Mb/s NAT over Wi-Fi, the 2.5G internal
trunk runs faster than stock (which caps it at 1G), and the whole port was done
without soldering a serial console.

### Solved: cold-start trunk degradation
After hours powered off, the first boot used to bring the HSGMII trunk up
(2.5Gbps/Full) with the data path degraded — frames silently discarded on the
port-6 egress path, no CRC/symbol errors; a soft reboot recovered it. Root cause
was twofold and both halves are in `src/`: the driver touched the switch before
its internal bring-up finished (`0001`), and the SerDes PLL got no settle time
after the data-path reset (`0002`). Without the settle roughly 1 boot in 7 came
up TX-dead; with both patches every boot has been clean. Diagnostics history:
forum thread *"reduce number of drivers for rtl8367s"*.

### Solved: USB3 SuperSpeed (mux ordering)
The IPQ5018 USB SS pads are shared with PCIe through a TCSR mux, and TP-Link's
U-Boot never touches USB, so the pads stay muxed away. Writing the mux *late* in
probe is not enough — it must happen **before the controller reset**, or the SS
link never leaves Rx.Detect while USB2 keeps working (HS does not go through the
mux). Patch `0003` does exactly that; the PHY driver (`0004`) needs no board
magic. The same TCSR register (`0x01947540`) was confirmed on IPQ5332
(GL.iNet Flint 3, forum thread 250267) — there GL.iNet's bootloader happens to
leave the mux right, which is why SS "just worked" on that board.

## Build
```sh
# Base: openwrt/openwrt main (kernel 6.12) — it already carries PR #22381
#       (UNIPHY-PCS + IPQ5018 DWMAC). No out-of-tree base patch is needed anymore.
git clone https://github.com/openwrt/openwrt.git && cd openwrt

# Drop in the cold-boot switch fixes (generic - any Realtek rtl8365mb board
# benefits) and the USB3 patches:
cp .../src/0001-*.patch .../src/0002-*.patch target/linux/generic/pending-6.12/
cp .../src/0003-*.patch .../src/0004-*.patch target/linux/qualcommax/patches-6.12/
# plus the device support (DTS, base-files, image recipe, ipq-wifi, BDFs) from PR #24197
#   https://github.com/openwrt/openwrt/pull/24197  (or git fetch the branch)

./scripts/feeds update -a && ./scripts/feeds install -a
make menuconfig    # Target: qualcommax / ipq50xx / TP-Link Archer AX55 v1
make -j$(nproc)
```
For USB3 the DTS must also carry the SS phy node and
`qcom,phy-mux-regs = <&tcsr 0x10540>;` in the usb node — the `src/` DTS has both.

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
SGMII/HSGMII datapath by **Johan Alvarado** (netdev, merged). The 98 ms SerDes
settle constant was pointed out by **Mieczysław Nalewaj** (vendor firmware
disassembly). IPQ5332 TCSR mux register confirmation by **Dusknoir**, Flint 3
testing by **perceival** (forum 250267). No-serial root method from lmadarassy
& the forum 158384 contributors. Port, USB3 mux-ordering root cause & hardware
validation: Stanisław Pal (kuncy7).
