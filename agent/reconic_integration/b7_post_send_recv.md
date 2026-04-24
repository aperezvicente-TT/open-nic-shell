# B7 — post_send / post_recv with ERNIC WQE build on the fast path

Design doc + patch SKETCH.  Sibling of B3/B5/B6; lands real
`ib_device_ops.post_send` and `.post_recv` in `onic_ib.c`, and replaces the
libonic stubs so pingpong stops failing at the `post_recv × 16` preamble.

Status flag for every non-trivial structural claim is **VERIFY**.  Do NOT
apply anything until the VERIFY items are either confirmed against PG332
v4.2 section numbers or lowered to an unconditional assertion.  §13 lists
the full set.

---

## 1. Scope, non-goals, acceptance gate

### In scope

- `onic_post_send`: build ERNIC SQ WQE from `struct ib_send_wr` (kernel verb
  signature — B7 uses the kernel-verb path; userspace hits it via
  `ibv_cmd_post_send`), write into the QP's DDR4 SQ ring, then ring the
  per-QP `SQPIi` doorbell.  Opcodes:
  - `IB_WR_SEND` → ERNIC `RNIC_OP_SEND` (`0x02`)
  - `IB_WR_RDMA_WRITE` → `RNIC_OP_WRITE` (`0x00`)
  - `IB_WR_RDMA_WRITE_WITH_IMM` → `RNIC_OP_WRITE_IMMDT` (`0x01`)
  - `IB_WR_RDMA_READ` → `RNIC_OP_READ` (`0x04`)
- `onic_post_recv`: build RQ WQE from `struct ib_recv_wr`, write it into
  DDR4 RQ ring at the driver-tracked producer index, then advance the
  hardware's RQ producer using the ERNIC memory-mapped handshake
  (`STATRQPIDBi`, offset `0x9C`).  See §6 and the §13 VERIFY on this —
  there is a real ambiguity between HWHSHKDIS mode (which we use) and the
  `RQCIi` consumer pointer.
- Single-SGE only (B5 advertises `max_send_sge=max_recv_sge=1`).
- Payload must either be already resident in the MR's DDR4 backing, or
  copied from the SGL host VA into DDR4 at post time via `get_user_pages()`.
  We pick the latter (§4) for correctness at the pingpong sizes we care
  about, guarded by the B5 cap of 64 KiB/MR.
- Error returns: ring full → `-ENOMEM`; invalid opcode → `-EOPNOTSUPP`;
  QP not in RTS (for post_send) / not in RTR+ (for post_recv) →
  `-EINVAL`; SGL outside the registered MR → `-EFAULT`.  `bad_wr` is set
  on all failures per ibverbs contract.
- Per-QP SW producer-index tracker kept in `struct onic_qp`.  SQPIi/RQCIi
  are treated as write-only doorbells — we never read them back for the
  PI (we do read for debug), matching libreconic's pattern (rdma_api.c
  lines 913–921).

### Out of scope

- `poll_cq` / `req_notify_cq` (B8).  For B7 alone, `ibv_rc_pingpong`
  still fails at `poll_cq` with `-EOPNOTSUPP` — the pingpong run is only
  expected to make it through `post_recv × 16` + modify INIT→RTR→RTS +
  one `post_send`.
- CQE interpretation and drain (B8).
- Atomics (PG332 v4.2 §3 pg 555–570 explicitly lists them as "not
  allowed"); we reject with `-EOPNOTSUPP` unconditionally.
- `IB_WR_SEND_WITH_INV` / `IB_WR_LOCAL_INV` / `IB_WR_REG_MR` / fast-reg
  flow — no-op in B7, `-EOPNOTSUPP`.
- Host-memory DMA into SGL virtual addresses (blocked on B2 s_axib
  path).  B7 copies into DDR4.
- Coalescing / doorbell batching optimization.  B7 rings one doorbell
  after each WR's WQE write.  See §7 VERIFY — we might want to batch.
- B9 CC/CNP handling.

### Acceptance gate

With B7 applied (B8 still a stub), on a two-node pingpong setup:

1. `sudo ibv_rc_pingpong -d onic_0100 -g 0 -r 16 <peer>` on each side.
2. Client drives:
   ```
   alloc_pd  → reg_mr → create_cq → create_qp
   modify_qp RESET→INIT
   post_recv × 16           <-- B7 exercises this
   modify_qp INIT→RTR       <-- B6
   post_send (one WR)       <-- B7 exercises this
   modify_qp RTR→RTS        <-- B6 (pingpong does this after first recv
                                posted too, depending on cycle)
   poll_cq                  <-- still fails with -EOPNOTSUPP until B8
   ```
3. `dmesg` shows per-WR trace lines from `onic_post_send` and
   `onic_post_recv`.
4. `ethtool` / phase F2 counters: `RN_RDMA_GCSR_INSRRPKTCNT` at
   `0x10_0100` increments on the receiver side,
   `RN_RDMA_GCSR_OUTIOPKTCNT` at `0x10_0108` increments on the sender
   side, confirming ERNIC actually consumed the WQE and produced a
   wire packet.
5. `WQEPROCSTS` at `0x10_0124` shows a non-zero count-of-WQEs-processed
   in bits [31:16].
6. No WARN/BUG from kernel path; no `pr_info_ratelimited` complaining
   about ring full / invalid SGL on the happy path.

### Why this order (B7 before B8)

The pingpong preamble rings SQPIi 16 times before any CQE is expected,
so `post_recv` must actually succeed end-to-end before B8 can be
exercised at all.  Posting the first `post_send` also happens before
the app reaches `poll_cq`, so B7 is a necessary prerequisite for B8
validation.  B7 in isolation is testable via the phase-F2 counters
(item 4) even without B8 — that's the explicit unit test for this
subtask.

---

## 2. ERNIC WQE layout (SQ + RQ)

### 2.1 Send Queue WQE — confirmed 64 B

**Source: PG332 v4.2 §3 Table 2, pg332-ernic-4.2.md lines 585–608.**

`libreconic/rdma_api.h:138` already has this as `struct rdma_wqe_t`.
Match it exactly — the bit field positions below come verbatim from
PG332 Table 2.

| Bits     | Field     | Bytes | Notes (PG332 Table 2)                              |
|----------|-----------|-------|----------------------------------------------------|
| [15:0]   | WRID      | 2     | 16-bit, truncated from `ibv_send_wr.wr_id`         |
| [31:16]  | reserved  | 2     | zero                                               |
| [95:32]  | LADDR     | 8     | local buffer DDR4 address, little-endian 64-bit    |
| [127:96] | LENGTH    | 4     | payload length                                     |
| [135:128]| OPCODE    | 1     | see §3                                             |
| [159:136]| reserved  | 3     | zero                                               |
| [223:160]| ROFFSET   | 8     | remote buffer DDR4 address (WRITE/READ only)       |
| [255:224]| RTAG      | 4     | remote key (WRITE/READ only)                       |
| [383:256]| SDATA     | 16    | inline SEND data (payload ≤ 16 B)                  |
| [415:384]| IMMDT     | 4     | immediate data (WRITE_WITH_IMM / SEND_WITH_IMM)    |
| [511:416]| reserved  | 12    | zero                                               |

WRID is 16-bit, not 64-bit as the scope hint suggested.  **Concrete:
truncate `wr->wr_id` to 16 bits; keep the full 64-bit cookie in a
driver-side shadow table indexed by (qp_num, sq_slot) so the B8 CQE
hander can recover it.**  Shadow table sizing: `sq_depth` entries per
QP, allocated in `create_qp`, freed in `destroy_qp`.

Driver-side mirror struct we will reuse (the existing libreconic
userspace struct — same bit layout, re-emitted in kernel header so we
are not pulling `<stdint.h>` into the kernel):

```c
/* onic_ib.h (B7 addition) — DO NOT include libreconic/rdma_api.h from
 * kernel side; it pulls stdint + ibverbs-unfriendly headers. */
struct __packed onic_sq_wqe {
    __le16 wrid;                 /* truncated from wr->wr_id */
    __le16 reserved0;
    __le32 laddr_lo;             /* bytes 4..7  */
    __le32 laddr_hi;             /* bytes 8..11 */
    __le32 length;               /* bytes 12..15 */
    __le32 opcode;               /* only byte 16 used; [31:8] MBZ */
    __le32 roffset_lo;           /* bytes 20..23 */
    __le32 roffset_hi;           /* bytes 24..27 */
    __le32 rtag;                 /* bytes 28..31 — remote key (rkey) */
    __le32 sdata[4];             /* bytes 32..47 — inline SEND ≤ 16 B */
    __le32 immdt;                /* bytes 48..51 */
    __le32 reserved1[3];         /* bytes 52..63 */
};
static_assert(sizeof(struct onic_sq_wqe) == 64, "SQ WQE must be 64B");
```

**VERIFY (V1)**: PG332 Table 2 lists reserved bits 136..159 as 3 bytes,
but our 32-bit field ordering puts `opcode` as a full u32 at byte 16,
which means bits 136..159 are the high 24 bits of that u32.  We zero
them.  That matches `rdma_api.h` exactly.  Keep as-is unless a bring-up
trace shows ERNIC requires the reserved nibble structured differently.

**VERIFY (V2)**: The ROFFSET field is labeled "Remote offset address"
in PG332 Table 2.  libreconic uses it as a full 64-bit remote DDR4 VA
(see `rdma_api.c:826-827`).  B7 follows the libreconic convention —
stuff `wr->wr.rdma.remote_addr` directly.  This is the same reg/field
ERNIC decodes for RDMA WRITE / READ destination.

### 2.2 Receive Queue WQE — 256 B per slot

**Source: PG332 v4.2 §3 "RDMA Queues" + Table 10 (Memory Requirement),
confirmed on line 3106 of pg332 markdown: "2048 QPs of depth 128
locations and each RQE is of ... 256 B".**

Per PG332 §3 pg 582–583 ("The Receive Queue work requests need not be
posted by the application as the ERNIC Hardware automatically re-posts
consumed receive buffers as per the configured receive queue depth"),
the ERNIC owns the RQ and auto-reposts.  The driver's responsibility
for `post_recv` in our HW-handshake-disabled path is:

1. Record the userspace buffer the ibverbs app wants incoming SEND
   data written to.  Since ERNIC writes into the MR's DDR4 region,
   and the app's recv buffer is in host memory, **we stash the host
   VA + lkey + wr_id in a driver-side RQ shadow table, keyed by
   `(qp_num, rq_slot)`.  On CQE (B8), memcpy from DDR4 → host VA
   before signaling completion.**
2. Write a minimal RQE marker into DDR4 + ring the RQ producer
   (see §6 for doorbell mechanics).

The exact 256-byte RQE byte layout is not documented as a single
table in PG332 v4.2 — the doc describes the RQ queue tier (§Table 10
line 3106) without a byte-level breakdown like Table 2 for the SQ.
**VERIFY (V3, TOP PRIORITY)**: before applying B7, re-scan PG332
Chapter 3 for a "Table 3" equivalent giving the RQ buffer layout.
If no explicit layout, the RQE in `QPCONFi.RQBUFSZ`-units is the
incoming SEND payload buffer itself — the driver does not need to
format the buffer header, ERNIC writes packet data there directly
(it's a scatter buffer, not a WQE in the SQ sense).

Working assumption pending V3: **the RQ slot IS the landing buffer
for incoming SEND, 256 B per QP×depth, and the driver needs only to
program `RQBAi` (already done in B5 `create_qp`) and advance the
RQ producer index to tell ERNIC "slot N is available for you to
write into".**  No per-byte RQE format.

This matches what libreconic does in `rdma_post_receive` — no WQE
format is built for RQ; the code polls `STATRQPIDBi` to observe the
ERNIC-advanced pointer (rdma_api.c:861, 1019).

### 2.3 CQE — 4 B (B8 consumes, sketched here for completeness)

PG332 Table 3, line 629–642 of the markdown:

| Bits    | Field   | Size | Notes                   |
|---------|---------|------|-------------------------|
| [15:0]  | WRID    | 2    | matches SQ WQE WRID     |
| [23:16] | OPCODE  | 1    | echoes SQ opcode        |
| [31:24] | ERRFLAG | 1    | `1` iff QP went fatal   |

We only note this here so the §2.1 WRID-truncation design makes sense:
the 16-bit WRID in the CQE is what B8 will use to index the shadow
table that holds the real 64-bit `wr_id`.

---

## 3. Opcode map: `IB_WR_*` → ERNIC opcode byte

`libreconic/reconic_reg.h:263-268` already names the constants:

```c
#define RNIC_OP_WRITE        0   /* IB_WR_RDMA_WRITE            */
#define RNIC_OP_WRITE_IMMDT  1   /* IB_WR_RDMA_WRITE_WITH_IMM   */
#define RNIC_OP_SEND         2   /* IB_WR_SEND                  */
#define RNIC_OP_SEND_IMMDT   3   /* IB_WR_SEND_WITH_IMM         */
#define RNIC_OP_READ         4   /* IB_WR_RDMA_READ             */
#define RNIC_OP_SEND_INV     12  /* IB_WR_SEND_WITH_INV         */
```

These exactly match PG332 §3 Table 2 OPCODE column, lines 595–600.

Driver-side map:

```c
/* onic_ib.c (B7) */
static int onic_opcode_ib_to_ernic(enum ib_wr_opcode ib, u8 *out)
{
    switch (ib) {
    case IB_WR_RDMA_WRITE:          *out = 0x00; return 0;
    case IB_WR_RDMA_WRITE_WITH_IMM: *out = 0x01; return 0;
    case IB_WR_SEND:                *out = 0x02; return 0;
    case IB_WR_SEND_WITH_IMM:       *out = 0x03; return 0;
    case IB_WR_RDMA_READ:           *out = 0x04; return 0;
    /* B7 scope rejects the rest: */
    case IB_WR_SEND_WITH_INV:
    case IB_WR_LOCAL_INV:
    case IB_WR_REG_MR:
    case IB_WR_ATOMIC_CMP_AND_SWP:
    case IB_WR_ATOMIC_FETCH_AND_ADD:
    case IB_WR_MASKED_ATOMIC_CMP_AND_SWP:
    case IB_WR_MASKED_ATOMIC_FETCH_AND_ADD:
    default:
        return -EOPNOTSUPP;
    }
}
```

We explicitly hold `SEND_WITH_IMM` in-scope-ish because pingpong doesn't
need it but it costs nothing extra and improves surface for later tests.
`SEND_WITH_INV` is rejected even though the ERNIC opcode exists,
because we don't implement the MR-invalidation path (B9 territory).

---

## 4. Payload-copy design (chose B' — GUP + memcpy)

### Options reviewed

- **A. Use SGL host VA directly in LADDR**.  Requires ERNIC's AXI master
  to reach host DRAM.  That path (s_axib) is gated on B2 and not wired
  in Tier 1a.  Reject.
- **B. Use MR's DDR4 backing, assume app has put data there**.  App
  would need to `mmap()` the MR handle or the DDR4 BAR.  No current
  libonic support for that.  Too invasive for minimum B7.
- **B' (CHOSEN). Kernel copies SGL host VA → DDR4 MR region at post
  time, stuff the DDR4 address into LADDR**.  Works within B5 constraints
  (1 MR/PD, 64 KiB cap, 4 KiB pingpong payload).  Cost: one `get_user_pages`
  + kmap + memcpy per post_send.  Pingpong is 16 iters then 1000-ish
  roundtrips — not a perf blocker.

### Implementation sketch

```c
/* onic_ib.c (B7) — called from onic_post_send.  sgl is a single SGE,
 * B5 asserts max_send_sge==1. */
static int onic_stage_send_payload(struct onic_qp *qp,
                                   const struct ib_sge *sgl,
                                   u64 *out_ddr_addr)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(qp->ibqp.device);
    struct onic_pd     *pd  = qp->pd;
    struct onic_mr     *mr;
    u64    mr_off, ddr_off, user_va;
    size_t len;
    void __iomem *ddr_vaddr;      /* if we ioremap; see VERIFY V4 */
    struct page **pages;
    int    nr_pages, i, rv;

    spin_lock(&pd->mr_lock);
    mr = pd->mr;
    spin_unlock(&pd->mr_lock);
    if (!mr)                           return -EINVAL;
    if (sgl->lkey != mr->lkey)         return -EINVAL;

    user_va = sgl->addr;
    len     = sgl->length;
    if (user_va < mr->va)              return -EFAULT;
    mr_off  = user_va - mr->va;
    if (mr_off + len > mr->length)     return -EFAULT;

    ddr_off = mr->ddr_off + mr_off;

    /* Pin the user pages, memcpy into DDR4 via the already-mapped
     * DDR4 MMIO window.  V4: is the DDR4 BAR mapped as MMIO into the
     * driver (and if so, is it kmap-cmpatible)?  onic_hardware.c maps
     * the AXI-Lite BAR at priv->hw.addr — DDR4 is NOT that BAR.  DDR4
     * is on the ERNIC AXI fabric and only reachable via the QDMA
     * H2C path OR via a dedicated DDR4 MMIO aperture.  If the latter
     * isn't present in our shell, B7 CANNOT WORK — we need QDMA-H2C
     * descriptor submission, which is B2 scope.  This is the LARGEST
     * blocker — see §13 V4. */
    pages = kmalloc_array(DIV_ROUND_UP(len, PAGE_SIZE), sizeof(*pages),
                          GFP_KERNEL);
    if (!pages) return -ENOMEM;
    nr_pages = get_user_pages_fast(user_va, DIV_ROUND_UP(len, PAGE_SIZE),
                                   FOLL_WRITE, pages);
    if (nr_pages < 0) { kfree(pages); return nr_pages; }

    /* Per-page memcpy to DDR4 via the driver's DDR4 mapping. */
    rv = onic_ddr_memcpy_to(dev, ddr_off, pages, nr_pages, user_va, len);
    for (i = 0; i < nr_pages; i++) put_page(pages[i]);
    kfree(pages);
    if (rv) return rv;

    *out_ddr_addr = ((u64)ONIC_DDR4_MSB << 32) |
                    (dev->ddr.base_off + ddr_off);
    return 0;
}
```

The helper `onic_ddr_memcpy_to()` does not exist yet.  In the sketch
its body is:

```c
/* VERIFY V4 — on Tier 1a today, do we have a DDR4 MMIO window that the
 * host CPU can dereference, or do we have to submit a QDMA H2C descriptor
 * to hit ERNIC's DDR?  Two very different implementations. */

#if defined(CONFIG_ONIC_DDR4_MMIO_WINDOW)
/* Trivial case: DDR4 is mapped into BAR at priv->ddr.addr. */
static int onic_ddr_memcpy_to(struct onic_ib_dev *dev, u64 ddr_off,
                              struct page **pages, int nr,
                              u64 user_va_start, size_t len)
{
    void __iomem *dst = dev->priv->ddr.addr + ddr_off;
    size_t off_in_first = user_va_start & (PAGE_SIZE - 1);
    size_t remain = len;
    int i;
    for (i = 0; i < nr && remain; i++) {
        void *src = kmap_local_page(pages[i]);
        size_t chunk = min(remain, PAGE_SIZE - off_in_first);
        memcpy_toio(dst, src + off_in_first, chunk);
        kunmap_local(src);
        dst    += chunk;
        remain -= chunk;
        off_in_first = 0;
    }
    return 0;
}
#else
/* Fall-back: QDMA H2C descriptor submit — NOT in B7 scope.  If we don't
 * have the MMIO aperture, B7 must wait on B2. */
static int onic_ddr_memcpy_to(...) { return -EOPNOTSUPP; }
#endif
```

This is the heart of the V4 risk in §13.

For `post_recv`: **no copy needed at post time**.  The ERNIC writes
into its own RQ buffer in DDR4; the driver records the mapping
`(rq_slot → host_va, lkey, wr_id)` in a shadow table.  B8 will do the
reverse memcpy (DDR4 → host VA) when it produces the `ibv_wc` for
that CQE.

---

## 5. SQ ring management

### Driver state (additions to `struct onic_qp`)

```c
/* onic_ib.h (B7 delta) */
struct onic_sq_shadow {
    u64                wr_id;    /* full 64-bit cookie */
    enum ib_wr_opcode  op;       /* for B8 to fabricate wc->opcode */
    u32                byte_len; /* for B8 to fabricate wc->byte_len */
};

struct onic_qp {
    /* ... existing B3/B5/B6 fields ... */

    /* B7 — SQ producer tracker + shadow */
    u16                     sq_pi;       /* next slot to fill */
    u16                     sq_ci;       /* last slot ERNIC has CQE'd;
                                          * driver-side only, updated
                                          * in B8 */
    struct onic_sq_shadow  *sq_shadow;   /* sq_depth entries */

    /* B7 — RQ producer tracker + shadow */
    u16                     rq_pi;
    u16                     rq_ci;
    struct onic_rq_shadow  *rq_shadow;   /* rq_depth entries */

    spinlock_t              sq_lock;     /* serializes post_send */
    spinlock_t              rq_lock;     /* serializes post_recv */
};

struct onic_rq_shadow {
    u64    wr_id;
    u64    host_va;   /* where the app wants data */
    u32    length;
    u32    lkey;
};
```

Allocations/frees move into `onic_create_qp` and `onic_destroy_qp`:

```c
/* onic_create_qp (B7 additions) — after DDR slot alloc, before return */
qp->sq_shadow = kcalloc(qp->sq_depth, sizeof(*qp->sq_shadow), GFP_KERNEL);
qp->rq_shadow = kcalloc(qp->rq_depth, sizeof(*qp->rq_shadow), GFP_KERNEL);
if (!qp->sq_shadow || !qp->rq_shadow) {
    kfree(qp->sq_shadow);
    kfree(qp->rq_shadow);
    onic_ddr_qp_slot_free(&dev->ddr, qp_idx);
    return -ENOMEM;
}
qp->sq_pi = qp->sq_ci = 0;
qp->rq_pi = qp->rq_ci = 0;
spin_lock_init(&qp->sq_lock);
spin_lock_init(&qp->rq_lock);

/* onic_destroy_qp (B7 additions) — before onic_ddr_qp_slot_free */
kfree(qp->sq_shadow); qp->sq_shadow = NULL;
kfree(qp->rq_shadow); qp->rq_shadow = NULL;
```

### WQE slot address

SQ ring lives at `slot_off + ONIC_DDR_QUEUE_SQ_OFF`, 4 KiB available →
64 entries of 64 B.  B5 caps `sq_depth <= 16` so we use `16 * 64 = 1024
B` of that space — fine.

```c
static inline u64 onic_sq_slot_ddr_off(struct onic_qp *qp, u16 slot)
{
    /* slot index (0..sq_depth-1) */
    return qp->slot_off + ONIC_DDR_QUEUE_SQ_OFF +
           (u64)slot * sizeof(struct onic_sq_wqe);
}
```

### Doorbell

Single 32-bit write to `RN_RDMA_QCSR_SQPIi` at `0x38` offset inside
the per-QP CSR.  Value is the new 16-bit PI (ERNIC treats unused high
bits as zero).  This is exactly what libreconic does in
`rdma_post_send` (rdma_api.c:919).

```c
static void onic_ring_sq_doorbell(struct onic_ib_dev *dev,
                                  struct onic_qp *qp)
{
    void __iomem *mmio = dev->priv->hw.addr;
    u32 q = RN_RDMA_QCSR_REG(qp->qp_num, 0x00);
    iowrite32(qp->sq_pi, mmio + q + 0x38);   /* SQPIi */
    (void)ioread32(mmio + q + 0x38);         /* posted-write flush */
}
```

**VERIFY V5**: libreconic writes a monotonically-increasing 16-bit
counter, NOT `pi % sq_depth`.  We mirror this — `sq_pi` is a running
counter, the ring wraps naturally because the shadow table is indexed
by `sq_pi & (sq_depth - 1)` (B5 will need `is_power_of_2(sq_depth)`,
which we can enforce in `create_qp`).  PG332 §3 and Table 2 don't
explicitly nail this down — confirm by reading register description
of SQPIi in §Chapter 5 (Register Space).

---

## 6. RQ ring management

### Producer doorbell for the RQ

There are two candidate registers:

- `RN_RDMA_QCSR_RQCIi` at `0x34` — named "RQ Consumer Index".  libreconic
  writes this with `write_rq_cidb` (rdma_api.c:979) to ADVANCE WHAT THE
  DRIVER HAS CONSUMED (i.e. CQE's — recv-complete notifications).  This
  is NOT the post_recv doorbell.
- `RN_RDMA_QCSR_STATRQPIDBi` at `0x9C` — libreconic READS this from
  `poll_rq_pidb` (rdma_api.c:863) to observe the ERNIC-advanced
  producer index.  Also NOT the post_recv doorbell from the driver side.
- `RN_RDMA_QCSR_RQWPTRDBADDi` at `0x20` — MMIO-address where ERNIC posts
  doorbells TO the driver (host DRAM address).  B5 stubs this to 0.

**So: in HWHSHKDIS=1 mode (our B5 setting), ERNIC auto-consumes the
RQ ring based on RQBUFSZ.  The driver doesn't actually ring an RQ
producer doorbell — ERNIC uses the RQ buffer like a cyclic landing
pool, writing each incoming SEND to the next slot.**  The ibverbs
`post_recv` call, in this mode, is purely a software bookkeeping
operation that records (wr_id, host_va, lkey) in the shadow table
so B8 knows where to memcpy the received data.

This matches PG332 §3 pg 582: "The Receive Queue work requests need
not be posted by the application as the ERNIC Hardware automatically
re-posts consumed receive buffers as per the configured receive queue
depth."

**VERIFY V6, TOP PRIORITY**: reconfirm by reading PG332 §Chapter 5
entries for RQCIi (`0x34`) and STATRQPIDBi (`0x9C`).  If the former
is actually the driver-writes-PI-here doorbell (contradicting
libreconic's usage), we need to ring it after each post_recv.

Working assumption for B7 patch sketch: **no hardware doorbell on
post_recv** in HWHSHKDIS mode.  If V6 flips, insert:

```c
iowrite32(qp->rq_pi, mmio + q + 0x34);   /* RQCIi — ALTERNATE IF V6 FLIPS */
```

at the end of `onic_post_recv`.

### RQ shadow update

```c
static int onic_post_recv_one(struct onic_qp *qp,
                              const struct ib_recv_wr *wr)
{
    u32 slot;
    struct onic_rq_shadow *s;

    if (wr->num_sge != 1)            return -EINVAL;
    if (wr->sg_list[0].length == 0)  return -EINVAL;
    /* MR lkey sanity — single-MR-per-PD means lkey == pd->pdn */
    if (wr->sg_list[0].lkey != qp->pd->mr->lkey) return -EINVAL;

    /* ring full? */
    if ((u16)(qp->rq_pi - qp->rq_ci) >= qp->rq_depth)
        return -ENOMEM;

    slot = qp->rq_pi & (qp->rq_depth - 1);
    s = &qp->rq_shadow[slot];
    s->wr_id   = wr->wr_id;
    s->host_va = wr->sg_list[0].addr;
    s->length  = wr->sg_list[0].length;
    s->lkey    = wr->sg_list[0].lkey;

    qp->rq_pi++;
    return 0;
}
```

No DDR4 writes from the driver; ERNIC owns the RQ buffer contents.
No hardware doorbell under our HWHSHKDIS=1 mode (pending V6).

---

## 7. `onic_post_send` main loop

### Signature + outer shell

```c
/* onic_ib.c — B7 replaces the onic_stub_post_send.  Note the const on
 * the wr argument: modern kernel verbs have const ib_send_wr *. */
static int onic_post_send(struct ib_qp *ibqp,
                          const struct ib_send_wr *wr,
                          const struct ib_send_wr **bad_wr)
{
    struct onic_qp *qp = to_onic_qp(ibqp);
    const struct ib_send_wr *w;
    int rv = 0;

    spin_lock(&qp->state_lock);
    if (qp->state != ERNIC_QP_RTS) {
        spin_unlock(&qp->state_lock);
        *bad_wr = wr;
        return -EINVAL;
    }
    spin_unlock(&qp->state_lock);

    spin_lock_bh(&qp->sq_lock);
    for (w = wr; w; w = w->next) {
        rv = onic_post_send_one(qp, w);
        if (rv) {
            *bad_wr = w;
            break;
        }
    }
    /* Ring one doorbell at end of batch (see VERIFY V7). */
    if (!rv || w != wr) {
        /* At least one WR succeeded — ring. */
        struct onic_ib_dev *dev = to_onic_ib_dev(ibqp->device);
        onic_ring_sq_doorbell(dev, qp);
    }
    spin_unlock_bh(&qp->sq_lock);
    return rv;
}
```

**VERIFY V7**: does ERNIC require ringing SQPIi after each WQE, or
only once at end of batch?  libreconic's `rdma_post_send` rings once
per WQE (rdma_api.c:919), but `rdma_post_batch_send` bumps `sq_pidb`
by `batch_size` and rings once (rdma_api.c:947, 955).  The latter
suggests end-of-batch is fine.  We pick end-of-batch.

### Per-WR builder

```c
static int onic_post_send_one(struct onic_qp *qp,
                              const struct ib_send_wr *wr)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(qp->ibqp.device);
    struct onic_sq_wqe  w   = {};
    struct onic_sq_shadow *sh;
    u64 laddr_ddr = 0;
    u64 roffset   = 0;
    u32 rkey      = 0;
    u32 immdt     = 0;
    u8  ernic_op;
    u16 slot;
    int rv;

    /* 1. Opcode translation. */
    rv = onic_opcode_ib_to_ernic(wr->opcode, &ernic_op);
    if (rv) return rv;

    /* 2. SGL — B5 enforces num_sge == 1. */
    if (wr->num_sge != 1)            return -EINVAL;
    if (wr->sg_list[0].length == 0)  return -EINVAL;
    if (wr->sg_list[0].length > ONIC_DDR_MR_SMALL_SIZE) return -EMSGSIZE;

    /* 3. Ring full? */
    if ((u16)(qp->sq_pi - qp->sq_ci) >= qp->sq_depth) return -ENOMEM;

    /* 4. Stage payload into DDR4 MR region. */
    rv = onic_stage_send_payload(qp, &wr->sg_list[0], &laddr_ddr);
    if (rv) return rv;

    /* 5. Opcode-specific fields. */
    switch (wr->opcode) {
    case IB_WR_RDMA_WRITE_WITH_IMM:
        immdt = be32_to_cpu(wr->ex.imm_data);
        fallthrough;
    case IB_WR_RDMA_WRITE:
    case IB_WR_RDMA_READ:
        roffset = wr->wr.rdma.remote_addr;
        rkey    = wr->wr.rdma.rkey;
        break;
    case IB_WR_SEND_WITH_IMM:
        immdt = be32_to_cpu(wr->ex.imm_data);
        fallthrough;
    case IB_WR_SEND:
        /* no remote addr / rkey for SEND */
        break;
    default:
        return -EOPNOTSUPP;
    }

    /* 6. Build WQE (little-endian — ERNIC AXI is LE). */
    slot = qp->sq_pi & (qp->sq_depth - 1);
    w.wrid        = cpu_to_le16((u16)wr->wr_id);
    w.laddr_lo    = cpu_to_le32((u32)laddr_ddr);
    w.laddr_hi    = cpu_to_le32((u32)(laddr_ddr >> 32));
    w.length      = cpu_to_le32(wr->sg_list[0].length);
    w.opcode      = cpu_to_le32(ernic_op);
    w.roffset_lo  = cpu_to_le32((u32)roffset);
    w.roffset_hi  = cpu_to_le32((u32)(roffset >> 32));
    w.rtag        = cpu_to_le32(rkey);
    w.immdt       = cpu_to_le32(immdt);

    /* 7. Copy WQE into DDR4 SQ ring slot. */
    rv = onic_ddr_memcpy_to_raw(dev, onic_sq_slot_ddr_off(qp, slot),
                                &w, sizeof(w));
    if (rv) return rv;

    /* 8. Shadow + advance PI. */
    sh = &qp->sq_shadow[slot];
    sh->wr_id   = wr->wr_id;
    sh->op      = wr->opcode;
    sh->byte_len = wr->sg_list[0].length;
    qp->sq_pi++;

    pr_info_ratelimited("onic_ib: post_send qp=%u slot=%u op=%u len=%u pi=%u\n",
                        qp->qp_num, slot, ernic_op,
                        wr->sg_list[0].length, qp->sq_pi);
    return 0;
}
```

`onic_ddr_memcpy_to_raw(dev, ddr_off, buf, len)` is a simpler helper
than `onic_ddr_memcpy_to()` (no user-page walk; direct kernel buffer).
Under the V4 MMIO-window assumption it's one `memcpy_toio` call.

---

## 8. `onic_post_recv` main loop

Simpler — no payload staging, no WQE build.

```c
static int onic_post_recv(struct ib_qp *ibqp,
                          const struct ib_recv_wr *wr,
                          const struct ib_recv_wr **bad_wr)
{
    struct onic_qp *qp = to_onic_qp(ibqp);
    const struct ib_recv_wr *w;
    int rv = 0;

    spin_lock(&qp->state_lock);
    /* ERNIC RQ can be fed once QP is INIT or later; IB spec allows
     * post_recv in INIT. */
    if (qp->state != ERNIC_QP_INIT &&
        qp->state != ERNIC_QP_RTR  &&
        qp->state != ERNIC_QP_RTS) {
        spin_unlock(&qp->state_lock);
        *bad_wr = wr;
        return -EINVAL;
    }
    spin_unlock(&qp->state_lock);

    spin_lock_bh(&qp->rq_lock);
    for (w = wr; w; w = w->next) {
        rv = onic_post_recv_one(qp, w);
        if (rv) {
            *bad_wr = w;
            break;
        }
    }
    spin_unlock_bh(&qp->rq_lock);

    /* V6: no hardware doorbell in HWHSHKDIS mode.  If V6 flips,
     * iowrite32(qp->rq_pi, mmio + q + 0x34) here. */
    return rv;
}
```

---

## 9. Concurrency

- Per-QP `sq_lock` + `rq_lock`, spinlock+bh to tolerate calls from
  softirq (rdma-cm / iWARP-ish timers).  B5's `state_lock` continues
  to guard `qp->state`.
- `post_send` and `post_recv` both take the state_lock briefly to
  read `qp->state`, then drop it and take their own ring lock.  A
  `modify_qp` on the same QP can race — after we release state_lock
  and before we take sq_lock, another thread could transition RTS→ERR.
  In that case we'd ring a doorbell on an ERR'd QP.  Mitigation:
  re-check `qp->state == ERNIC_QP_RTS` under `sq_lock` too.  Adds
  one `READ_ONCE(qp->state)` cost per post, negligible.
- `destroy_qp` vs in-flight post: ibverbs requires the app to not
  call destroy_qp while another thread is in post_send on the same
  QP.  We rely on that — no reference counting beyond what the ib
  core provides.
- The DDR4 memcpy happens inside sq_lock.  That's a 64 B write +
  up-to-64 KiB payload memcpy_toio.  On 4 KiB pingpong this is
  ~1 µs — acceptable.

---

## 10. Error paths

| Condition                                | errno           | `*bad_wr` set | Notes                               |
|------------------------------------------|-----------------|---------------|-------------------------------------|
| QP not in RTS (post_send)                | `-EINVAL`       | yes (= wr)    |                                     |
| QP not in INIT/RTR/RTS (post_recv)       | `-EINVAL`       | yes           |                                     |
| `num_sge != 1`                           | `-EINVAL`       | yes           | B5 cap                              |
| `sg_list[0].length == 0`                 | `-EINVAL`       | yes           |                                     |
| `length > 64 KiB`                        | `-EMSGSIZE`     | yes           | B5 MR cap                           |
| `lkey != pd->mr->lkey`                   | `-EINVAL`       | yes           | single-MR-per-PD                    |
| SGL VA outside MR range                  | `-EFAULT`       | yes           |                                     |
| Ring full                                | `-ENOMEM`       | yes           | per-QP pi-ci gap check              |
| Unsupported opcode (atomics, INV, REG)   | `-EOPNOTSUPP`   | yes           |                                     |
| `get_user_pages_fast` fails              | `-EFAULT`       | yes           |                                     |
| DDR4 MMIO not available (V4 fallback)    | `-EOPNOTSUPP`   | yes           | compile-time switch                 |
| PD has no MR bound                       | `-EINVAL`       | yes           |                                     |

On every error we abort the batch at the first failing WR, set
`*bad_wr = w`, return the errno.  Any prior WRs in the batch already
went into the SQ ring — we DO ring the SQPIi doorbell for those (see
§7 "Ring one doorbell at end of batch" — the check `!rv || w != wr`
means "ring if at least one succeeded").  This matches the usual
verbs behavior (partial batch commits).

---

## 11. Userspace libonic changes

The kernel verbs ABI (uverbs) already funnels `ibv_post_send` through
`IB_USER_VERBS_CMD_POST_SEND` into `ib_device_ops.post_send`.
libibverbs does this via the `ibv_cmd_post_send`/`ibv_cmd_post_recv`
helpers.  Our current stubs in `libonic.c:193-199` just set errno and
return -1.

**Replacement:**

```c
/* libonic.c (B7 delta) */
static int onic_post_send(struct ibv_qp *q, struct ibv_send_wr *wr,
                          struct ibv_send_wr **bad)
{
    /* rdma-core v59 helper; forwards the WR list to the kernel via
     * the uverbs POST_SEND command.  Signature sanity-checked against
     * rdma-core infiniband/driver.h in v59. */
    int rv = ibv_cmd_post_send(q, wr, bad);
    if (rv)
        fprintf(stderr, "libonic: post_send rv=%d errno=%d\n",
                rv, errno);
    return rv;
}

static int onic_post_recv(struct ibv_qp *q, struct ibv_recv_wr *wr,
                          struct ibv_recv_wr **bad)
{
    int rv = ibv_cmd_post_recv(q, wr, bad);
    if (rv)
        fprintf(stderr, "libonic: post_recv rv=%d errno=%d\n",
                rv, errno);
    return rv;
}
```

**VERIFY V8**: the stock rdma-core v59 headers do expose
`ibv_cmd_post_send`/`ibv_cmd_post_recv` — they are declared in
`<infiniband/cmd_write.h>` or `<infiniband/driver.h>`.  Grep
`/usr/include/infiniband` on the build host before applying.  If
OFED's libibverbs lacks them, fall back to writing to the uverbs
`cmd_fd` directly with a `struct ib_uverbs_post_send` manually — the
prototype is in `<rdma/ib_user_verbs.h>`.

No allocator changes, no new ops-table slots.  The `verbs_context_ops`
table already has `.post_send` / `.post_recv` bound (libonic.c:308-309).

---

## 12. Patch sketch file-by-file

Rough LoC budget.  "New" = fresh lines; "Mod" = lines changed.

### `open-nic-driver/onic_ib.h`

- **New: ~35 LoC** — `struct onic_sq_wqe`, `struct onic_sq_shadow`,
  `struct onic_rq_shadow`, 4 new fields in `struct onic_qp` (sq_pi,
  sq_ci, rq_pi, rq_ci, sq_shadow*, rq_shadow*, sq_lock, rq_lock).
- **Mod: ~5 LoC** — struct reordering for cacheline alignment.

### `open-nic-driver/onic_ib.c`

- **New: ~220 LoC**
  - `onic_opcode_ib_to_ernic`                     (~20)
  - `onic_stage_send_payload`                     (~45)
  - `onic_ddr_memcpy_to` + `_raw`                 (~35)
  - `onic_sq_slot_ddr_off` inline                 (~5)
  - `onic_ring_sq_doorbell`                       (~10)
  - `onic_post_send_one`                          (~60)
  - `onic_post_send` outer                        (~25)
  - `onic_post_recv_one`                          (~20)
  - `onic_post_recv` outer                        (~25)
- **Mod: ~15 LoC** — `onic_create_qp` allocates shadows, inits
  ring-locks / PIs; `onic_destroy_qp` frees shadows; `onic_ib_ops`
  binds real post_send/post_recv instead of stubs.
- **Delete: ~4 LoC** — remove `onic_stub_post_send` /
  `onic_stub_post_recv` bodies (or keep as dead code until B8 lands).

### `libonic-provider/libonic.c`

- **Mod: ~10 LoC** — replace `onic_post_send` / `onic_post_recv` stub
  bodies with `ibv_cmd_post_send` / `ibv_cmd_post_recv` passthroughs +
  a stderr trace line each.

### `open-nic-driver/onic_hardware.c` (optional, V4 gate)

- **New: ~40 LoC** — if DDR4 MMIO window is present but currently
  unmapped, add `pci_iomap(pdev, BAR_DDR_IDX, ...)` in probe.  May
  not be needed if the window is already mapped for the queue-config
  writes.  **VERIFY V4**.

### Nothing else

- `onic_ddr_alloc.[ch]` — unchanged (no new size class).
- `onic_ernic_irq.[ch]` — unchanged (no new IRQ handling; B8 territory).
- `reconic_reg.h` — unchanged (all needed regs already defined).

**Total: ~290 LoC new, ~30 LoC modified across 3 files.**

---

## 13. Risks / VERIFY

Ordered by "how badly this blocks B7":

| ID  | Topic                         | Impact if wrong            | How to confirm                                                                                        |
|-----|-------------------------------|----------------------------|-------------------------------------------------------------------------------------------------------|
| V4  | DDR4 MMIO window from host     | **Blocks B7 entirely**     | Inspect `onic_hardware.c` + PCI BAR map.  If no mapping, B7 waits on B2 QDMA H2C.                    |
| V3  | RQ 256-B slot byte format      | RQ fails to fill / corrupts | Re-scan PG332 §3 Chapter 3 and §5 for any "Table N: RQE format".  Our assumption is buffer-only.    |
| V6  | RQCIi (0x34) semantics         | RQ stalls after ~`rq_depth` | PG332 §Chapter 5 register descriptions; cross-check against HWHSHKDIS behavior note.                  |
| V1  | WQE reserved-byte zeroing      | Opcode corruption           | libreconic does this exact layout and it works on bare ERNIC — low risk but confirm in trace.         |
| V2  | ROFFSET as full 64-bit VA      | RDMA WRITE/READ to wrong pa | Trace INSRRPKTCNT + remote DDR inspection after a known write.                                        |
| V5  | SQPIi is monotonic counter     | Ring wrap breaks            | libreconic behavior matches; reconfirm by inspection of PG332 §Chapter 5.                             |
| V7  | Doorbell per-WR vs batched     | Perf only, not correctness  | Both work per libreconic; end-of-batch is cheaper.                                                    |
| V8  | `ibv_cmd_post_send` available  | Userspace build break       | `grep -r ibv_cmd_post /usr/include/infiniband/`.  Trivial to confirm.                                 |

### Biggest single blocker

**V4 (DDR4 MMIO window).**  Without a way for the kernel to write the
WQE bytes into DDR4 — either via a memory-mapped BAR or via a QDMA H2C
descriptor — B7 cannot functionally complete `onic_ddr_memcpy_to_raw`.
Everything else in this doc assumes V4 is resolved in favor of the
MMIO path.  If the shell only exposes DDR4 via QDMA's data-mover, B7
shifts from a ~290-LoC patch to a ~600-LoC patch that co-opts the
QDMA H2C descriptor ring for control-plane WQE writes, OR depends on
B2 landing first.

### Race hazards to eyeball at review

- `modify_qp` → `ERR` racing with in-flight `post_send`: see §9;
  the re-check-under-sq_lock is the mitigation, keep it.
- `destroy_qp` racing with `post_send`: ibverbs forbids, we don't
  guard beyond that.  A `WARN_ON(qp->sq_shadow == NULL)` at entry
  is cheap insurance.
- `post_send` from two threads: `sq_lock` handles it.
- `post_recv` from softirq (if any driver-internal relay ever posts):
  spin_lock_bh handles it.

### Open question for human sign-off

Before applying: is there a DDR4 MMIO aperture the driver can write
through today, or is Tier 1a expected to rely on QDMA H2C for all
DDR4 access?  This determines whether B7 is one patch or two.
