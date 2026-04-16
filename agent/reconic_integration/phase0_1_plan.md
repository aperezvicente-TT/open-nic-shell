# Phase 0 / Phase 1 — ERNIC Bring-up Verification Plan

> **SUPERSEDED 2026-04-16 (late)** — Phase 0 completed and produced the definitive finding that probes at `BAR2+0x220000` were hitting the MR/PD table (PD entry 512), not XRNICCONF. ERNIC v4.2 has GCSR at `ERNIC+0x100000`, unreachable with the current 256 KB crossbar windows. Phase 1 as described here targets the old 4 MB BAR / 256 KB window layout — it's obsolete.
>
> **Current pointers:**
> - Phase 0 closure: `status.md` → "Phase 0 Results — CLOSED 2026-04-16"
> - Phase 0 probe artifacts: `rdma_test/phase0_ernic_probe.c`, `phase0b_ernic_enable.c`, `phase0c_pd_table.c`
> - Replacement Phase 1 (post-rebuild CSR bring-up): `phase2_rtl_rebuild_plan.md` → "Tier 1a" (to be added)
>
> This document is retained for history. Do not act on it.

---

Date: 2026-04-16
Author: verification plan for the `au200_2cmac_2pf_rdma` bitstream currently loaded on `0000:82:00.0` / `0000:82:00.1`.

## Why this document exists

After the RTL audit (see `status.md` → "RTL Blocker discovered 2026-04-16"), Phase 2 (real RDMA WRITE loopback) is **blocked** on the current bitstream because:

1. `axi_sys_mem_mux_*` in `open_nic_shell.sv:3384-3388` is a comment-only stub — ERNIC's host-memory master has no consumer.
2. `qdma_no_sriov_au200.tcl:43-44` has `dma_intf_sel_qdma {AXI_Stream_with_Completion}` and `en_axi_mm_qdma {false}` — no QDMA bridge in either direction.
3. BAR2 is 4 MB (`pf0_bar2_size_qdma {4}`) so ERNIC1 at system offset `0x600000` is **outside the host-visible BAR**. Only ERNIC0 is reachable.

Phase 0 and Phase 1 are the maximum verification we can do **without an RTL rebuild**. They are both CSR-only: they exercise the AXI-Lite stack (PCIe → BAR2 → system_config crossbar → rdma_subsystem AXI-Lite slave → ERNIC QCSR/GCSR/PDT), confirm ERNIC is alive, and program QP context to the last step before posting a WQE. They do **not** issue any AXI-MM transactions.

## Scope (what's in, what's out)

| Tested | Not tested |
|---|---|
| BAR2 mmap + address map translation | QDMA AXI-MM bridge (disabled in TCL) |
| ERNIC0 register R/W through the full AXI-Lite chain | ERNIC1 (BAR2 too small to reach `0x600000`) |
| XRNIC reset → enable sequence | WQE fetch from DDR4 or hugepage |
| MAC/IPv4 GCSR programming | CMAC TX/RX of actual RoCEv2 frames |
| PDT write (protection domain) | Completion poll |
| QP context programming in QCSR | End-to-end RDMA WRITE/READ/SEND |
| Plugin `rdma_onic_250mhz` address map crossbar path | packet_classifier `is_rdma` demux |

---

# Phase 0 — ERNIC0 liveness probe (30 min, no dependencies)

## Goal

Prove ERNIC0 is alive on the AXI-Lite fabric. Single C program, ≤40 lines. No Kconfig, no libreconic, no driver changes, no hugepages.

## Prerequisite sanity checks

Run these first and record results (paste into `status.md` under "Phase 0 results"):

```bash
# 1. Confirm driver is unloaded so we own BAR2 exclusively
sudo rmmod onic 2>/dev/null; lsmod | grep onic   # should be empty

# 2. Confirm BAR2 size. Region 2 must be ≥ 4 MB to reach ERNIC0 at offset 0x200000.
sudo lspci -vv -s 82:00.0 | grep -E "Region [0-2]"
# Expected: "Region 2: Memory at ... [size=4M]"
# If size=1M or 2M, the address map crossbar will decode but the BAR window is
# too small — ERNIC0 unreachable. STOP and rebuild with pf0_bar2_size_qdma {8}.

# 3. Confirm Memory/BusMaster enabled.
sudo setpci -s 82:00.0 COMMAND          # bit 1 = memory enable, must be set
```

Driver-unbound is preferred for Phase 0 to avoid any ioremap overlap and because
we want raw reads to land on the fabric deterministically. (Driver being loaded
is also fine — `/sys/.../resource2` mmap works either way — but keep it simple.)

## The probe program

Location: **new file** `rdma_test/phase0_ernic_probe.c`. Link: none (pure libc).

Register offsets to touch, all inside the ERNIC0 window (BAR2 base + `0x200000`):

| Offset (absolute) | Reg | Expected behavior |
|---|---|---|
| `0x220000` | `XRNICCONF` | Non-`0xFFFFFFFF`, stable across 5 reads. PG332 reset value = `0x000000FB`. |
| `0x220004` | `XRNICADCONF` | Writable. Write `0x00000001`, read back, restore original. |
| `0x220070` | `IPV4XADD` | Writable. Write `0xC0A86401` (192.168.100.1), read back. |
| `0x220010` | `MACXADDLSB` | Writable. Write `0x00000A35`, read back. |
| `0x0` (PDT entry 0) | PDT[0].pd_num | Writable. Write `0xDEADBEEF`, read back. |

**Program flow** (reference — write in C):

```c
int fd = open("/sys/bus/pci/devices/0000:82:00.0/resource2", O_RDWR | O_SYNC);
if (fd < 0) die("open resource2");

void *bar2 = mmap(NULL, 0x400000 /*4 MB = current BAR size*/, PROT_READ|PROT_WRITE,
                  MAP_SHARED, fd, 0);
if (bar2 == MAP_FAILED) die("mmap");

volatile uint32_t *r = (uint32_t *)((uint8_t *)bar2 + 0x220000);

// 1. 5 reads of XRNICCONF for stability
for (int i = 0; i < 5; i++) printf("[%d] XRNICCONF = 0x%08x\n", i, r[0]);

// 2. Writable round-trip on XRNICADCONF
uint32_t orig = r[1];  r[1] = 0x00000001;  uint32_t rb = r[1];  r[1] = orig;
printf("XRNICADCONF round-trip: 0x%08x -> 0x00000001 -> read 0x%08x\n", orig, rb);

// 3. IPv4 address reg
r[0x70/4] = 0xC0A86401; printf("IPV4XADD after write: 0x%08x\n", r[0x70/4]);

// 4. PDT entry 0 at absolute BAR2 + 0x200000 + 0x0
volatile uint32_t *pdt = (uint32_t *)((uint8_t *)bar2 + 0x200000);
pdt[0] = 0xDEADBEEF; printf("PDT[0] after write: 0x%08x\n", pdt[0]);

munmap(bar2, 0x400000); close(fd);
```

## Pass criteria

All five checks pass:
1. XRNICCONF reads are non-`0xFFFFFFFF` and stable (same value every read).
2. XRNICADCONF round-trips.
3. IPV4XADD reads back what we wrote (`0xC0A86401`).
4. MACXADDLSB round-trips.
5. PDT[0] reads back `0xDEADBEEF`.

## Failure modes and what each means

| Symptom | Likely cause | Next step |
|---|---|---|
| All reads = `0xFFFFFFFF` | BAR2 not enabled, or ERNIC0 below the plugin's AXI-Lite decode window | Re-check `lspci`, re-check plugin's `system_config_address_map.sv` M13 translation (should decode `0x200000-0x23FFFF` to ERNIC0 slave base 0x0). |
| XRNICCONF reads fluctuate | Not a decode — something else is driving that address, or the IP is under reset | Check PCIe PERST/user-reset from QDMA: `sudo lspci -vv` bus link status. Check MIG calibration — if DDR4 MIG never calibrates, the ERNIC's upstream resets may not release. |
| `mmap` returns `MAP_FAILED` | BAR2 size smaller than our mmap size, or sysfs `resource2` not present | `ls -la /sys/bus/pci/devices/0000:82:00.0/resource*` — should show resource0/1/2 with non-zero sizes |
| Writes fail (read back garbage) but reads are stable | AXI-Lite BRESP = SLVERR silently dropped; most likely the plugin crossbar decoded to a region with no slave | Use `devmem2` (or equivalent) to narrow down which sub-window fails. |
| `bus error` / `SIGBUS` on access | Address decoded outside any slave → AXI-Lite timeout → PCIe completer abort | Check `dmesg` for PCIe AER events. Reduce probe to just offset `0x220000` and bisect. |

## Output to capture

Create `rdma_test/phase0_output.txt` with dmesg + program stdout. Paste into `status.md` under "Phase 0 results" when done.

---

# Phase 1 — libreconic CSR-only bring-up (2-4 hours)

## Goal

Run `libreconic`'s full ERNIC0 init sequence **except** the parts that require AXI-MM (hugepage DMA, WQE fetch). Prove:
- BAR2 mmap works end-to-end through the existing `libreconic` stack.
- `create_rn_dev` + `create_rdma_dev_port` bring-up doesn't hang or blow up.
- XRNIC reset sequence works.
- QP context programming (PDT + QCSR) round-trips.

## Pre-work: surgical patches to libreconic

These are **local hacks** for Phase 1 on the current (RTL-incomplete) bitstream. Track them in `status.md` so they can be reverted once Phase 2 RTL is in place.

### Patch 1 — shrink mmap size to current 4 MB BAR

File: `libreconic/reconic_reg.h`
Current (line 48): `#define RN_SCR_MAP_SIZE  0x00800000`

Change for Phase 1 only:
```c
#define RN_SCR_MAP_SIZE  0x00400000   /* PHASE1_HACK: current bitstream BAR2 = 4MB, ERNIC1 unreachable */
```

Document: only ERNIC0 will be probable. `create_rdma_dev_port(rn_dev, 1)` will return garbage on every register read (addresses ≥ `0x400000` will either wrap, SIGBUS, or hit shifted BOX0).

### Patch 2 — disable `config_rn_dev_axib_bdf` call

File: `libreconic/reconic.c`, line 339.
Current:
```c
// Configure QDMA slave AXI bridge
config_rn_dev_axib_bdf(rn_dev, phy_addr_msb, phy_addr_lsb);
```

Change to:
```c
// PHASE1_HACK: QDMA AXI-MM bridge not present in au200_2cmac_2pf_rdma bitstream.
// These writes would land on QDMA subsystem CSRs at 0x014000+0x2420 etc. which
// DO decode (QDMA subsystem CSR space is 0x012000–0x016FFF) but are NOT the
// bridge registers and may alias to QDMA-internal state. Skip entirely for Phase 1.
// config_rn_dev_axib_bdf(rn_dev, phy_addr_msb, phy_addr_lsb);
fprintf(stderr, "[PHASE1] Skipping QDMA AXIB BDF config — bridge not in RTL\n");
```

### Patch 3 — guard WQE/buffer posting

Any test that calls `rdma_post_send`, `poll_cq_cidb`, `allocate_rdma_buffer(..., dev_mem, ...)`, or writes `DATBUFBA*` / `SQBAi` / `RQBAi` / `CQBAi` is **not safe** on this bitstream. Two options:

- **Recommended**: write a new minimal test `rdma_test/phase1_csr_bringup.c` that only calls the CSR-touching APIs. See "Phase 1 test program" below.
- Alternative: run `rdma_test/write.c` but abort before `rdma_post_send` via an early `return` / `exit(0)` after `allocate_rdma_qp()`.

## Phase 1 test program

Location: **new file** `rdma_test/phase1_csr_bringup.c`. Link against `libreconic.so`.

Flow (function-by-function, ERNIC0 only):

```
1. create_rn_dev("/sys/bus/pci/devices/0000:82:00.0/resource2", &fd,
                 num_hugepages=1, num_qp=4)
   - Opens BAR2, mmaps 4 MB (Patch 1), allocates 1 hugepage (2 MB default),
     mlocks it. Hugepage is allocated but will not be DMA'd — it's only used so
     that later APIs don't null-deref.
   - Skips config_rn_dev_axib_bdf (Patch 2).

2. Optional — spot-check PDT:
     write32_data(rn_dev->axil_ctl, RN_RDMA_BASE_ADDRESS + 0x0, 0xCAFE0001)
     assert read32_data(rn_dev->axil_ctl, RN_RDMA_BASE_ADDRESS + 0x0) == 0xCAFE0001

3. create_rdma_dev_port(rn_dev, port_id=0, num_qp=4)
   - Allocates rdma_dev_t, computes port_offset=0 for port 0.
   - Does NOT touch XRNIC yet (just struct init).

4. open_rdma_dev(rn_dev, mac_lsb, mac_msb, ipv4_addr, udp_port, ...)
   - Writes: XRNICCONF reset, XRNICCONF enable, MACXADD{LSB,MSB},
     IPV4XADD, UDPDESTPORT, ERRBUFBA* (points to hugepage paddr — safe, ERNIC
     won't actually write there unless a fault occurs), INTMASK.
   - All CSR-only. No AXI-MM issued yet.

5. allocate_rdma_pd(rdma_dev, pd_num=1)
   - Writes PDT entry 1 at RN_RDMA_BASE_ADDRESS + pd_num*0x8.
   - Read back to verify.

6. allocate_rdma_qp(rdma_dev, qpid=2, dst_qpid=2, pd=1,
                    sq_psn=0xabd, last_rq_psn=0xabc,
                    qdepth=4, r_key=0x0008, p_key=0x1234,
                    buffer_location=host_mem,
                    sq, cq_ba, rq_ba, cq_db_va, rq_ci_db_va, ...)
   - Writes QP context to QCSR:
       XRNICCONF.QPi_EN, QPCONFi, QPADVCONFi, SQPSNi, LSTRQREQPSNi,
       SQBAi, RQBAi, CQBAi (these take hugepage paddrs — unused until first post),
       CQDBADDi, RQWPTRDBADDi, SQPIi, CQHEADi, DESTQPCONFi, SQHEADi, RQCIi, ...
   - All CSR writes. No AXI-MM issued.
   - Read back every written CSR and verify.

7. dump_registers(rdma_dev, port_id=0)
   - Prints every GCSR + the QP0..3 QCSR block.
   - Visual sanity check.

8. STOP. Do NOT call rdma_post_send, poll_cq_cidb, rdma_recv, anything that
   touches SQ/RQ/CQ memory.

9. Teardown: free(rn_dev->base_buf->buffer) + munmap + close.
```

## Pass criteria

- `create_rn_dev` returns non-NULL, `mmap` succeeds.
- PDT write/read round-trips (spot check).
- `open_rdma_dev` returns without segfault / hang (>30 s timeout is a hang).
- Every CSR we write in step 4–6 reads back exactly what we wrote (or the expected XRNIC-computed value — some bits like QPi_EN may be sticky-RO from GCSR context).
- `dump_registers` output matches the expected PG332 defaults modified by our writes.
- Run program twice back-to-back; second run must succeed (no persistent ERNIC state corruption). If the second run hangs, the XRNIC reset sequence on the first run didn't fully clear state — investigate `open_rdma_dev`'s reset handling.

## Specific CSRs to audit against PG332

If a CSR read-back mismatches what we wrote, cross-reference against Xilinx PG332 (ERNIC Product Guide). Common issues:
- Reserved bits in `XRNICCONF` are RO; only bits [0], [4], [8:13] are writable in v4.0.
- `MACXADDMSB[31:16]` is reserved.
- `IPV6XADDR*` must be written as four 32-bit words even in IPv4-only mode.
- Per-QP regs at `QCSR_BASE + qp_num*0x100` — make sure `qp_num` in libreconic matches the PG332 index (some versions are 1-indexed).

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `mmap` fails with size 4 MB | BAR2 is smaller (e.g. 2 MB from an older build) | Rebuild TCL with `pf0_bar2_size_qdma {4}` or {8}. |
| XRNIC reset hangs (XRNICCONF stays in reset state) | DDR4 MIG not calibrated → ERNIC's upstream reset stuck | Check DDR4 init_calib_complete signal (requires debug probe). Or skip the hardware reset step and see if the rest still works — ERNIC boots to a default state usable for CSR access. |
| Per-QP CSR writes read back as 0 | QPi_EN not set, QCSR gates writes when QP is disabled | Write `QPi_EN = 1` first, then QP config regs. |
| Bus error (SIGBUS) on any offset | Undecoded region inside the 4 MB window | Narrow with bisection. Likely culprits: address map translation bug, or a window we haven't accounted for. |
| Second run hangs | Persistent ERNIC state (QP active, interrupt pending) | Issue `XRNICCONF.global_reset` at program entry before any other access. |

## Output to capture

Create `rdma_test/phase1_output.txt` with program stdout + `dmesg -w` output
captured during the run (look for PCIe AER, QDMA subsystem errors). Include
`dump_registers` output. Paste into `status.md` "Phase 1 results".

---

# Optional — Kernel-side probe (~40 lines)

Independent of Phase 0/1. Adds an `insmod` dmesg line per port confirming ERNIC presence.

File: `open-nic-driver/onic_hardware.c`, in `onic_init_hardware()` **after** line 245 (where `pci_iomap_range` already covers 4 MB):

```c
/* Phase 0 probe — log ERNIC liveness */
if (hw->addr) {
    u32 ernic0_conf = readl((u8 __iomem *)hw->addr + 0x220000);
    dev_info(&pdev->dev, "ERNIC0 XRNICCONF = 0x%08x (expect non-0xFFFFFFFF)\n",
             ernic0_conf);
    /* ERNIC1 at offset 0x620000 is beyond the current 4 MB BAR — skip.
     * Once BAR2 is rebuilt to 8 MB, also:
     *   u32 ernic1_conf = readl((u8 __iomem *)hw->addr + 0x620000);
     *   dev_info(&pdev->dev, "ERNIC1 XRNICCONF = 0x%08x\n", ernic1_conf);
     */
}
```

Pair with a matching bump in `onic_register.h` when BAR becomes 8 MB:
```c
#define SHELL_END  0x800000   /* was 0x400000 — covers ERNIC1 */
```

Trade-off: writes `dev_info` at every probe. No functional risk. Good for
"did my insmod see ERNIC" one-liner feedback without running userspace.

---

# Order of operations

1. **Phase 0** (today): prerequisite checks → write probe → run → record.
2. If Phase 0 passes → **Phase 1** (this week): apply Patches 1–2, write `phase1_csr_bringup.c`, run, record.
3. Optional: land the driver probe. Zero dependency on 0/1 — but easier to verify the driver probe *after* Phase 0 has confirmed the register is readable.
4. **After both pass**: you have high confidence that the AXI-Lite fabric is correct end-to-end. The remaining risk for Phase 2 is purely in the AXI-MM domain (QDMA bridge RTL + DDR4 MIG calibration + ERNIC master wiring).

# When Phase 2 becomes possible

Phase 2 requires a new bitstream with:
1. `qdma_no_sriov_au200.tcl` patched to RecoNIC's config: `en_axi_mm_qdma {true}`, `en_bridge_slv {true}`, `dma_intf_sel_qdma {AXI_MM_and_AXI_Stream_with_Completion}`, `axibar_highaddr_0 {0x000000FFFFFFFFFF}`, `pf0_bar2_size_qdma {8}` (8 MB → covers ERNIC1).
2. `qdma_subsystem.sv` — expose `s_axib_*` (slave from ERNIC via `axi_sys_mem_mux`) and `m_axi_bridge_*` (master from PCIe for host staging).
3. `open_nic_shell.sv:3384` — wire `axi_sys_mem_mux_*` to QDMA `s_axib`, wire QDMA `m_axi_bridge` into the `dev_mem` 4-to-1 crossbar.
4. `onic_register.h` + `onic_hardware.c` — bump `SHELL_END` to `0x800000`.
5. libreconic — revert Patches 1 and 2.

All 4 RTL changes are diff-portable from `RecoNIC/base_nics/open-nic-shell/`.
That's a separate planning document (see `plan.md` for the original integration
plan — it predates the RTL audit and needs a revision once we start Phase 2).
