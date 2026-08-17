---
name: reference-tt-link-bridge-test
description: "How to run the WH→AU200 tt-link bridge end-to-end test, including FW build, load, manual TX, and FPGA-side counter verification"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c4372cc9-6de5-4473-97ce-f51a44549f4b
---

# tt-link bridge first-light test (WH → AU200 CMAC0 → tt_link_udp_bridge)

**Topology**: WH chip on local host (PCI `01:00.0`), AU200 FPGA on `10.42.0.180` (`0000:02:00.0`), 100G QSFP between WH erisc0 and FPGA CMAC0.

## One-shot runner
```
COUNT=100 SIZE=128 bash /home/alex/mpi-shfs/fpga/wh-erisc-fpga/run_tt_link_test.sh
# REBUILD=1 to rebuild the firmware first
```
Builds (optional) → loads ELF → waits for `LINK_TRAIN_SUCCESS` → checks FPGA CMAC0 `STAT_RX_STATUS=0x03` → fires N packets → reads bridge counters → diffs.

## Component paths
- ERISC firmware source: `/home/alex/mpi-shfs/tenstorrent/budabackend-master/src/firmware/riscv/targets/erisc_cmac_simple/`
- ERISC firmware build script: `.../rebuild.sh` (SFPI at `/home/alex/mpi-shfs/tenstorrent/sfpi/build/sfpi`)
- Built ELF: `/home/alex/mpi-shfs/tenstorrent/budabackend-master/build/src/firmware/riscv/targets/erisc_cmac_simple/out/erisc_cmac_simple.elf`
- Manual TX trigger: `/home/alex/mpi-shfs/fpga/wh-erisc-fpga/manual_tx_trigger.py` (tt-exalens; requires `safe_mode=False` to reach `ETH_TXQ0_REGS_START = 0xFFB90000`)
- tt-exalens scripts: `/home/alex/mpi-shfs/tenstorrent/tt-exalens/scripts/{load_erisc_fw,dump_custom_fw_debug,eth_packet_test}.py`

## FPGA-side observability (BAR2 on `0000:02:00.0`)
- CMAC0 `STAT_RX_STATUS` @ `0x8204` — `0x03` = PCS aligned, `0xC0` = local fault (no link partner)
- CMAC0 RX stat TICK @ `0x82B0` (write any value to latch stats)
- tt_link bridge (no-RDMA build, Box0 base `0x100000`):
  - `cls_passed`  @ `0x100430`
  - `cls_dropped` @ `0x100434`
  - `dmx_passed`  @ `0x100438`
  - `dmx_dropped` @ `0x10043C`

Raw-ethertype frames (e.g. `0x9999`) are classified-dropped — expected; the bridge expects UDP. See [[project-tt-link-bridge]] when wiring real UDP tests.

## Production firmware quirks worth knowing
- The shipped `erisc_cmac_simple` (May 13 build) is a **burst-free** build (`main_cmac.cc:845-850`): `init_tx_burst()` pre-configures TX regs but the main loop **does not** call `tx_fire`. Default state = idle until `GW_MODE_ADDR (0x1F50)` is set to `0xDA7ADA7A` (gateway/WQE modes).
- For standalone bridge testing, drive TX externally via `manual_tx_trigger.py`. NOC-RTT vs MAC-commit timing means roughly every-other `CMD=1` is dropped without throttling — the trigger script handles this by polling `PKT_END_CNT` and retrying with a 500 µs nap.
- Sudoers needed on the FPGA host so the runner can `pcimem` non-interactively: see [[sudoers-pcimem]] (line added to `tools/install_onic_sudoers.sh`).
