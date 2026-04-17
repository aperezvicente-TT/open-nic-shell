# Tier 1a Bitstream Validation Runbook

Sequence to run AFTER `build_2cmac_rdma_v2.sh` completes. ≈ 30 min end-to-end assuming no surprises.

## 0. Pre-flight — bitstream sanity check

Before touching the card, confirm the build artifacts exist and timing closed:

```bash
BUILD_DIR=/home/alex/mpi-shfs/fpga/open-nic-shell/build/au200_2cmac_2pf_rdma_v2
IMPL_DIR=$BUILD_DIR/open_nic_shell/open_nic_shell.runs/impl_1

# 1. Files exist
ls -lh $IMPL_DIR/open_nic_shell.bit $IMPL_DIR/open_nic_shell.mcs

# 2. Timing closed (worst slack should be >= 0 ns)
grep -A2 "Timing Summary" $IMPL_DIR/open_nic_shell_timing_summary_routed.rpt | head -10

# 3. No fatal errors in impl log
grep -E "ERROR|CRITICAL" $BUILD_DIR/open_nic_shell/open_nic_shell.runs/impl_1/runme.log | head
```

**Pass**: both `.bit` and `.mcs` exist, Worst Negative Slack (WNS) ≥ 0, no ERROR/CRITICAL entries.

**Fail — timing negative**: bitstream still programmable but flaky at speed. Acceptable for bring-up; note for Tier 1b. Post-route fix = try different impl strategy (`-strategies "Performance_ExplorePostRoutePhysOpt"`).

**Fail — bitstream missing**: build bombed before `write_bitstream`. Check the log for the last `ERROR:` line.

## 1. Back-up the current working bitstream

```bash
# Snapshot the currently-loaded bitstream artifacts
cp $BUILD_DIR/../au200_2cmac_2pf_rdma/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.bit \
   ~/au200_2cmac_2pf_rdma_original.bit
cp $BUILD_DIR/../au200_2cmac_2pf_rdma/open_nic_shell/open_nic_shell.runs/impl_1/open_nic_shell.mcs \
   ~/au200_2cmac_2pf_rdma_original.mcs
```

Rollback path if the new bitstream misbehaves.

## 2. Flash the card

Two options depending on your hardware setup. Use **JTAG programming** for dev iteration (fast, ephemeral until power cycle). Use **flash/MCS** for persistent install.

### Option A — JTAG (ephemeral, fast)

```bash
cd /home/alex/mpi-shfs/fpga/open-nic-shell/script
# Unload driver first — QDMA reprobe can hang the kernel if driver is mid-activity
sudo rmmod onic

# Use the program_fpga.sh or equivalent — check the script's args
./program_fpga.sh $IMPL_DIR/open_nic_shell.bit
```

**After JTAG program, PCIe bus needs to re-enumerate** because BAR sizes changed (4 MB → 16 MB). Most AU200 setups require a **warm reboot** for this; some allow PCIe rescan via:

```bash
# Try this first — may work on some systems
sudo sh -c "echo 1 > /sys/bus/pci/devices/0000:82:00.0/remove"
sudo sh -c "echo 1 > /sys/bus/pci/devices/0000:82:00.1/remove"
sudo sh -c "echo 1 > /sys/bus/pci/rescan"

# If lspci still shows old BAR size → reboot
sudo reboot
```

### Option B — flash MCS (persistent, slower)

```bash
# Program flash via program_hw.tcl if that's your flow
vivado -mode batch -source /home/alex/mpi-shfs/fpga/open-nic-shell/script/program_hw.tcl \
       -tclargs -mcs $IMPL_DIR/open_nic_shell.mcs
# Then power cycle the host (full shutdown + on).
```

## 3. Post-boot sanity

After reboot / rescan:

```bash
# 3.1 PCIe enumeration — both PFs must appear
lspci | grep -i xilinx
# Expected:
#   82:00.0 Ethernet controller: Xilinx Corporation Device 9064
#   82:00.1 Ethernet controller: Xilinx Corporation Device 9064

# 3.2 BAR2 is 16 MB (the critical new property)
sudo lspci -vv -s 82:00.0 | grep -E "Region [0-3]"
sudo lspci -vv -s 82:00.1 | grep -E "Region [0-3]"
# Expected:
#   Region 0: Memory at ... [size=256K]
#   Region 2: Memory at ... [size=16M]      ← was 4M

# 3.3 BAR4 (Tier 2 only — not yet)
# Absent — if you see a Region 4, Tier 2 accidentally landed

# 3.4 sysfs resource files
ls -la /sys/bus/pci/devices/0000:82:00.0/resource*
# resource2 should be 16777216 bytes (16 MB, not 4 MB)
```

**Pass**: BAR2 size = 16M on both PFs. **Fail**: go back to step 2; flash may have aborted, or the wrong bitstream loaded.

## 4. Rebuild + load driver

```bash
cd /home/alex/mpi-shfs/fpga/open-nic-driver
git status        # confirm on feature/ernic-v4.2-rebuild, SHELL_END = 0x1000000
make

sudo rmmod onic 2>/dev/null   # in case it auto-loaded
sudo insmod onic.ko
sudo dmesg | tail -40
```

**Pass**: `dmesg` shows normal probe sequence, no "pci_iomap failed" or "size too large" errors. Look for:
```
onic 0000:82:00.0: enabling device (0000 -> 0002)
onic 0000:82:00.0 onic130s0f0: Set MAC address to 00:0a:35:e0:82:00
onic 0000:82:00.0: Allocated 30 queue vectors
...
onic 0000:82:00.0: PTP hardware detected, version 0x0100
onic 0000:82:00.0 enp130s0f0: renamed from onic130s0f0
```

Same for 82:00.1.

**Fail**: dmesg shows `pci_iomap_range failed` → BAR2 didn't actually resize (step 3 was wrong); go back. Or driver binary doesn't match — check `modinfo onic` that `srcversion` changed.

## 5. Phase 1 CSR bring-up

The 27-test validation. Run for ERNIC0 first; only attempt ERNIC1 if ERNIC0 passes cleanly.

```bash
cd /home/alex/mpi-shfs/fpga/rdma_test
make phase1_csr_bringup

sudo ./phase1_csr_bringup 0000:82:00.0 0 | tee phase1_ernic0.log
# If that ends with "27 / 27 tests passed":
sudo ./phase1_csr_bringup 0000:82:00.0 1 | tee phase1_ernic1.log
```

### Interpretation

**27/27 pass** → Tier 1a complete. Proceed to Tier 1b (Items 2/3/4 + 5-remaining).

**Test 1 fail (`NUM_QP mismatch` or SIGBUS)** → GCSR unreachable. Possible causes:
- v4.3 offsets still wrong — grep PG332 for your specific field again.
- `system_config_axi_crossbar` IP didn't actually pick up the 21-bit ADDR_WIDTH. Verify in the `.xci` on disk.
- DDR4 MIG didn't calibrate, ERNIC held in reset. Need the Task C MIG status register (deferred). Workaround: watch the AU200 DDR4 calibration LED on the card.

**Test 2 fail (any GCSR reg)** → wrong register offset, or byte-lane handling. Recheck PG332 for that specific register.

**Test 3 fail (EN latch)** → XRNICCONF.EN is sticky-RO, or requires sequencing (MAC/IP programmed first). Reorder the test: program MAC+IP before the EN test.

**Test 4 partial fail** → PG332 PDT entry bit-widths differ from what we coded. The `expected` values in `phase1_csr_bringup.c` use our interpretation of PG332 v4.3 Table 8 — may need tweaking per-field.

**Test 5 fail (stride)** → PDT entries alias. The `C_NUM_PD` IP parameter may be different from 2048 default.

**Test 6 fail (QCSR)** → per-QP offsets wrong. Cross-check against PG332 QCSR section.

### Iteration

Each re-run of `phase1_csr_bringup` is idempotent and safe — all tests save-write-restore. You can tweak `reconic_reg.h` offsets, rebuild the test, re-run without rebuilding the bitstream or flash.

## 6. Record results

```bash
# Store the logs for the git record
cp /home/alex/mpi-shfs/fpga/rdma_test/phase1_ernic0.log \
   /home/alex/mpi-shfs/fpga/open-nic-shell/agent/reconic_integration/
cp /home/alex/mpi-shfs/fpga/rdma_test/phase1_ernic1.log \
   /home/alex/mpi-shfs/fpga/open-nic-shell/agent/reconic_integration/

# Update the status tracker
cd /home/alex/mpi-shfs/fpga/open-nic-shell
$EDITOR agent/reconic_integration/status.md    # mark Tier 1a DONE or diagnose
```

## 7. If Tier 1a is green — what's next

1. Append "Tier 1a — COMPLETE" entry to `status.md` with the phase1 log summary.
2. Plan Tier 1b work:
   - Item 2: add QDMA `en_axi_mm_qdma {true}` + `en_bridge_slv {true}` + `dma_intf_sel_qdma {AXI_MM_and_AXI_Stream_with_Completion}` to `qdma_no_sriov_au200.tcl`.
   - Item 3: wire `axi_sys_mem_mux_*` → `qdma_subsystem.s_axib_*` at `open_nic_shell.sv:3384`. Reference `RecoNIC/base_nics/open-nic-shell/src/open_nic_shell.sv:1743-1777`.
   - Item 4: expose `s_axib_*` ports in `qdma_subsystem.sv`. Reference the research agent's findings (ports, widths, sidebands).
   - Item 5-remaining: populate DMA buffer address registers (SQBAi/RQBAi/CQBAi/DATBUFBA/MSBs) in libreconic.
3. Rebuild — full impl pass ≈ same 4-8 h.
4. New test `phase2_loopback_write.c` — actual RDMA WRITE end-to-end.

## 8. Troubleshooting checklist

| Symptom | First thing to check |
|---|---|
| `phase1_csr_bringup` says "BAR2 sysfs size 0x400000 < expected 0x1000000" | Step 3 — new bitstream didn't load, or BAR sizing didn't take effect after reboot |
| All reads return 0xFFFFFFFF | `lspci -vv` Memory bit (cmd 0x02) — try `sudo setpci -s 82:00.0 COMMAND=0x02` |
| dmesg "pci_iomap_range failed" | Driver's SHELL_END still 0x400000 — make sure `modinfo onic` shows the new binary |
| XRNICCONF reads 0x00000000 stably | DDR4 MIG likely not calibrated — add Task C status register in next rebuild |
| Test 1 SIGBUS | Address 0x900000 (ERNIC0 GCSR) not decoded — crossbar 2 MB config didn't apply. Check `$IMPL_DIR/open_nic_shell_utilization_placed.rpt` for system_config_axi_crossbar |
| Random Phase 1 flakiness | Run twice; if different results each time, clock/reset chain issue — check DDR4 calibration light on AU200 |
