# AX55 v1 — technical findings

> **Historical debug record.** These notes date from the porting/investigation phase
> (pre-mainline, on an out-of-tree base). Hardware facts (MTD layout, U-Boot logic,
> chip IDs) remain accurate; some conclusions about the SerDes/datapath were
> superseded — the current state is in `README.md` and PR #24197.

Reference notes gathered while porting OpenWrt to the TP-Link Archer AX55 v1.
Confirmed from a **live root shell on stock**, from the **GPL U-Boot/QSDK source**,
and from FCC internal photos.

## NAND / MTD layout (live `cat /proc/mtd`, 128 MB SPI-NAND, PEB 128 KiB)
```
mtd0  0:SBL1        0x080000     mtd8  0:APPSBL      0x140000
mtd1  0:MIBIB       0x080000     mtd9  0:ART         0x100000   <- WiFi caldata
mtd2  0:BOOTCONFIG  0x040000     mtd10 0:TRAINING    0x080000
mtd3  0:BOOTCONFIG1 0x040000     mtd11 rootfs        0x2a00000  <- OS slot 0 (42 MiB)
mtd4  0:QSEE        0x100000     mtd12 rootfs_1      0x2a00000  <- OS slot 1 (42 MiB)
mtd5  0:DEVCFG      0x040000     mtd13 tp_data       0x840000
mtd6  0:CDT         0x040000     mtd14 radio         0x440000
mtd7  0:APPSBLENV   0x080000     mtd15 data          0x080000
```
- Two OS slots, 0x2a00000 (42 MiB) each. Each holds a UBI with volumes
  `kernel` (FIT) + `ubi_rootfs` (squashfs) + `rootfs_data`.
- **Dual-boot flag = U-Boot env `tp_boot_idx`** in `0:APPSBLENV` (mtd7).
  `=1` → boot `rootfs_1` (slot 1); else → `rootfs` (slot 0).
- Env is minimal: only `baudrate=115200` + `tp_boot_idx`. All boot logic is
  compiled into U-Boot, not in env.
- Stock `/etc/fw_env.config`: `/dev/mtd7 0x0 0x40000 0x00020000 0x2`.

## U-Boot boot logic (GPL `board/qca/arm/common/cmd_bootqca.c`, `do_bootipq`)
- Slot select: reads `tp_boot_idx`; boots that slot via `do_boot(idx)`.
- **Fallback:** if `do_boot(idx)` *returns failure* (FIT cannot be loaded), it retries
  `do_boot(!idx)`; if both fail → `up_file_via_httpd()` (recovery at 192.168.0.1).
  There is **no boot counter / health-check** — a kernel that loads then hangs never
  returns to U-Boot, so it does **not** auto-revert.
- Secure boot: `qca_scm_call(SCM_SVC_FUSE, QFPROM_IS_AUTHENTICATE_CMD)`. If the fuse
  is blown → `do_boot_signedimg` (unsigned kernel rejected). If not → `do_boot_unsignedimg`
  (no signature check). Consumer units usually leave the fuse **unblown** (they gate
  upgrades via software RSA, not HW secure boot), so an unsigned OpenWrt FIT should
  boot. Unconfirmed on real HW, but the auto-fallback makes testing safe.
- Kernel load (NAND, unsigned path): `ubi part fs` on the slot, then
  `ubi read <addr> kernel` → the UBI volume **must be named `kernel`** (a FIT).
- Config select: env `config_name` if set, else the first control-DTB candidate that
  exists in the FIT. Our FIT uses `config@mp03.3`; force with
  `fw_setenv config_name config@mp03.3` if auto-select fails.
- Rootfs bootargs are forced by U-Boot: `ubi.mtd=rootfs root=mtd:ubi_rootfs
  rootfstype=squashfs`. Our DTS overrides root by index via
  `bootargs-append = " root=/dev/ubiblock0_1 …"` (last `root=` wins; a UbiFit device
  has kernel = vol 0, rootfs = vol 1). This matches sibling qualcommax UbiFit devices
  that boot on stock QCA U-Boot (gl-b3000, ax830, ax850, mx6200).

## Firmware signing (relevant to install/recovery)
- **U-Boot web recovery = RSA-gated** (`nm_fwup.c` `handle_fw_cloud`, RSA1024/2048 +
  MD5 + SupportList). Rejects OpenWrt and any modified image.
- **Runtime web-UI upgrade = MD5 only** for the *legacy* (2022/2024) unencrypted
  `tplink-safeloader`+UBI format. Repacking with the `\x50\x72` ("Pr", `fw-type:Proud`)
  flag at file offset 0x1C takes the image out of the RSA/Cloud branch → the running
  OS accepts it. This is how root telnet is obtained (telnet enabled in squashfs).
- 2025 firmware (v1.5.10) is AES-"Cloud" encrypted; 2024 (v1.3.3) and 2022 are the
  legacy unencrypted format. Downgrading via the web UI is accepted.

## No-serial install path (what we actually did)
1. Root telnet on stock (above).
2. `mtd erase /dev/mtd11` + `mtd write factory.ubi /dev/mtd11` into the inactive slot.
   - **Stock `ubiformat -f` SIGFPEs** (`Arithmetic exception`) on this old QSDK
     mtd-utils, before writing — with or without `-s 512/2048`. subpagesize reports
     2048 correctly, so it is a mtd-utils bug, not geometry. `mtd write` avoids it.
   - The stock is **32-bit ARMv7** (`uname -m` = `armv7l`), so an aarch64 replacement
     `ubiformat` will not exec — a static **armv7** build would be needed instead.
3. `fw_setenv tp_boot_idx 0` + `fw_setenv config_name config@mp03.3` + `reboot`.

Result: FIT loads (no U-Boot fallback), but no WiFi/WAN/LAN came up. **Needs a serial
boot log to diagnose (panic vs. booted-but-no-interface).**

## RTL8367S / (H)SGMII — SOLVED (2026-07-06)

The trunk (1G SGMII *and* 2.5G HSGMII) passes traffic from cold boot with two
additions to the `rtl8365mb` SGMII patch — **both mandatory**, each alone gives
a "link up, zero frames either way" trunk:

1. **SerDes SGMII in-band autoneg must be disabled** (both trunk ends are
   fixed-link/forced, AN never completes, the SerDes drops everything).
   Vendor `rtl8367c_setSgmiiNway`: pause the 8051 (`0x130C` bit 5 = 0) →
   INDACS read SDS reg `0x0002` (ADR `0x6601`, CMD `0x6600`=`0x0080`, DATA
   `0x6602`) → clear bit 9, set bit 8 (commit) → INDACS write (CMD `0x00C0`)
   → resume the 8051.
2. **`SDS_MISC` (`0x1D11`) force bits written from `mac_link_up`** — vendor
   `setAsicPortForceLinkExt` type-1: FDUP bit 10, LINK bit 9, SPD bits 8:7
   (+RXFC bit 14/TXFC bit 13). **Bit 9 directly gates the SerDes TX** — with
   everything else configured perfectly the trunk stays silent until it's set.

Hard-won debugging facts:
- **Never `cat`/`grep` the full regmap debugfs `registers` file of this switch**
  — dumping the whole register space over MDIO wedges the RTL8367S MDIO slave
  (all reads return 0) until a hard power cycle. Read single registers by
  offset (`dd bs=11 skip=$((0xREG)) count=1`).
- The 8051 SerDes firmware **continuously polls SDS status reg `0x3D` through
  the same INDACS engine** — host INDACS accesses race it and lose. Pause the
  8051 (`0x130C` bit 5) around every INDACS access, like the vendor does.
- SDS status reg `0x3D`: bit 8 = SignalDetect, bit 0 = Sync, bit 4 = Link.
- SDS reg `0x0000` = `0x1403` normal operation; vendor `rtl8367c_sdsReset`
  pulses `0x1401` → `0x1403`.
- The uniphy CH_STS register with FORCE_MODE cleared is NOT a valid
  "peer TX alive" probe (part of the RX path stops when unforced).
- The stock TP-Link firmware runs this trunk at **1G SGMII**
  (`switch_mac_mode 0x0c` = SGMII_CHANNEL0; live `ssdk_sh port speed get 2` →
  1000). 2.5G HSGMII works fine with this driver — a free upgrade over stock.

## WAN / port mapping — SOLVED (2026-07-06)

The IPQ5018's internal GE PHY (mdio0 addr 7) is **not bonded out** on the
AX55: it probes fine (clocks, resets, TCSR LDO all OK) but its AFE goes
nowhere. All five front jacks are the RTL8367S's five internal PHYs,
verified jack-by-jack with a BMSR logger: **blue WAN = phy0, LAN1-4 =
phy1-4** (phy4 ships powered-down — BMCR 0x1940 — because no port used it;
that was the "dead LAN4 jack"). So "WAN" is simply switch port 0.

Factory MACs live in the **`default-mac` file (6 raw bytes) inside the
`tp_data` UBI volume** (label MAC = lan, +1 wan, +2/+3 radios). tp_data also
carries `product-info`, `device-id`, certificates etc.

Useful trick: RTL8367S PHY registers can be read/written from userspace via
the switch INDIRECT_ACCESS regs (0x1F00-0x1F04 + OCP prefix in 0x1D15,
ocp_addr = 0xA400 + 2*reg) — that is how the per-jack mapping and the phy4
power-down were found without any serial console.

## (historical) RTL8367S / HSGMII — the open datapath problem
- WAN (`switch_wan_bmp=0x00`) never touches the RTL switch: it is the IPQ5018 internal
  GE PHY @ mdio0:7 on `gmac0`. WAN and WiFi are therefore independent of the RTL8367S
  and are the intended out-of-band bring-up channels.
- LAN = `gmac1` → UNIPHY0 → 2.5G HSGMII → RTL8367S. Confirmed HW facts:
  RTL8367S **reset = GPIO39**, MDIO addr **29**, CPU/ext port **6**,
  `switch_lan_bmp=0x1e` (LAN1-4 = internal PHY 0-3), machid `0x8040002`.
- Patch **0918** rebases Hauke's 2022 rtl8365mb SGMII/HSGMII work onto the monolithic
  6.12.92 driver: SerDes `redData*` tables, 8051 firmware load via `request_firmware`
  (`rtl_switch/rtl8367s-sgmii.bin`), `ext_config_sgmii`, 2500BASEX/SGMII in
  `supported_interfaces`, `mac_config`/`link_up` for SPEED_2500.
- **Open question (shared with Sunshainy):** on real HW the SerDes/8051 upload appears
  to break MDIO to the RTL8367S (PHY reads return 0/0xffff) right after the firmware
  push. Likely a wrong `redData` vs `redDataHB` table branch or ordering for
  **chip_ver 0x00A0** (our exact chip). Sunshainy has the OCP writes
  (`0xB83E/0xB840/0xB820`) + BMCR power-down clear (`0xA400/0xA42C`) +
  `SDS_INDACS 0x6600-0x6602`, but is stuck on the same table-selection question.
  Comparing our patch 0918's table branch against his jam table + dmesg is the
  next concrete step.
