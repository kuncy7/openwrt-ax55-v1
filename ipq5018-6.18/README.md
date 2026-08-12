# Clean IPQ5018 patches for kernel 6.18

The two fixes an IPQ5018 board actually needs on 6.18, without any debug
instrumentation. If you carried `debug/debug-d50-spinand-512.patch`, drop
it - it was diagnostic only (the `DBG ... ret=-517` lines come from it;
-517 is EPROBE_DEFER and is harmless) - and keep just these:

- `478-spi-qpic-snand-write-feature-value-before-exec.patch` -
  SET_FEATURE off-by-one in the QPIC SPI-NAND controller. In mainline as
  8fd62901d6bf, queued for stable; drop this copy once your tree's 6.18
  includes it. Goes to `target/linux/generic/pending-6.18/`.
- `0191-clk-qcom-ipq-cmn-pll-keep-the-CMN-block-bus-clocks-enabled.patch` -
  fixes the early-boot hang/boot-loop on IPQ5018 (OpenWrt PR #24653,
  discussion on linux-clk ongoing). Goes to
  `target/linux/qualcommax/patches-6.18/`.

Board-specific ECC properties (`nand-ecc-strength`/`nand-ecc-step-size`
in your DTS) are separate - see the D50 thread, post #433.
