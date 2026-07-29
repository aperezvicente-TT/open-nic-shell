# Chapter 6 — Build & Flash Guide

This chapter takes you from source to a running, flash-resident bitstream on the Alveo
U200.

## 6.1 Prerequisites

- **Vivado 2024.2.** The wrapper auto-detects `settings64.sh` under `/opt/amd/fpga`,
  `/opt/amd`, `/tools/Xilinx` or `/opt/Xilinx` — installs differ per bench
  (`homelab-1` has it at `/opt/amd/fpga/Vivado/2024.2`).
- **CMAC license.** The `cmac_usplus` (*UltraScale+ Integrated 100G Ethernet*) core needs
  a **node-locked license**, held in `~/.Xilinx/*.lic` (Vivado scans that directory; or
  point `XILINXD_LICENSE_FILE` at the file). Node-locked means locked to a **specific
  host ID** — the MAC of one network interface — so moving to a new machine requires
  **rehosting the license on the AMD portal**, not copying the file.

  Without it, the CMAC IP reports
  `[IP_Flow 19-650] IP license key 'cmac_usplus@2020.05' is enabled with a Design_Linking
  license`. Design_Linking permits synthesis *and* implementation but **blocks
  `write_bitstream`**, so a full build runs for over an hour and then fails at the last
  step with:

  ```
  ERROR: [Common 17-69] This design contains one or more cells for which bitstream
  generation is not permitted:  i_cmac_usplus_0_top (<encrypted cellview>)
  ```

  To check licensing *before* committing to a build, generate the IP on its own and look
  for that warning:

  ```bash
  vivado -mode batch -source - <<'EOF'
  create_project -in_memory -part xcu200-fsgd2104-2-e
  create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name lic_test -dir ./lictest
  generate_target synthesis [get_files lic_test.xci]
  EOF
  ```

  A licensed host shows no `19-650` line for `cmac_usplus` (one for `cmac_an_lt` is
  expected and harmless — this design uses CAUI4 without auto-negotiation/link-training).
- Neither `write_bitstream` nor the CMAC IP needs anything beyond the free entitlement for
  **`xcu200` synthesis/implementation** itself; that license is granted automatically.
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
    -synth_ip 1 -impl 1 -post_impl 1 -jobs "${JOBS:-16}" \
    -num_queue 2048 -max_pkt_len 9600 -pkt_cap 16 \
    -num_cmac_port 2 -num_phys_func 1 \
    -user_plugin ../plugin/eth_2cmac_1pf  "$@" \
    2>&1 | tee build_eth_1pf_2cmac_qid_full.log
```

- Arguments given to the wrapper are **appended**, so they override the defaults:
  `./build_eth_1pf_2cmac_qid.sh -overwrite 0 -impl_strategies '...'`.
- `-user_plugin ../plugin/eth_2cmac_1pf` is **mandatory**. Omit it and `build.tcl` silently
  falls back to `plugin/p2p`, producing a bitstream with no qid steering at all.
- `-impl 1 -post_impl 1` runs the full flow **through `write_bitstream` and `write_cfgmem`**,
  producing both `.bit` and `.mcs`. Use `-impl_to_step post_route_phys_opt_design
  -post_impl 0` to stop before bitstream generation (e.g. unlicensed CMAC, §6.1).
- `-overwrite 1 -rebuild 1` handle cleanup **inside** `build.tcl` (no manual `rm -rf`):
  `-rebuild 1` deletes `$build_dir/open_nic_shell`; `-overwrite 1` deletes
  `$build_dir/vivado_ip` **including the Manage IP project**. That last part matters —
  deleting only the per-IP directories leaves each `.xci` registered in the project and
  the next `create_ip` fails with *"IP name 'axi_stream_pipeline' is already in use in
  this project"*.
- `EXT_QID=1` and `RSS_ON_EXT=1` are **not** build flags — both are hardcoded on the
  `qdma_subsystem` instance in `open_nic_shell.sv` (Ch. 3 §3.2, Ch. 11).
- **Runtime, measured on a 256-core / 157 GB host** (`homelab-1`, 2026-07-29): IP synthesis
  ~14 min, top synthesis ~5 min, one implementation ~40-75 min → **~96 min end to end**
  for two strategies plus both bitstreams. Re-running with `-overwrite 0` reuses the IP
  cache and skips the first 14 min.

### Parallelism (`-jobs`, `-max_threads`, `-ultrathreads`)

Three separate knobs, easy to confuse:

| Option | Controls | Ceiling |
|--------|----------|---------|
| `-jobs` | concurrent **runs** (`launch_runs -jobs`) | as many runs as exist: ~15 IPs, then one per strategy |
| `-max_threads` | `general.maxThreads` **inside** each run | **32** on 2024.2 (`Value should be >= 1 and <= 32`; Linux default 8) |
| `-ultrathreads` | `place_design`/`route_design -ultrathreads`, spreading threads across SLRs | UltraScale+ SSI only (xcu200 = VU9P, 3 SLRs) |

IP synthesis is launched as a single fan-out (all runs concurrent, then one wait), so
`-jobs` genuinely parallelizes it — 15 concurrent runs reached ~48 cores and cut the stage
from ~45-60 min to ~14. Beyond that, utilization is bounded by algorithm parallelism, not
by these settings: a single `synth_design` holds 37 OS threads but draws ~1.2 cores.
`-max_threads` above 8 only helps where a step's own cap allows it, which in practice means
placement/routing with `-ultrathreads`.

⚠️ With `-jobs 256` the IP stage also launches the `cms_subsystem_0` block design's ~34
child runs concurrently (48 runs total), which peaked at **129 GB resident**. On a smaller
host, cap `-jobs` accordingly.

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

## 6.6 Timing closure for production ✅

> **Resolved (2026-07-29).** Reproducible closure comes from the
> **`Performance_ExplorePostRoutePhysOpt`** implementation strategy, whose post-route
> `phys_opt_design` step is the automated equivalent of the manual pass that produced the
> original WNS 0.000 image. Pass it via `-impl_strategies` (§6.2) — no manual work on the
> routed checkpoint.

The finding came from a four-strategy sweep on the same synthesis run (all four launched
concurrently, so the comparison is controlled):

| Strategy | ultrathreads | WNS (ns) | TNS | Failing endpoints |
|----------|--------------|----------|-----|-------------------|
| Vivado Implementation Defaults | off | **−0.095** | −2.527 | 82 |
| Vivado Implementation Defaults | on | +0.027 | 0.000 | 0 |
| **Performance_ExplorePostRoutePhysOpt** | **off** | **+0.008** | **0.000** | **0** |
| Performance_ExplorePostRoutePhysOpt | on | +0.001 | 0.000 | 0 |
| Performance_ExtraTimingOpt | on | −0.348 | −7.676 | 41 |
| Congestion_SpreadLogic_high | on | +0.018 | 0.000 | 0 |

Two conclusions:

- **Defaults does not close** (−0.095 ns / 82 endpoints), confirming the original
  "stock lands slightly negative" observation. `write_bitstream` still succeeds — negative
  WNS is a warning, not an error — so a *functional but not clean* `.mcs` is easy to
  produce by accident. `build.tcl` now prints a `CRITICAL WARNING` when the run selected
  for `write_cfgmem` has negative WNS.
- **`-ultrathreads` is not required.** It does rescue Defaults (+0.027 ns), but placement
  is then non-reproducible run to run ("placement results will differ slightly"), so it is
  the wrong basis for a production image. `Performance_ExplorePostRoutePhysOpt` closes
  clean without it.

**Production recipe:**

```bash
./build_eth_1pf_2cmac_qid.sh -max_threads 32 -ultrathreads 0 \
    -impl_strategies 'Performance_ExplorePostRoutePhysOpt'
```

Add `{Vivado Implementation Defaults}` to the list to reproduce the comparison; each extra
strategy is a concurrent run costing ~20-30 GB of RAM and little extra wall clock.

## 6.7 Build artifacts

Everything lands under
`build/au200_eth_1pf_2cmac_qid/open_nic_shell/open_nic_shell.runs/impl_<N>/`, one
directory per strategy (`impl_1` is simply the first entry of `-impl_strategies`, **not
necessarily the run that closed timing**):

| Artifact | What it is |
|----------|------------|
| `open_nic_shell.bit` | FPGA config bitstream — **volatile** JTAG load, lost on power cycle |
| `open_nic_shell.mcs` | Flash image built from the `.bit` by `write_cfgmem` — **persistent** in SPI config flash |
| `*_routed.dcp` | Final routed checkpoint |
| `*_opt/_placed/_physopt.dcp` | Intermediate checkpoints |
| `*_timing_summary_routed.rpt` | Where WNS/TNS/WHS come from |

`-post_impl 1` writes the `.mcs` from whichever run has the **best WNS** among those that
produced a bitstream, and logs its choice:

```
INFO: [Post-impl] Using impl_2 for write_cfgmem (WNS=0.008471)
```

A routed `.dcp` from a build whose CMAC IP lacked a full license **cannot** be turned into
a bitstream later — the encrypted cellview keeps its Design_Linking state, and Vivado says
so: *"the current netlist needs to be updated by resetting and re-generating the IP output
products before bitstream generation."* Once a license is installed, rebuild with
`-overwrite 1` (which regenerates every IP) rather than trying to salvage the checkpoint.

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
