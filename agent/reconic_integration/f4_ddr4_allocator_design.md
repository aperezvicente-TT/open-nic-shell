# F4 — DDR4 Staging Buffer Allocator Design

**Status:** design only — code lands in a follow-up after F7 (QP lifecycle).
**Target:** `onic` driver, both ERNIC instances (port 0 and port 1).
**Scope:** carve the U200's **single 16 GiB DDR4 RDIMM** (MTA18ASF2G72PZ-2G3,
per `dev_mem_ddr4_controller_au200.tcl`) into ERNIC-usable regions (MR
backing, per-QP SQ/RQ/CQ, always-on error/retx buffers) and give the driver
a tiny allocator that all three tracks (B restricted NIC, C gateway, D TT↔TT)
can drive with the same API.

> **Update 2026-04-23**: `phase_f4_ddr4_address_probe` confirmed 8/8 corner
> round-trips (0 GiB / 4 GiB−4K / 8 GiB / 16 GiB−4K on both ERNIC0 and
> ERNIC1) against `DATBUFBA`/`DATBUFBAMSB`.  Full 34-bit / 16 GiB address
> space is reachable by both ERNICs.  Earlier pessimistic 8 GiB-per-ERNIC
> budget is lifted — allocator commits to the full 16 GiB DDR4 shared
> between both ERNICs.  The size-class tiers below can be doubled (or the
> reserved XXL 4 GiB slot promoted to active use).

Assumes `f1_register_map_audit.md` (ERNIC register offsets), `phase1b_ernic_data_plane_config.c`
(working 64-bit BA round-trip), and the `sys_mem_5to2_axi_crossbar` config
(`src/utility/vivado_ip/sys_mem_5to2_axi_crossbar.tcl`) as ground truth.

---

## 1. Goals and non-goals

**Goals**
1. A single contiguous byte-offset map for the full DDR4 visible to each ERNIC.
2. A minimal kernel-side allocator with deterministic fast-path (O(1) per size class).
3. One API that feeds all three tracks (B/C/D) and respects the one-MR-per-QP ERNIC constraint.
4. All PG332 alignment rules enforced at allocation time, not at register-write time.
5. Audit-friendly: the map is static enough that a probe tool can verify it on live hardware.

**Non-goals**
1. Host-direct access to DDR4 (dev_mem path is not wired in this bitstream).
2. Shared-memory semantics between ERNIC0 and ERNIC1 (they share the same DDR4 through the
   crossbar but their allocations are disjoint — see §2 for the split).
3. Ongoing compaction / defrag — we accept fragmentation and reboot if a workload needs a reset
   (see §6).
4. MR refcounting for shared MRs — one MR per QP is the hard rule; no aliasing.

---

## 2. DDR4 address map layout

### 2.1 Crossbar base (verified)

`sys_mem_5to2_axi_crossbar.tcl` lines 45–48:

```tcl
CONFIG.M00_A00_ADDR_WIDTH {52}           # M00 = PCIe/QDMA leg (host → DDR4)
CONFIG.M01_A00_ADDR_WIDTH {36}           # M01 = DDR4 MIG leg, 64 GiB window
CONFIG.M00_A00_BASE_ADDR {0x0000000000000000}
CONFIG.M01_A00_BASE_ADDR {0xa350000000000000}
```

The M01 base `0xa350_0000_0000_0000` is where ERNIC's AXI masters hit the DDR4 MIG. The
ERNIC 64-bit BA registers (DATBUFBA / SQBAi / RQBAi / etc.) accept this base in their MSB
halves — `phase1b_ernic_data_plane_config.c` confirms round-trip with
`DDR4_HI = 0xa3500000` (and LSB = the actual byte offset inside DDR4).

**So: any `uint64_t` DDR4 address used in ERNIC BAs has the form**

```
addr = 0xa350_0000_0000_0000 | (offset & 0x0000_0000_FFFF_FFFF)
```

The 36-bit M01 window gives 64 GiB of address space; the physical DDR4 is 16 GiB
(2 × 8 GB SODIMM). So only `offset ∈ [0, 0x4_0000_0000)` is valid. Offsets above 16 GiB
will land on unmapped DRAM; keep the allocator below that ceiling.

> **TBD at bring-up:** confirm U200 DDR4 SODIMM population. Some U200 SKUs are shipped
> single-DIMM. A probe tool (see §9.b) should read/write +0x2_0000_0000 (8 GB) and
> +0x3_FFFF_F000 (~16 GB) and flag if either aliases back to 0. Until then, budget the
> allocator at the pessimistic **8 GiB** (single SODIMM) and treat the upper 8 GiB as
> "reserved — verify DIMM2 present."

### 2.2 Per-ERNIC split

Both ERNICs share the same 16 GiB window through the crossbar. We split the window
so each ERNIC owns a disjoint half. This avoids any ambiguity about cross-ERNIC
writes to the same address.

```
0x0_0000_0000  +-------------------------------+
               |  ERNIC0 region — 8 GiB (or 4  |
               |  GiB if DIMM2 absent)         |
0x2_0000_0000  +-------------------------------+
               |  ERNIC1 region — 8 GiB (or 4  |
               |  GiB reserved)                |
0x4_0000_0000  +-------------------------------+
```

The split is arbitrary but reflected in the driver: `ddr_region_for_ernic(id)` returns
`{base: id * 0x2_0000_0000, len: 0x2_0000_0000}`.

### 2.3 Per-ERNIC tier layout

Within each ERNIC's 8 GiB region, three tiers:

| Tier | Offset (relative to ERNIC base) | Size | Contents |
|---|---|---|---|
| **Infrastructure** | 0x0000_0000 .. 0x0004_0000 | 256 KiB | DATBUF (retx), REQERRBUF, FATALERRBUF, RESPERRBUF |
| **Per-QP queues**  | 0x0004_0000 .. 0x0040_0000 | 3.75 MiB | 256 × (SQ + RQ + CQ) rings |
| **MR pool**        | 0x0040_0000 .. 0x2_0000_0000 | ~8 GiB – 4 MiB | MR backing, sliced into size classes |

Absolute 64-bit addresses (example for ERNIC0, infrastructure tier):

```
DATBUFBA    = 0xa350_0000_0000_0000
REQERRBUFBA = 0xa350_0000_0001_0000
FATALERRBUFBA = 0xa350_0000_0002_0000
RESPERRBUFBA  = 0xa350_0000_0003_0000
```

ERNIC1 adds `+0x2_0000_0000` to the LSB half (which, since the LSB is only 32 bits in
the LSB register, requires the MSB to also change — ERNIC1 MSB becomes `0xa350_0002`).
This is safe: the MSB register is 32 bits wide and the round-trip probe already
confirms arbitrary MSBs latch correctly.

### 2.4 Infrastructure-tier table (per ERNIC)

| Register | Offset in tier | Size | PG332 field |
|---|---|---|---|
| DATBUFBA | 0x0_0000 | 128 KiB | §5.9 — retx DMA buffer. `DATBUFSZ = {NBUFS=32, BUFSZ=4096}` |
| REQERRBUFBA | 0x2_0000 | 64 KiB | Request-error packet ring. `REQERRBUFSZ = {256 entries, 256 B each}` |
| FATALERRBUFBA | 0x3_0000 | 16 KiB | `FATALERRBUFSZ = {64 entries, 256 B each}`. Fatal-path only. |
| RESPERRBUFBA | 0x3_4000 | 16 KiB | `RESPERRBUFSZ = {64 entries, 256 B each}`. Response-error path. |
| *reserved* | 0x3_8000 .. 0x4_0000 | 32 KiB | padding / future use |

All four bases are 4K aligned (safest superset of the 32-B / 256-B / implicit-4K
rules in PG332 §3). Sizes are suggestions; they are configured via the `*SZ`
companion registers, not by how many bytes the allocator hands out — but the
allocator must not stomp on the footprint.

### 2.5 Queue-tier layout

256 QPs per ERNIC (matches our `XRNIC_CONF_QP_EN` budget and is the practical limit
given BAR2 space per QCSR register fanout). Per-QP rings:

| Ring | Size | Alignment (PG332 §5.10) | Offset within per-QP slot |
|---|---|---|---|
| SQ  | 4 KiB | 32-B (SQBAi[31:5])  | 0x0000 |
| RQ  | 4 KiB | 256-B (RQBAi[31:8]) | 0x1000 |
| CQ  | 4 KiB | 32-B (CQBAi[31:5])  | 0x2000 |
| pad |       |                    | 0x3000 |

Per-QP slot size = 16 KiB. 256 QPs × 16 KiB = 4 MiB — rounded up the tier to 4 MiB
minus the infrastructure overhead (so 3.75 MiB usable; if we push to 240 QPs we stay
comfortably under).

Slot `q` for ERNIC `e`:

```
slot_base(e, q) = ernic_base(e) + 0x0004_0000 + q * 0x4000
SQBA(e, q) = slot_base(e, q) + 0x0000
RQBA(e, q) = slot_base(e, q) + 0x1000
CQBA(e, q) = slot_base(e, q) + 0x2000
```

All three bases are 4 KiB aligned — satisfies all three PG332 alignment requirements
with margin.

### 2.6 MR pool

The bulk: ~8 GiB – 4 MiB per ERNIC. Sliced by size class. See §3.

---

## 3. Allocator data structure

### 3.1 Tiers

1. **Infrastructure slots** — compile-time constants (per-ERNIC). No allocator logic
   needed; the driver just reads `DDR_INFRA_{DATBUF,REQERR,FATALERR,RESPERR}_OFFSET`
   macros.

2. **Queue slab** — fixed-size per-QP slot (16 KiB, see §2.5). Indexed by QP-ID.
   Allocation == QP-ID assignment. Implementation: a per-ERNIC `DECLARE_BITMAP(qp_bits,
   256)` in the ERNIC control struct, protected by a spinlock. `ddr_queue_alloc(ernic)`
   finds a clear bit, returns `(qp_id, slot_base_paddr)`.

3. **MR pool** — variable-size. Size classes, power-of-2:

   | Class | Size | Count (8 GiB pool) | Use case |
   |---|---|---|---|
   | S | 64 KiB | 256 | small MRs, Track B tiny buffers |
   | M | 1 MiB | 128 | Track B medium, Track C gateway rings |
   | L | 16 MiB | 64 | Track C large staging, Track D small pairing |
   | XL | 256 MiB | 16 | Track D pairing |
   | XXL | 4 GiB | 1 | Track D max, single-monster MR |

   Total budget sums: 16 MiB + 128 MiB + 1 GiB + 4 GiB + 4 GiB = **~9 GiB** — fits inside
   the 8 GiB per-ERNIC region *only if* one of XL/XXL is unpopulated. Realistic split
   below, per track priority:

   | Class | Count | Total |
   |---|---|---|
   | S | 256 | 16 MiB |
   | M | 128 | 128 MiB |
   | L | 64 | 1 GiB |
   | XL | 16 | 4 GiB |
   | XXL | 0 (reserved slot — 4 GiB) | — |
   | Total | | 5.14 GiB (fits with ~2.8 GiB headroom) |

   XXL is pre-reserved address space but not default-populated; the driver can promote
   the last 4 GiB to a single XXL MR on request (once — no coalescing).

   Free-list per class: a simple `struct list_head free[MR_CLASS_COUNT]` plus a bitmap
   as a defensive cross-check. Each free node carries `(paddr, class)` — fixed-size,
   no metadata fragmentation.

### 3.2 API

```c
/* ernic_ddr_alloc.h — proposed public shape */

enum ddr_tier {
    DDR_TIER_QUEUE,   /* per-QP SQ/RQ/CQ slot */
    DDR_TIER_MR,      /* MR backing, variable class */
};

enum ddr_mr_class { MR_64K, MR_1M, MR_16M, MR_256M, MR_4G, MR_CLASS_COUNT };

/* Returns the physical DDR4 offset inside the ERNIC's region.  Caller OR-masks
 * 0xa350_0000_0000_0000 when writing the BA MSB/LSB registers. */
int  ddr_alloc(unsigned ernic_id, enum ddr_tier tier,
               enum ddr_mr_class klass /* ignored for QUEUE */,
               u64 *out_paddr, size_t *out_len);

void ddr_free(unsigned ernic_id, u64 paddr);

/* Debug / introspection */
void ddr_dump_map(unsigned ernic_id, struct seq_file *m);
```

`ddr_alloc(DDR_TIER_QUEUE, ...)` returns the 16 KiB per-QP slot; the caller then
computes `+0x0000` / `+0x1000` / `+0x2000` for SQ/RQ/CQ separately.

### 3.3 Track-specific drivers on top

- **Track B:** `ibv_reg_mr(buf, len)` → driver rounds `len` up to the smallest enclosing
  class → `ddr_alloc(DDR_TIER_MR, class)`. If the request exceeds 4 GiB, return `-ENOMEM`
  rather than trying to coalesce. Host `buf` is NOT copied into DDR4 up-front — it's
  the remote's RDMA WRITE landing zone (we do not maintain coherence with host-side
  `buf`; the driver needs to document this in the ibverbs glue as "DDR4 is the real
  MR; host buf is advisory").

- **Track C:** gateway config declares a per-client MR class at init. Typical value:
  `MR_16M`. On CM-REQ arrival, `ddr_alloc(DDR_TIER_MR, MR_16M)` returns one L-class slot
  per client QP.

- **Track D:** orchestrator supplies `(pool_id, size, access)`; driver maps size to a
  class, allocates once per pairing at setup time, holds it until teardown.

---

## 4. Host visibility of DDR4 contents

Blunt: **the host has no direct read path to DDR4 in this bitstream.**

The `M00_A00` leg of the crossbar (host/QDMA-MM → DDR4) is wired in the IP config
(`CONFIG.M00_A00_BASE_ADDR = 0`) but QDMA MM is **not enabled** in the `au200_2cmac_rdma_v3`
build — the `/dev/reconic-mm` node that Phase 2a attempted returns ENODEV. This is
documented in `agent/reconic_integration/phase2a_rdma_write_ddr4_plan.md`.

**Practical consequence for debugging MR contents:** the only way to observe what's in
DDR4 is through ERNIC itself:

1. Post a local RDMA READ against our own MR (loopback QP or second-ERNIC QP).
2. The read response DMAs the MR content back into the SQ/RQ rings (or into a
   second staging MR).
3. Walk the CQ, pick up the CQE, read the data from the ring.

This is invasive and requires a functional QP, so it's unusable for "is my BA register
actually pointing at real DDR?" bring-up. Use the counter-based probe
(`phase_f2_ernic_counters.c`) and RoCE-inject tooling for the BA-correctness question;
fall back to RDMA-READ loopback only for MR content correctness.

**When QDMA MM is eventually enabled** (Tier 1b), this whole section collapses to "mmap
the `/dev/reconic-mm` node and `memcpy`" — keep the API stable so we can swap in the
direct path without touching allocator callers.

---

## 5. Lifecycle per track

### 5.1 Track B — restricted Linux RoCE NIC (ibverbs)

```
app:    ibv_reg_mr(buf, len)
  driver: pd = ernic_pd_alloc()
  driver: class = class_for(len)
  driver: (paddr, plen) = ddr_alloc(ernic_id, DDR_TIER_MR, class)
  driver: pdt_idx = pdt_alloc(pd, paddr, plen, rkey, access)
  driver: when QP transitions to RTS, write QCSR_PDi(qp) = pdt_idx
```

On `ibv_dereg_mr`: driver must first confirm no QP binds this PDT entry
(enforced by `ibv_destroy_qp` landing first). Then `pdt_free(pdt_idx)`,
`ddr_free(paddr)`.

### 5.2 Track C — gateway

```
at gateway init:
  for each client slot c in config:
    (paddr, plen) = ddr_alloc(ernic_id, DDR_TIER_MR, MR_16M)
    gw_slots[c] = { paddr, plen, rkey=c+base_rkey, pdt_idx=pdt_alloc(...) }

on CM-REQ from external host for client slot c:
  qp = ddr_queue_alloc(ernic_id)   # per-QP SQ/RQ/CQ slot
  configure QP with gw_slots[c].pdt_idx   (one MR per QP — reuses class pool)
  send CM-REP
```

### 5.3 Track D — TT↔TT

Orchestrator-driven, static at bring-up:

```
orchestrator_msg(pair_id, size, access):
  class = class_for(size)
  (paddr, plen) = ddr_alloc(ernic_id, DDR_TIER_MR, class)
  (qp, slot)   = ddr_queue_alloc(ernic_id)
  pdt_idx      = pdt_alloc(pd_tt, paddr, plen, rkey_of(pair_id), access)
  program QP to peer, QCSR_PDi(qp)=pdt_idx
  report back (qp_id, rkey, paddr) to orchestrator so peer can WRITE here
```

---

## 6. Failure modes

### 6.1 Fragmentation across size classes
Accepted. The class counts in §3.1 are sized for our worst-case workload; we never
coalesce or promote between classes. If a workload exhausts a class while another is
idle, we report ENOMEM and the operator adjusts compile-time class counts and reloads
the driver.

### 6.2 Allocator-vs-ERNIC race
If the driver calls `ddr_free` while ERNIC still has in-flight DMA to/from that
address, ERNIC writes corrupt DDR4 (now belonging to someone else). **Rule:** driver
must drive the QP to state ERR + drain CQ + wait for any outstanding WQE completion
before calling `ddr_free` on that QP's MR. The F7 QP-lifecycle header will own the
drain logic; `ddr_free` assumes it was called.

Defensive: `ddr_free` poisons the free-listed region with `0xDEADBEEF` pattern
(via an RDMA WRITE from a scratch QP) before re-issuing it. Optional, gated on a
debug flag.

### 6.3 Host-crash / driver-reload recovery
DDR4 content persists across host reboot. ERNIC internal state persists across host
reboot only if FPGA power is maintained and no `pci_reset_function` is issued. Allocator
metadata is in-memory only — on driver reload it's gone.

**Reload path:** driver treats DDR4 as scratch, re-initializes the full allocator map,
reprograms all infrastructure BAs, and assumes no QP survives a reload. Any in-flight
RDMA peers will see their QPs go dead and must re-establish via CM. This is the same
behavior as mainline mlx5 / i40iw on driver reload; no special handling needed.

### 6.4 DDR4 ECC errors
Reported by the MIG IP via AXI interrupts (uncorrectable → system error). ERNIC's
FATALERRBUF captures *packet-level* fatals (received malformed, etc.), not DRAM
errors. If MIG flags an uncorrectable error on a DATBUF read during retx, ERNIC will
emit a fatal and the driver must tear down all QPs on that ERNIC and re-init.

No scrubbing or live-correction plan here — if we need that, it's a separate MIG-ECC
handler task.

---

## 7. Implementation sketch

### 7.1 Files to add

1. `onic/src/ernic/ernic_ddr_alloc.h` — public API above, plus `struct ernic_ddr_region`
   and per-ERNIC state embedded in `ernic_device`.
2. `onic/src/ernic/ernic_ddr_alloc.c` — the two-tier allocator (bitmap for QUEUE,
   free-list-per-class for MR). ~300 lines total.
3. `onic/src/ernic/ernic_ddr_map.h` — compile-time offset macros:

   ```c
   #define DDR_INFRA_DATBUF_OFF        0x00000000
   #define DDR_INFRA_REQERR_OFF        0x00010000
   #define DDR_INFRA_FATALERR_OFF      0x00020000
   #define DDR_INFRA_RESPERR_OFF       0x00030000
   #define DDR_QUEUE_TIER_OFF          0x00040000
   #define DDR_QUEUE_SLOT_SIZE         0x00004000   /* 16 KiB */
   #define DDR_MR_TIER_OFF             0x00400000
   #define DDR_ERNIC_REGION_SIZE       0x200000000ULL  /* 8 GiB */
   #define DDR4_MSB_ADDR               0xa3500000U
   ```

### 7.2 Data structures (sketch)

```c
struct ernic_ddr_region {
    u64 base_offset;                    /* 0 for ERNIC0, 0x2_0000_0000 for ERNIC1 */
    DECLARE_BITMAP(qp_bits, 256);
    spinlock_t qp_lock;

    struct list_head mr_free[MR_CLASS_COUNT];
    unsigned         mr_free_count[MR_CLASS_COUNT];
    spinlock_t mr_lock;

    /* compile-time map of (class, offset, count) lives in .c */
};
```

Free-list node is 16 B; cheapest per-class overhead is S-class (256 × 16 B = 4 KiB);
total per-ERNIC metadata comfortably fits in one page.

### 7.3 Interaction with other Fs

- **F7 (QP lifecycle):** `ddr_queue_alloc` is called from F7's `ernic_qp_create`.
  `ddr_free` is called from F7's `ernic_qp_destroy` *after* drain. F7 owns the
  QP-ID ↔ slot mapping; the allocator just hands out slot addresses.
- **F1 / F2 / F3 register audit:** the allocator consumes register definitions
  (SQBAi etc.) through `reconic_reg.h` — no direct edits needed beyond possibly
  adding `#define XRNIC_NUM_QP 256` somewhere shared.
- **F5 (if/when QDMA MM enabled):** allocator is unchanged; `ddr_dump_map` gains a
  `/dev/reconic-mm`-backed read path.

---

## 8. Open questions / TBDs

1. **Actual DDR4 capacity on the U200 board.** 8 GB vs 16 GB. Budget conservatively
   for 8 GB until a probe confirms. `verify at bring-up via a write/read
   probe at +0x2_0000_0000 and +0x3_FFFF_F000`.
2. **Does ERNIC tolerate concurrent DMA masters on the same DDR4 region (i.e.,
   ERNIC0 writing a byte while ERNIC1 reads the adjacent word)?** Current design
   disjoint-splits to avoid this. If we later want cross-ERNIC sharing for some
   pairing pattern, *FAE query — coherence + ordering guarantees across ERNIC
   instances behind the 5→2 crossbar*.
3. **Track C backend-fabric DMA path.** If the backend-fabric-to-TT link is a
   separate AXI master (not ERNIC) writing into the Track-C staging ring, it must
   be arbitrated by the crossbar or routed through ERNIC. **Depends on C1 backend-
   fabric spec — block F4 code landing on resolving this.**
4. **REQERRBUFSZ / FATALERRBUFSZ / RESPERRBUFSZ tuning.** PG332 doesn't prescribe
   depth; our numbers in §2.4 are plausible-default. Revisit once stress test in
   F9 shows typical fill depth.
5. **MR poisoning on free** (§6.2). Worth the debug flag? Possibly noisy under
   tear-down storms.

---

## 9. Concrete next code steps

a. **Write `ernic_ddr_map.h`** with the offset macros in §7.1. Zero logic, just
   constants. Can be reviewed standalone.

b. **Write a probe tool** `phase_f4_ddr_map_probe.c` using the
   `phase_f2_ernic_counters.c` pattern: for each ERNIC, for each of the four
   infrastructure offsets, write the BA registers, then RDMA-WRITE a pattern
   from a scratch QP to the first byte, read it back via RDMA READ, confirm.
   Goal: verify the map on live hardware before any kernel code depends on it.
   Also probes `+0x2_0000_0000` and `+0x3_FFFF_F000` for the DIMM-population
   question (§8.1).

c. **Write `ernic_ddr_alloc.{h,c}`** with the API in §3.2. ~300 lines. Unit-test
   by running `ddr_alloc` / `ddr_free` in a tight loop with a fake `ernic_id` and
   no hardware touch; validate bitmap/free-list invariants.

d. **Integrate with F7 QP lifecycle** — replace whatever placeholder F7 uses for
   queue-region allocation today with `ddr_queue_alloc`.

e. **Integrate with Track B PDT management** — replace any "hardcoded MR at
   0xa3500000_00001000" in ibverbs glue with `ddr_alloc(DDR_TIER_MR, class)` +
   `pdt_alloc`.

f. **Add `ddr_dump_map` to the driver's debugfs** so operators can see the
   fill state of each tier without rebuilding.
