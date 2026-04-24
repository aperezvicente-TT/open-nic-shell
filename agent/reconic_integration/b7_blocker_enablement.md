# B7 Blocker — Host ↔ DDR4 data path not reachable in v3 bitstream

> **Status (2026-04-23):** B7 design landed (`b7_post_send_recv.md`, 949 lines).
> Code unapplied.  Running the B7 path requires an FPGA architecture change
> — specifically one of the three enablement routes in §3 — because v3
> gives the host CPU zero visibility into DDR4 memory.

---

## 1. The structural problem

### 1.1 Where DDR4 lives

Our shell places DDR4 on ERNIC's internal AXI fabric at AXI base
`0xa350_0000_0000_0000`.  ERNIC reads/writes DDR4 via its own AXI master
for MR backing and SQ/RQ/CQ rings.

### 1.2 What the host sees

PCIe BAR2 (16 MB) maps **only** CSR space:

```
0x000000 - 0x01FFFF   system registers (QDMA/CMAC/sysmon CSRs)
0x300000 - 0x340FFF   CMS + QSPI
0x400000 - 0x4FFFFF   BOX0 plugin (250 MHz clock domain)
0x500000 - 0x5FFFFF   BOX1 plugin (322 MHz clock domain)
0x800000 - 0x9FFFFF   ERNIC0 CSR + PDT (2 MB)
0xA00000 - 0xBFFFFF   ERNIC1 CSR + PDT (2 MB)
```

**There is no DDR4 window in BAR2 or any other BAR.**

### 1.3 Consequence for B7

B7 needs to write ERNIC SQ WQEs into DDR4 before ringing the SQPIi
doorbell (PG332 §5.1 + §7).  The driver has no mapping that
`memcpy_toio()` could aim at DDR4.  So:

- `post_send` cannot place a WQE in the SQ ring.
- `post_recv` cannot initialize the RQ scatter buffer.
- Payload staging (`get_user_pages_fast` + copy) would go anywhere — DDR4 is
  the one place we can't reach.

B5 and B6 are unaffected because they only touched CSR (programming BA/
MSB register pointers to DDR4 addresses); they never actually dereferenced
those addresses.  B7 is the first verb that has to read/write DDR4 content,
and that's where the gap opens.

### 1.4 Current v3 QDMA config (the knob that was deliberately off)

`src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl`:

```
CONFIG.en_axi_mm_qdma     {false}    ← disables the QDMA AXI-MM DMA engines
CONFIG.en_bridge_slv      {true}     ← enables s_axib (card→host DMA) — NOT wired
CONFIG.axibar_notranslate {false}
CONFIG.axibar_highaddr_0  {0x000000FFFFFFFFFF}
```

**`en_axi_mm_qdma=false` is what foreclosed the DDR4 path.**  That flag
controls whether the QDMA IP instantiates its AXI-MM master (`m_axi_*`)
which, in RecoNIC's reference design, wires into a `dev_mem` crossbar
that terminates at DDR4.  Setting it back to `true` restores that path.

---

## 2. What already exists (partial Tier 1b work)

- `agent/reconic_integration/tier1b_qdma_audit.md` — 433-line plan from the
  Tier 1a→1b transition, with **Q1–Q4 answered**, IP-config edits staged
  (uncommitted working-tree), and exact wrapper/subsystem insertion lines
  identified for the `s_axib` graft.
- `pg302-qdma.md` (10,324 lines, in `~/Downloads/XilinxAmdDownloads/`)
  fully indexed.
- RecoNIC reference at `~/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/`
  has the canonical wiring — its `qdma_no_sriov_au200.tcl` has both
  `en_axi_mm_qdma=true` and `en_bridge_slv=true`, and `open_nic_shell.sv`
  routes `m_axi_*` through a 4:1 crossbar into DDR4.

So the enablement isn't starting from scratch — most of the plumbing is
already either designed or exists in RecoNIC to copy.

---

## 3. Three enablement routes

| Route | What it adds | Driver impact | Fits our B5/B6 as-built? | Bitstream rebuild | Effort |
|-------|------|---------------|--------------------------|-------------------|--------|
| **X.  `en_axi_mm_qdma=true` + `m_axi_*` → dev_mem crossbar → DDR4** | QDMA MM DMA engines become usable; BAR2 gets an AXI-Bridge-Master window that lands in DDR4; host can also submit H2C descriptors for async DMA | small — driver `ioremap`s the DDR4 BAR and `memcpy_toio`s | **yes, unchanged** | **yes** | 1–2 days shell + 1 day driver |
| **Y.  Y reuses RecoNIC's existing drivers (`/dev/reconic-mm`)** | Same IP config as Route X, but bring up the RecoNIC-style userspace interface (mmap of DDR4 via a char device) | small — port reconic_mm driver OR load it alongside onic.ko | yes, unchanged | same as X | 1–2 days shell + 0.5 day driver integration |
| **Z.  `s_axib` graft (Tier 1b as originally scoped)** | Queues live in **host memory**; ERNIC reads WQEs via s_axib through PCIe; no DDR4 staging | **LARGE** — B5's DDR4-backed MR model becomes host-memory MRs.  Driver refactors allocator + all verb paths | **no — invalidates B5's "DDR4-only MR" design call** | yes (35-port graft, fully documented in tier1b_qdma_audit.md) | 1 day shell + 3–5 days driver refactor |

### Routes X and Y are almost identical in bitstream terms

Both flip `en_axi_mm_qdma=true`.  The difference is purely driver-side:

- **X.** Add a new BAR (e.g., BAR4) of size matching our DDR4 (16 GiB) and
  pciebar2axibar it to `0xa350_0000_0000_0000`.  Driver `ioremap`s the new
  BAR; `memcpy_toio(dst, src, len)` just works.  Simplest.
- **Y.** Reuse RecoNIC's `reconic-mm` character-device driver that exposes
  DDR4 via `mmap(/dev/reconic-mm)`.  Same FPGA config; skip writing our own
  BAR-mapping code.

### Route Z is real but undoes design decisions

If we pick Z, the "single MR per PD (DDR4-backed)" invariant in B5 pivots
into "single MR per PD (host-memory kmalloc, dma_map-ed, given to ERNIC
via s_axib)".  That's more production-shaped — it mirrors how ConnectX
works — but it's a ~week of driver refactor and re-verifies all of
B5/B6 downstream.

---

## 4. Recommendation

**Pick Route X (new MMIO BAR for DDR4).**  Rationale:

1. **Smallest delta from current state.**  Flip one TCL config flag, add
   one BAR config, resize BAR table.  Everything else — CSR path, ERNIC
   instances, plugin RTL, driver ib_device — unchanged.
2. **Doesn't invalidate B5/B6.**  DDR4-backed MRs stay the model, B7 just
   gets a way to write them.
3. **Matches the B7 design doc.**  The `CONFIG_ONIC_DDR4_MMIO_WINDOW`
   branch the agent wrote is exactly what Route X enables.
4. **Can be downgraded to Route Y trivially** if we want to skip writing
   BAR-mapping driver code — install `reconic-mm.ko` alongside `onic.ko`.
5. **Doesn't foreclose Route Z later.**  If we grow to "host-memory
   MRs" for real production, the s_axib graft is still available (and
   is incrementally useful anyway for ERNIC→host bursts).

### 4.1 What Route X actually requires

**Bitstream side (half a day + Vivado build time):**

1. In `qdma_no_sriov_au200.tcl`:
   - `en_axi_mm_qdma {true}`
   - Add a new BAR:  `pf0_bar4_type_qdma {AXI_Bridge_Master}`,
     `pf0_bar4_size_qdma {16384}` (16 GiB), `pf0_bar4_prefetchable_qdma {true}`.
   - Add `pciebar2axibar_4 {0xa350000000000000}` (new BAR maps to DDR4 AXI base).
2. In `qdma_subsystem_qdma_wrapper.v` + `qdma_subsystem.sv`:
   - Wire `m_axi_*` out of the QDMA IP (PG302 Table 13).  ~20 port
     declarations.  Copy verbatim from RecoNIC's wrapper, restricted to
     what our shell consumes (the AXI-4 variant, not AXI-Stream).
3. In `open_nic_shell.sv`:
   - Instantiate a `smartconnect` (or basic crossbar) that takes QDMA's
     `m_axi_*` AND our dev_mem output to DDR4.  For a single QDMA/single
     DDR4 this can be a 1-to-1 wire, no actual crossbar needed.
4. Rebuild bitstream (4–8 hours Vivado).
5. Reflash.

**Driver side (~half a day):**

1. In `onic_hardware.c` / capacity init, `pci_iomap` BAR4 into
   `priv->hw.ddr_addr`.
2. In `onic_ddr_alloc.h`, add the `void __iomem *` pointer to the pool.
3. In `b7`'s `onic_ddr_memcpy_to()` (already sketched), replace the
   `CONFIG_ONIC_DDR4_MMIO_WINDOW` stub with `memcpy_toio(ddr_addr + off,
   src, len)`.

**Total estimate: 2 working days + ~6 hours of Vivado build time.**

### 4.2 What this unblocks

After Route X lands:
- B7 (post_send / post_recv) becomes applicable.
- Phase 2a (RDMA WRITE DDR4 loopback, the legacy libreconic test) becomes
  viable as a secondary smoke test.
- B11 perftest becomes testable end-to-end (with B7/B8 also landed).
- Future Track C gateway work gains a real host↔DDR4 path even when ERNIC
  is the RDMA endpoint.

---

## 5. Intermediate paths worth mentioning

### 5.1 Land B7 code with `-EOPNOTSUPP` fallback

The B7 design doc's `#ifdef CONFIG_ONIC_DDR4_MMIO_WINDOW` branch already
has this built in.  If we apply the patch without defining that flag,
`onic_post_send` compiles, loads, and returns `-EOPNOTSUPP` at runtime.

Why you might do this: it makes the full stack shape visible in the
repo.  B8 (`poll_cq`) can be designed and landed in parallel; once
Route X lands, flipping the flag turns everything on.

Why you might not: it's a stub that will bitrot if the real design
diverges from the sketch.  Better to apply after the bitstream is
actually enabled.

### 5.2 Stick with the v3 bitstream; defer Track B data path indefinitely

- Foundation (F1–F5, F7) + B3/B3.5/B5/B6 are a real deliverable on their
  own: a RoCE-capable `ib_device` that advertises correctly and handles
  all verbs up through state transitions.  Useful for:
  - Validating the kernel + userspace stack against an existing ibverbs peer
    (apps see the device, enumerate, fail cleanly at post_send).
  - Training + demo use (`ibv_devinfo` on the FPGA is nontrivial).
- No Track C (gateway, needs data path) or Track D (TT↔TT, same) possible
  without this.
- All real RDMA traffic tests blocked forever.

Calling this out as an option for completeness.  Not recommended.

---

## 6. Decision needed

Which route, and who owns the bitstream rebuild?

1. **Route X + immediate execution** — rebuild bitstream this week,
   unblock B7+B8+B11.
2. **Route Z + schedule refactor** — keep v3, plan the s_axib+host-memory
   refactor; ~2 weeks of work (bitstream graft + driver redesign).
3. **Pause Track B entirely at B6** — commit foundation+skeleton, declare
   Track B data path requires TT-side enablement decision first.

My vote: **Route X**.  Small, reversible, preserves all work to date,
gives us a real data-path test in ~2 days.

---

## 7. Session parking notes

State as of 2026-04-23:

- `open-nic-driver`: B6 committed (`0eb3448`).  B7 design not applied.
- `libonic-provider`: B6 committed (`ec67c06`).  B7 stubs still EOPNOTSUPP.
- `open-nic-shell`: design docs committed (`f2c9c39`).  B7 + B7-blocker docs
  not yet committed.
- All verified live via `ibv_rc_pingpong -d onic_0100 -g 0 -r 16`:
  reaches `modify_qp RESET→INIT`, succeeds; blocks at `post_recv` stub.

Tier 1b audit is the next session's entry point for Route X — its
insertion-point list is authoritative.

---

## References

- `b7_post_send_recv.md` — B7 design doc (949 lines, code sketch included).
- `tier1b_qdma_audit.md` — prior work on the `s_axib` route; maps
  directly onto Route Z, provides canonical port lists for either
  route.
- `pg302-qdma.md` — PG302 v5.1 extracted markdown in
  `~/Downloads/XilinxAmdDownloads/pcie/`.
- RecoNIC AU200 reference: `~/mpi-shfs/fpga/RecoNIC/base_nics/open-nic-shell/`.
- `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` — the flag that
  was deliberately turned off.
