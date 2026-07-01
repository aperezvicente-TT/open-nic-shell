# Chapter 6 — Build & Flash Guide

This chapter takes you from source to a running, flash-resident bitstream on the Alveo
U200.

## 6.1 Prerequisites

- **Vivado 2024.2** at `/opt/amd/Vivado/2024.2` (the build wrapper sources
  `settings64.sh` from there).
- **CMAC license.** The `cmac_usplus` (*UltraScale+ Integrated 100G Ethernet*) core needs
  a **node-locked license** to synthesize/implement. Without it the CMAC IP's OOC synth
  run fails and there is no bitstream. On this bench the license is at
  `~/.Xilinx/Xilinx100GEthSubsystem.lic` (node-locked to MAC `a8:a1:59:f4:62:a9`). **Do
  not move or delete it.** If a build suddenly can't find a CMAC license, restore that
  file (or set `XILINXD_LICENSE_FILE`).
- Board files: `board_files/Xilinx/` (used automatically via `set_param board.repoPaths`).
- The `onic` driver toolchain for the host side (Ch. 5 §5.7).

## 6.2 The one-command build

```bash
cd /home/alex/mpi-shfs/fpga/open-nic-shell/script
./build_eth_1pf_2cmac_qid.sh
```

That wrapper (`script/build_eth_1pf_2cmac_qid.sh`) sources Vivado 2024.2 and runs:

```bash
vivado -mode batch -source build.tcl -tclargs \
    -board au200 -tag eth_1pf_2cmac_qid -overwrite 1 -rebuild 1 \
    -synth_ip 1 -impl 1 -post_impl 1 -jobs 16 \
    -num_queue 2048 -max_pkt_len 9600 -pkt_cap 16 \
    -num_cmac_port 2 -num_phys_func 1 \
    -user_plugin ../plugin/eth_2cmac_1pf  2>&1 | tee build_eth_1pf_2cmac_qid_full.log
```

- `-impl 1 -post_impl 1` runs the full flow **through `write_bitstream` and `write_cfgmem`**,
  producing both `.bit` and `.mcs`.
- `-overwrite 1 -rebuild 1` handle cleanup **inside** `build.tcl` (no manual `rm -rf`
  needed): `-rebuild 1` deletes `$build_dir/open_nic_shell`, `-overwrite 1` deletes the
  cached IP + top build. (If you ever invoke `build.tcl` *without* these on a dir that
  already has generated IP, you hit the "IP name `cmac_usplus_0` already in use" error.)
- `EXT_QID=1` is **not** a build flag — it is hardcoded on the `qdma_subsystem` instance
  in `open_nic_shell.sv` (Ch. 3 §3.2).
- Full build is ~3–5 h at `-jobs 16`.

## 6.3 What `build.tcl` does (stages)

`script/build.tcl` is the master Tcl driver. In order:

1. **Parse args** into `build_options`, `design_params`, `sim_params`; sanity-check
   ranges (`num_cmac_port ∈ {1,2}`, `num_queue` power-of-two ≤ 2048, `max_pkt_len ∈
   [256,9600]`, …).
2. **Board settings:** source `board_settings/au200.tcl` → `part = xcu200-fsgd2104-2-e`,
   `board_part = xilinx.com:au200:part0:1.3`.
3. **IP synthesis** (Manage IP project): for each subsystem's `vivado_ip/vivado_ip.tcl`,
   create the IPs (board-specific `${ip}_au200.tcl` when present), `upgrade_ip`,
   `generate_target synthesis`, and OOC-synth them.
4. **Create design project** with `verilog_define = __synthesis__ __au200__`.
5. **Read IP**, then **read the user plugin** (the ingestion loop, §6.4), then **read RTL**.
6. **Set generics** from `design_params` (uppercased).
7. **Read constraints:** `pins.xdc` + `timing.xdc` (unmanaged), then `general.xdc` and
   the generated `run_params.xdc`.
8. **Implementation:** `launch_runs impl_1 -to_step write_bitstream` (synth → place →
   route → bitstream in one flow).
9. **Post-impl:** `write_cfgmem` → `.mcs`.

### Command-line arguments (defaults in parentheses)

`-board` (au250), `-tag` (""), `-overwrite` (0), `-rebuild` (0), `-jobs` (8), `-synth_ip`
(1), `-impl` (0), `-post_impl` (0), `-user_plugin` (`plugin/p2p`), `-num_phys_func` (1),
`-num_qdma` (1), `-num_queue` (512), `-num_cmac_port` (1), `-min_pkt_len` (64),
`-max_pkt_len` (1518), `-pkt_cap` (64), `-bitstream_userid` (0xDEADC0DE),
`-bitstream_usr_access` (0x66669999).

## 6.4 How the plugin gets into the build

The ingestion loop (`build.tcl:355–378`), for each of `box_250mhz` and `box_322mhz`:
looks for `${user_plugin}/${box}` + `${user_plugin}/build_${box}.tcl`; if present, sources
the box's `axi_crossbar.tcl` (and `axis_switch.tcl`), reads its `address_map.v`, adds the
box dir to the include path, then sources `build_${box}.tcl`. Otherwise it falls back to
`plugin/p2p`. See Ch. 4 §4.6 for what `eth_2cmac_1pf` contributes.

## 6.5 The timing XDC fix (`constr/au200/timing.xdc`)

**Problem:** bare `set_false_path` on the PTP CDC synchronizer flops fails with
*"No valid object(s) found" ([Vivado 12-4739])* when synthesis optimizes or renames those
cells and `get_cells` returns an empty list — aborting the whole run. This is a
pre-existing upstream `main` hazard that this branch fixes.

**Fix** (`timing.xdc:84–85`): guard the exception behind a length check.

```tcl
proc fp_to_if   {objs} { if {[llength $objs]} { set_false_path -to   $objs } }
proc fp_from_if {objs} { if {[llength $objs]} { set_false_path -from $objs } }
```

Both PTP CDC blocks are wrapped with these:
- **TX** (`ptp_clock_cdc_inst`): `fp_to_if` on toggle-sync first stages, `fp_from_if` on
  data-capture registers, `fp_to_if` on the reset sync (`timing.xdc:89–107`).
- **RX** (`ptp_clock_cdc_rx_inst`): same pattern (`timing.xdc:146–164`).

The `ASYNC_REG TRUE` / `SHREG_EXTRACT NO` properties on those FF chains still protect the
crossings; the guarded false-path just avoids the empty-object-list abort.

Other timing content in the same file: PCIe clock + `pcie_rstn` false path;
`axis_aclk ↔ cmac_clk` and QDMA-125 MHz ↔ datapath max-delays; RX-serdes max-delay; and
floorplan pblocks for the packet-adapter TX/RX (`CLOCKREGION_X0Y9:X2Y11` /
`X3Y9:X5Y11`).

## 6.6 Timing closure for production ⚠️

> **Important caveat about reproducibility.** The validated, timing-clean image currently
> flashed (WNS 0.000) was produced by a **manual post-route `phys_opt_design`** pass on
> the routed checkpoint, using aggressive directives. A **fresh `build.tcl` run does not
> reproduce that closure** — stock implementation lands slightly negative (WNS ≈ −0.03 to
> −0.13 ns, functional but not clean).
>
> To make production builds reproducibly timing-clean, the `phys_opt`/Performance strategy
> must be **baked into the implementation flow** (a strategy directive or an explicit
> `phys_opt_design` step in `_do_impl`). This is an **open item** — see Ch. 8 §8.6.

## 6.7 Build artifacts

Everything lands under
`build/au200_eth_1pf_2cmac_qid/open_nic_shell/open_nic_shell.runs/impl_1/`:

| Artifact | What it is |
|----------|------------|
| `open_nic_shell.bit` | FPGA config bitstream — **volatile** JTAG load, lost on power cycle |
| `open_nic_shell.mcs` | Flash image built from the `.bit` by `write_cfgmem` — **persistent** in SPI config flash |
| `*_routed.dcp` | Final routed checkpoint (the input to the manual `phys_opt` closure) |
| `*_opt/_placed/_physopt.dcp` | Intermediate checkpoints |

**`.bit` vs `.mcs`:** the `.bit` loads directly into config SRAM over JTAG and is lost at
power-off. The `.mcs` is written into the board's 128 Mbit SPI flash at offset
`0x01002000`; because `general.xdc` sets `CONFIGFALLBACK Enable` + `CONFIG_MODE SPIx4`,
the FPGA **boots from that flash automatically** on power-up/reboot.

## 6.8 Flashing the card

Use the host-side wrapper:

```bash
cd /home/alex/mpi-shfs/fpga/open-nic-shell/script
./program_fpga.sh -p <path>/open_nic_shell.mcs      # persistent (flash)
# or, for a volatile test load:
./program_fpga.sh -p <path>/open_nic_shell.bit
```

`program_fpga.sh` auto-detects the first JTAG target (or pass `-t`), then dispatches to
`program_hw.tcl`:
- **`.bit`** → `program_hw_devices` (volatile).
- **`.mcs`** → builds a cfgmem for `mt25qu01g`, erases/programs/verifies the SPI flash,
  then `boot_hw_device` triggers boot-from-flash. It prints *"Please reboot the machine
  for FPGA to load from flash."*

**After flashing a `.mcs`, reboot (or power-cycle) the host** so the FPGA re-reads config
from flash and PCIe re-enumerates. Confirm the flashed image with the build-stamp register
(Ch. 8 §8.2) — the validated clamp-fix image reads `0x07010922`.

Continue to [Chapter 7 — Operation & Bring-up Runbook](07-operation-runbook.md).
