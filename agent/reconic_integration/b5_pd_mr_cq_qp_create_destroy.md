# B5 — First real ibverbs objects: PD / MR / CQ / QP create + destroy

**Status:** design only — NO code to apply yet. This doc is a patch SKETCH.
**Depends on:** B3 (ib_device skeleton, PD bitmap), B3.5 (libonic userspace
provider), F1 (register-map audit), F4 (DDR4 allocator design), F5 (MSI-X
dispatch), F7 (QP/CQ/PD lifecycle header).
**Blocks:** B6 (`modify_qp` INIT→RTR→RTS), B7 (`post_send`/`post_recv`),
B8 (`poll_cq`/`req_notify_cq`), B9 (CC plumbing).

References throughout:
- **PG332** = `pg332-ernic-4.2.md` (Xilinx ERNIC v4.2 PG), Chapter 7
  "ERNIC Software Flow" lines 3562–3800 (RC QP Creation / Memory Registration /
  QP Deletion / Fatal Recovery).
- **F1**   = `f1_register_map_audit.md` (register offsets + bitfields).
- **F4**   = `f4_ddr4_allocator_design.md` (DDR4 layout, 16 GiB, per-ERNIC
  split, queue slots, MR classes).
- **F7**   = `f7_qp_cq_pd_lifecycle.md` (state machines + transition
  contracts). Header at `libreconic/ernic_lifecycle.h`.

---

## 1. Scope, non-goals, acceptance gate

### 1.1 In scope (the verbs that become real)

- `alloc_pd` / `dealloc_pd` — extend the B3 bitmap allocator to (a) still
  reserve a PDT row and (b) carry the MR back-binding lock/pointer for the
  single-MR-per-PD invariant (F7 §2, §3).
- `reg_user_mr` / `dereg_mr` — write the 8 per-entry PDT registers at
  `RN_RDMA_BASE_ADDRESS + pdt_row * 0x100` (F1 §5.1.2; PG332 §7 "Memory
  Registration"). Return a real `ibv_mr` with `lkey == rkey == pdt_row`.
- `create_cq` / `destroy_cq` — allocate a DDR4 CQ ring (F4 queue-tier slot,
  4 KiB CQ sub-region), defer QCSR programming until `create_qp` (CQ is
  per-QP in ERNIC; see §5.2 below).
- `create_qp` / `destroy_qp` — allocate SQ/RQ/CQ rings in DDR4 per F4,
  program `QCSR_SQBAi/RQBAi/CQBAi/QDEPTHi/PDi` and the QPCONFi/QPADVCONFi
  fields, bind PD + MR + send/recv CQ, leave QP in state **INIT**
  (`QPEN=0`). PG332 §7 "RC QP Creation" steps 1–2.

### 1.2 Out of scope (land later)

| Verb                   | Lands in |
|------------------------|----------|
| `modify_qp` (INIT→RTR→RTS) | B6 |
| `post_send`, `post_recv`   | B7 |
| `poll_cq`, `req_notify_cq` | B8 |
| One-shot CC plumbing       | B9 |
| `alloc_mr` (fastreg)       | B10 (not needed for RC pingpong) |
| `create_ah`, multicast     | not needed for RoCEv2 RC |

### 1.3 Acceptance gate

After B5 lands:

1. `sudo insmod onic.ko` clean; dmesg quiet (no WARN/BUG).
2. `ibv_devinfo -v onic_0100` unchanged from B3.
3. A minimal test program that does
   `ibv_alloc_pd → ibv_reg_mr → ibv_create_cq → ibv_create_qp` succeeds and
   their matching destroys also succeed.
4. `sudo ibv_rc_pingpong -d onic_0100 -g 0` progresses past
   `ibv_create_qp` and fails at `ibv_modify_qp` with `EOPNOTSUPP` (B6 is
   pending). **No kernel oops, no refcount leak, rmmod clean.**

That failure-shape — "got past create_qp, stops at modify_qp" — is the
signal B5 is done.

---

## 2. DDR4 allocator — B5 minimum viable implementation

F4 describes a 3-tier, 5-class allocator. Shipping all of that for B5 is
overkill. B5 needs only enough to give each QP its 16 KiB queue slot and
each MR a chunk of DDR4. Propose **minimal** `onic_ddr_alloc.{h,c}`:

### 2.1 What B5 actually uses

- **Queue tier (F4 §2.5):** 256 per-QP slots × 16 KiB per ERNIC, bitmap
  allocated. SQ at slot+0x0000, RQ at slot+0x1000, CQ at slot+0x2000.
  QP indices **start at 2** (QP0, QP1 reserved per PG332 §7 and F1 §5.4).
- **MR pool (F4 §3.1, reduced):** for B5, one size class only —
  `MR_SMALL` = 64 KiB × 256 entries = 16 MiB. Fits at offset `0x0040_0000`
  relative to each ERNIC base (F4 §2.3, start of the MR tier).
- Larger classes deferred to B10/B11. An app that registers an MR >64 KiB
  in B5 gets `-ENOMEM` (documented limitation).

### 2.2 Header sketch — `onic_ddr_alloc.h`

```c
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * onic_ddr_alloc.h — B5 minimum: queue-slot bitmap + one-class MR pool.
 * See f4_ddr4_allocator_design.md for the full design; this is the B5 subset.
 */
#ifndef __ONIC_DDR_ALLOC_H__
#define __ONIC_DDR_ALLOC_H__

#include <linux/bitops.h>
#include <linux/spinlock.h>
#include <linux/types.h>

/* F4 §2.1 — DDR4 appears to ERNIC at this 64-bit base (MSB half of the 64b BA
 * registers).  Byte offset inside DDR4 is OR'd into the LSB. */
#define ONIC_DDR4_MSB                   0xa3500000u

/* F4 §2.5 — queue tier */
#define ONIC_DDR_QUEUE_TIER_OFF         0x00040000u
#define ONIC_DDR_QUEUE_SLOT_SIZE        0x00004000u   /* 16 KiB */
#define ONIC_DDR_QUEUE_SQ_OFF           0x00000000u
#define ONIC_DDR_QUEUE_RQ_OFF           0x00001000u
#define ONIC_DDR_QUEUE_CQ_OFF           0x00002000u

/* B5 MR pool (single size class). F4 §3.1 — keep room to grow. */
#define ONIC_DDR_MR_TIER_OFF            0x00400000u
#define ONIC_DDR_MR_SMALL_SIZE          0x00010000u   /* 64 KiB */
#define ONIC_DDR_MR_SMALL_COUNT         256u

/* Per-ERNIC region size.  F4 §2.2: 8 GiB each until DIMM2 probe lifts it.  B5
 * doesn't hit the ceiling; hard-code 8 GiB for safety. */
#define ONIC_DDR_ERNIC_REGION_SIZE      0x200000000ULL

/* QP 0 and QP 1 are reserved (PG332 §7; F1 §5.4).  First usable index = 2. */
#define ONIC_QP_RESERVED_LO             2u
#define ONIC_QP_MAX                     256u          /* Track B budget */

struct onic_ddr_pool {
	/* base_off: 0 for ERNIC0, 0x2_0000_0000 for ERNIC1 (F4 §2.2). */
	u64                 base_off;

	/* Queue slots. Bit i == in-use; bits 0,1 preset to reserved. */
	DECLARE_BITMAP(qp_bits, ONIC_QP_MAX);
	spinlock_t          qp_lock;

	/* MR small-class free bitmap. */
	DECLARE_BITMAP(mr_small_bits, ONIC_DDR_MR_SMALL_COUNT);
	spinlock_t          mr_lock;
};

int  onic_ddr_pool_init(struct onic_ddr_pool *p, unsigned int ernic_id);
void onic_ddr_pool_fini(struct onic_ddr_pool *p);

/*
 * Allocate a 16 KiB per-QP slot. *out_qp_idx is in [2, ONIC_QP_MAX).
 * *out_slot_off is the byte offset inside DDR4 (host caller OR-masks
 * ONIC_DDR4_MSB into the BA MSB register).
 */
int  onic_ddr_qp_slot_alloc(struct onic_ddr_pool *p,
			    u32 *out_qp_idx, u64 *out_slot_off);
void onic_ddr_qp_slot_free(struct onic_ddr_pool *p, u32 qp_idx);

/*
 * Allocate one MR backing region. B5 only supports size <= 64 KiB; any
 * larger request returns -ENOMEM (see §2.1).  *out_off is DDR4 byte offset.
 */
int  onic_ddr_mr_alloc(struct onic_ddr_pool *p, u64 size,
		       u64 *out_off, u64 *out_len);
void onic_ddr_mr_free(struct onic_ddr_pool *p, u64 off);

/* Helper: compose 64b DDR4 address from offset. */
static inline u64 onic_ddr_addr(const struct onic_ddr_pool *p, u64 off)
{
	return ((u64)ONIC_DDR4_MSB << 32) | (p->base_off + off);
}
static inline u32 onic_ddr_addr_lsb(const struct onic_ddr_pool *p, u64 off)
{
	return (u32)((p->base_off + off) & 0xFFFFFFFFu);
}
static inline u32 onic_ddr_addr_msb(const struct onic_ddr_pool *p, u64 off)
{
	/* F4 §2.3: for ERNIC1 with base_off=0x2_0000_0000, the high 32b of
	 * the DDR4 addr is 0xa350_0002, not 0xa350_0000. */
	u64 a = ((u64)ONIC_DDR4_MSB << 32) | (p->base_off + off);
	return (u32)(a >> 32);
}

#endif /* __ONIC_DDR_ALLOC_H__ */
```

### 2.3 Source sketch — `onic_ddr_alloc.c`

```c
/* SPDX-License-Identifier: GPL-2.0 */
#include <linux/slab.h>
#include "onic_ddr_alloc.h"

int onic_ddr_pool_init(struct onic_ddr_pool *p, unsigned int ernic_id)
{
	memset(p, 0, sizeof(*p));
	/* F4 §2.2: disjoint halves.  ERNIC0 -> 0, ERNIC1 -> 0x2_0000_0000. */
	p->base_off = (u64)ernic_id * 0x200000000ULL;

	spin_lock_init(&p->qp_lock);
	spin_lock_init(&p->mr_lock);

	/* Reserve QP0 + QP1 per PG332 §7 + F1 §5.4. */
	bitmap_zero(p->qp_bits, ONIC_QP_MAX);
	set_bit(0, p->qp_bits);
	set_bit(1, p->qp_bits);

	bitmap_zero(p->mr_small_bits, ONIC_DDR_MR_SMALL_COUNT);
	return 0;
}

void onic_ddr_pool_fini(struct onic_ddr_pool *p)
{
	/* No kmalloc'd state in the B5 allocator; nothing to free. */
}

int onic_ddr_qp_slot_alloc(struct onic_ddr_pool *p,
			   u32 *out_qp_idx, u64 *out_slot_off)
{
	unsigned long flags;
	int bit;

	spin_lock_irqsave(&p->qp_lock, flags);
	bit = find_first_zero_bit(p->qp_bits, ONIC_QP_MAX);
	if (bit >= ONIC_QP_MAX) {
		spin_unlock_irqrestore(&p->qp_lock, flags);
		return -ENOMEM;
	}
	set_bit(bit, p->qp_bits);
	spin_unlock_irqrestore(&p->qp_lock, flags);

	*out_qp_idx   = (u32)bit;
	*out_slot_off = ONIC_DDR_QUEUE_TIER_OFF +
			(u64)bit * ONIC_DDR_QUEUE_SLOT_SIZE;
	return 0;
}

void onic_ddr_qp_slot_free(struct onic_ddr_pool *p, u32 qp_idx)
{
	unsigned long flags;

	if (qp_idx < ONIC_QP_RESERVED_LO || qp_idx >= ONIC_QP_MAX)
		return;
	spin_lock_irqsave(&p->qp_lock, flags);
	clear_bit(qp_idx, p->qp_bits);
	spin_unlock_irqrestore(&p->qp_lock, flags);
}

int onic_ddr_mr_alloc(struct onic_ddr_pool *p, u64 size,
		      u64 *out_off, u64 *out_len)
{
	unsigned long flags;
	int bit;

	/* B5 limitation: single class.  Reject >64 KiB (documented). */
	if (size == 0 || size > ONIC_DDR_MR_SMALL_SIZE)
		return -ENOMEM;

	spin_lock_irqsave(&p->mr_lock, flags);
	bit = find_first_zero_bit(p->mr_small_bits, ONIC_DDR_MR_SMALL_COUNT);
	if (bit >= ONIC_DDR_MR_SMALL_COUNT) {
		spin_unlock_irqrestore(&p->mr_lock, flags);
		return -ENOMEM;
	}
	set_bit(bit, p->mr_small_bits);
	spin_unlock_irqrestore(&p->mr_lock, flags);

	*out_off = ONIC_DDR_MR_TIER_OFF +
		   (u64)bit * ONIC_DDR_MR_SMALL_SIZE;
	*out_len = ONIC_DDR_MR_SMALL_SIZE;
	return 0;
}

void onic_ddr_mr_free(struct onic_ddr_pool *p, u64 off)
{
	unsigned long flags;
	u64 idx;

	if (off < ONIC_DDR_MR_TIER_OFF)
		return;
	idx = (off - ONIC_DDR_MR_TIER_OFF) / ONIC_DDR_MR_SMALL_SIZE;
	if (idx >= ONIC_DDR_MR_SMALL_COUNT)
		return;

	spin_lock_irqsave(&p->mr_lock, flags);
	clear_bit(idx, p->mr_small_bits);
	spin_unlock_irqrestore(&p->mr_lock, flags);
}
```

**VERIFY:** the `base_off = ernic_id * 0x2_0000_0000` convention matches
whatever `onic_private::ernic_id` / which-ERNIC the ib_device is bound to.
B3 only wires ERNIC0; for B5 we hard-code `ernic_id = 0` everywhere and
leave the ERNIC1 multiplexing for a later story.

---

## 3. PD object — upgrade from B3 bitmap

B3 keeps a 256-bit bitmap indexed 0..255; allocating yields a PDT row
number. B5 extends `struct onic_pd` to track its bound MR (single-MR-per-PD
per F7 §2/§3 — the PDT row IS the MR table row).

### 3.1 Struct changes (in `onic_ib.h`)

```c
/* Extends B3 definition. */
struct onic_pd {
	struct ib_pd      ibpd;       /* existing */
	u32               pdn;        /* PDT row, 0..ONIC_IB_MAX_PD-1 */
	struct onic_mr   *mr;         /* bound MR or NULL */
	spinlock_t        mr_lock;    /* guards ->mr */
};
```

`alloc_pd` gains one line: `spin_lock_init(&pd->mr_lock); pd->mr = NULL;`.
`dealloc_pd` refuses to run if `pd->mr != NULL` (ib_core normally tears
MRs down first, but be defensive):

```c
static int onic_dealloc_pd(struct ib_pd *ibpd, struct ib_udata *udata)
{
	struct onic_ib_dev *dev = to_onic_ib_dev(ibpd->device);
	struct onic_pd     *pd  = to_onic_pd(ibpd);

	spin_lock(&pd->mr_lock);
	if (pd->mr) {
		spin_unlock(&pd->mr_lock);
		return -EBUSY;
	}
	spin_unlock(&pd->mr_lock);

	spin_lock(&dev->pd_lock);
	clear_bit(pd->pdn, dev->pd_bitmap);
	spin_unlock(&dev->pd_lock);
	return 0;
}
```

---

## 4. MR object — `reg_user_mr` / `dereg_mr`

### 4.1 Struct (`onic_ib.h`)

```c
struct onic_mr {
	struct ib_mr      ibmr;
	struct onic_pd   *pd;         /* back-ptr */
	u64               va;         /* user VA (advisory) */
	u64               ddr_off;    /* DDR4 byte offset (from allocator) */
	u64               length;     /* MR length in bytes */
	u8                access;     /* ERNIC ACCESSDESC[1:0] encoding */
	u32               lkey;       /* = rkey = pdt row */
	u32               rkey;
};

static inline struct onic_mr *to_onic_mr(struct ib_mr *mr)
{
	return container_of(mr, struct onic_mr, ibmr);
}
```

### 4.2 `reg_user_mr` sequence

Per PG332 §7 "Memory Registration" + F1 §5.1.2 (PDT entry layout,
8 × 32b registers at `RN_RDMA_BASE_ADDRESS + pdt_row * 0x100`).

Invariants enforced:
- Single MR per PD (F7 §2/§3). Reject if `pd->mr != NULL`.
- B5 restriction — MR backing MUST be carved from DDR4 staging. Host-memory
  MRs require the s_axib bridge which isn't wired yet. Document as "Track B
  restriction" (§12 risks).
- `lkey == rkey == pdn` (see §12 risks — we accept the rkey-collision risk
  under the "controlled deployments" Track B premise).

```c
static struct ib_mr *
onic_reg_user_mr(struct ib_pd *ibpd, u64 start, u64 length, u64 virt_addr,
		 int access_flags, struct ib_dmah *dmah, struct ib_udata *udata)
{
	struct onic_ib_dev *dev = to_onic_ib_dev(ibpd->device);
	struct onic_pd     *pd  = to_onic_pd(ibpd);
	struct onic_mr     *mr;
	u64   ddr_off, ddr_len;
	u64   buf_addr;
	u32   access_desc;
	int   ret;

	(void)dmah;
	(void)udata;

	/* Cap checks. */
	if (length == 0 || length > ONIC_DDR_MR_SMALL_SIZE)
		return ERR_PTR(-EINVAL);

	/* F7 §2: one MR per PD. */
	spin_lock(&pd->mr_lock);
	if (pd->mr) {
		spin_unlock(&pd->mr_lock);
		return ERR_PTR(-EBUSY);
	}
	spin_unlock(&pd->mr_lock);

	mr = kzalloc(sizeof(*mr), GFP_KERNEL);
	if (!mr)
		return ERR_PTR(-ENOMEM);

	ret = onic_ddr_mr_alloc(&dev->ddr, length, &ddr_off, &ddr_len);
	if (ret) { kfree(mr); return ERR_PTR(ret); }

	/* ERNIC ACCESSDESC[1:0] — F7 enum ernic_mr_access; PG332 line 3793. */
	access_desc = 0;
	if (access_flags & IB_ACCESS_REMOTE_READ)  access_desc |= 0x1;
	if (access_flags & IB_ACCESS_REMOTE_WRITE) access_desc |= 0x2;
	/* IB_ACCESS_LOCAL_WRITE does not correspond to any ERNIC bit;
	 * ERNIC assumes local RW always.  VERIFY against PG332 line 3793. */

	mr->pd      = pd;
	mr->va      = virt_addr;
	mr->ddr_off = ddr_off;
	mr->length  = length;
	mr->access  = access_desc & 0x3;
	mr->lkey    = pd->pdn;
	mr->rkey    = pd->pdn;

	/* Buffer address for BUFBASEADDR{LSB,MSB} — the DDR4 address the
	 * ERNIC DMA engine will target on remote WRITE/READ. */
	buf_addr = ((u64)ONIC_DDR4_MSB << 32) | (dev->ddr.base_off + ddr_off);

	/* Program the 8 PDT registers. F1 §5.1.2.  Stride 0x100 per row. */
	{
		void __iomem *mmio = dev->priv->hw.addr;
		u32 row_base = RN_RDMA_BASE_ADDRESS + pd->pdn * 0x100;

		iowrite32(pd->pdn,                         mmio + row_base + 0x00); /* PDPDNUM */
		iowrite32((u32)(virt_addr & 0xffffffffu),  mmio + row_base + 0x04); /* VIRTADDRLSB */
		iowrite32((u32)(virt_addr >> 32),          mmio + row_base + 0x08); /* VIRTADDRMSB */
		iowrite32((u32)(buf_addr & 0xffffffffu),   mmio + row_base + 0x0C); /* BUFBASEADDRLSB */
		iowrite32((u32)(buf_addr >> 32),           mmio + row_base + 0x10); /* BUFBASEADDRMSB */
		iowrite32(mr->rkey & 0xffu,                mmio + row_base + 0x14); /* BUFRKEY */
		iowrite32((u32)(length & 0xffffffffu),     mmio + row_base + 0x18); /* WRRDBUFLEN */
		iowrite32(((u32)(length >> 16) << 16) |
			  ((u32)mr->access & 0x3),         mmio + row_base + 0x1C); /* ACCESSDESC */
		/* Flush: read one back (cheap barrier on BAR). */
		(void)ioread32(mmio + row_base + 0x00);
	}

	mr->ibmr.lkey = mr->lkey;
	mr->ibmr.rkey = mr->rkey;

	spin_lock(&pd->mr_lock);
	pd->mr = mr;
	spin_unlock(&pd->mr_lock);

	return &mr->ibmr;
}
```

### 4.3 `dereg_mr` sequence

Refuse while any QP still binds this PD (F7 §3 drain rule). Ib_core
destroys QPs before MRs in the normal tear-down order, so in practice
this just zeros the row and frees DDR4:

```c
static int onic_dereg_mr(struct ib_mr *ibmr, struct ib_udata *udata)
{
	struct onic_mr     *mr  = to_onic_mr(ibmr);
	struct onic_pd     *pd  = mr->pd;
	struct onic_ib_dev *dev = to_onic_ib_dev(ibmr->device);
	void __iomem       *mmio = dev->priv->hw.addr;
	u32                 row_base = RN_RDMA_BASE_ADDRESS + pd->pdn * 0x100;
	int                 i;

	/* Zero the PDT row (all 8 registers). */
	for (i = 0; i < 8; i++)
		iowrite32(0, mmio + row_base + i * 4);
	(void)ioread32(mmio + row_base + 0);

	onic_ddr_mr_free(&dev->ddr, mr->ddr_off);

	spin_lock(&pd->mr_lock);
	pd->mr = NULL;
	spin_unlock(&pd->mr_lock);

	kfree(mr);
	return 0;
}
```

---

## 5. CQ object — `create_cq` / `destroy_cq`

### 5.1 Struct

```c
struct onic_cq {
	struct ib_cq      ibcq;
	u32               cq_id;      /* == bound QP index once bound */
	u64               ddr_off;    /* DDR4 byte offset of CQ ring */
	u32               depth;      /* number of CQEs */
	u32               head;       /* driver tail-tracker for B8 */
	u32               tail;
	bool              bound;      /* CQ is always created un-bound here */
	spinlock_t        lock;
};

static inline struct onic_cq *to_onic_cq(struct ib_cq *cq)
{
	return container_of(cq, struct onic_cq, ibcq);
}
```

### 5.2 Design choice — deferred QCSR programming

ERNIC has no standalone CQ object — `CQBAi`, `CQBAMSBi`, `QDEPTHi[CQDEPTH]`
all live in a QP's QCSR slot. But ibverbs apps create CQs *before* QPs
and often reuse one CQ across multiple QPs. We solve this as:

1. `create_cq` allocates driver-side bookkeeping only — no QCSR writes.
   Depth is remembered. DDR4 allocation is DEFERRED to `create_qp`, which
   owns the queue slot anyway (CQ ring lives at slot+0x2000 per F4 §2.5).
2. `create_qp` programs CQBAi/CQBAMSBi/QDEPTHi using **the queue slot it
   just allocated** and writes the CQ's `ddr_off` / `cq_id` / `bound=true`
   back into the `onic_cq` object.
3. **CQ sharing across QPs is REJECTED in B5.** If `ibv_create_qp` gets a
   `send_cq` or `recv_cq` that is already `bound`, return `-EINVAL`. That
   matches ERNIC's one-CQ-per-QP model and keeps B5 honest. Documented in
   §12 risks; some apps (not `ibv_rc_pingpong`) will need to stop sharing
   CQs. `ibv_rc_pingpong` uses one CQ for send+recv of the same QP — that
   is fine, we bind both to the same slot.

### 5.3 Code sketch

```c
static int onic_create_cq(struct ib_cq *ibcq,
			  const struct ib_cq_init_attr *attr,
			  struct uverbs_attr_bundle *attrs)
{
	struct onic_cq *cq = container_of(ibcq, struct onic_cq, ibcq);

	if (attr->cqe == 0 || attr->cqe > 1024)
		return -EINVAL;

	spin_lock_init(&cq->lock);
	cq->depth = attr->cqe;
	cq->head  = 0;
	cq->tail  = 0;
	cq->bound = false;
	/* cq_id and ddr_off filled in by create_qp when it binds. */
	return 0;
}

static int onic_destroy_cq(struct ib_cq *ibcq, struct ib_udata *udata)
{
	struct onic_cq *cq = container_of(ibcq, struct onic_cq, ibcq);

	/* No per-CQ DDR4 allocation to free here — the CQ's DDR4 slice is
	 * part of the QP's queue-slot, and that's freed by destroy_qp.
	 * If cq->bound is still true when we get here, the bound QP wasn't
	 * destroyed first — ib_core shouldn't let that happen (refcount),
	 * but be defensive. */
	if (cq->bound)
		return -EBUSY;
	return 0;
}
```

Requires `INIT_RDMA_OBJ_SIZE(ib_cq, onic_cq, ibcq)` in the ops table.

---

## 6. QP object — `create_qp` / `destroy_qp`

### 6.1 Struct

```c
struct onic_qp {
	struct ib_qp          ibqp;
	enum ernic_qp_state   state;      /* from ernic_lifecycle.h */
	u32                   qp_num;     /* DDR4 queue-slot index; also ERNIC QPi */
	struct onic_pd       *pd;
	struct onic_cq       *send_cq;
	struct onic_cq       *recv_cq;

	u64                   slot_off;   /* DDR4 byte offset of the 16 KiB slot */
	u32                   sq_depth;
	u32                   rq_depth;
	u32                   cq_depth;
	u8                    path_mtu;   /* PG332 QPCONFi[10:8], code 0..4 */

	spinlock_t            state_lock;
};

static inline struct onic_qp *to_onic_qp(struct ib_qp *qp)
{
	return container_of(qp, struct onic_qp, ibqp);
}
```

### 6.2 Sequence per PG332 §7 "RC QP Creation" + F7 §5 RESET→INIT

B5 does RESET→INIT ONLY. B6 does INIT→RTR (DESTQPCONFi, MACDESADDLSB/MSB,
IPDESADDR1..4, TIMEOUTCONFi) and RTR→RTS (SQPSNi + QPEN=1 + bump
`XRNIC_CONF_QP_EN`).

Validation:
- `init_attr->qp_type == IB_QPT_RC` (RoCEv2 RC only).
- `cap.max_send_wr <= 16`, `cap.max_recv_wr <= 16`, `max_send_sge <= 1`,
  `max_recv_sge <= 1`. (PG332 single-SGE WQE layout.)
- Neither CQ already bound.

```c
static int onic_create_qp(struct ib_qp *ibqp,
			  struct ib_qp_init_attr *init_attr,
			  struct ib_udata *udata)
{
	struct onic_ib_dev *dev  = to_onic_ib_dev(ibqp->device);
	struct onic_pd     *pd   = to_onic_pd(ibqp->pd);
	struct onic_qp     *qp   = to_onic_qp(ibqp);
	struct onic_cq     *scq  = init_attr->send_cq ?
				   container_of(init_attr->send_cq,
						struct onic_cq, ibcq) : NULL;
	struct onic_cq     *rcq  = init_attr->recv_cq ?
				   container_of(init_attr->recv_cq,
						struct onic_cq, ibcq) : NULL;
	void __iomem       *mmio = dev->priv->hw.addr;
	u32                 qp_idx;
	u64                 slot_off;
	u64                 sq_off, rq_off, cq_off;
	u32                 qpconfi, qpadvconfi, qdepthi;
	int                 rv;

	if (init_attr->qp_type != IB_QPT_RC)
		return -EOPNOTSUPP;
	if (init_attr->cap.max_send_wr > 16 ||
	    init_attr->cap.max_recv_wr > 16 ||
	    init_attr->cap.max_send_sge > 1 ||
	    init_attr->cap.max_recv_sge > 1)
		return -EINVAL;
	if (!scq || !rcq)
		return -EINVAL;
	if (scq->bound || rcq->bound)
		return -EINVAL;           /* B5: no CQ sharing */

	/* Require a PD with an MR registered — ERNIC QP needs its PD
	 * pre-bound to an MR (PDT row already filled). */
	spin_lock(&pd->mr_lock);
	if (!pd->mr) {
		spin_unlock(&pd->mr_lock);
		return -EINVAL;
	}
	spin_unlock(&pd->mr_lock);

	/* 1. Allocate the DDR4 queue slot. */
	rv = onic_ddr_qp_slot_alloc(&dev->ddr, &qp_idx, &slot_off);
	if (rv)
		return rv;

	sq_off = slot_off + ONIC_DDR_QUEUE_SQ_OFF;
	rq_off = slot_off + ONIC_DDR_QUEUE_RQ_OFF;
	cq_off = slot_off + ONIC_DDR_QUEUE_CQ_OFF;

	qp->qp_num     = qp_idx;
	qp->pd         = pd;
	qp->send_cq    = scq;
	qp->recv_cq    = rcq;
	qp->slot_off   = slot_off;
	qp->sq_depth   = init_attr->cap.max_send_wr;
	qp->rq_depth   = init_attr->cap.max_recv_wr;
	qp->cq_depth   = max(scq->depth, rcq->depth);
	qp->path_mtu   = 4;  /* 4096 — PG332 QPCONFi[10:8] = 0b100 */
	qp->state      = ERNIC_QP_RESET;
	spin_lock_init(&qp->state_lock);

	/* 2. Program QCSR registers (QPEN stays 0 — B6 will set it).
	 *    PG332 §7 "RC QP Creation" steps 1-2.
	 *    QPCONFi[0] QPEN=0, QPCONFi[2] RQINTEN=1, QPCONFi[3] CQINTEN=1,
	 *    QPCONFi[5] HWHSHKDIS=1 (no H/W handshake in B5),
	 *    QPCONFi[10:8] PATHMTU=0b100 (4096),
	 *    QPCONFi[31:16] RQBUFSZ = rq_depth in 256-B units
	 *                   = rq_depth * 1 (one 256-B slot per WQE).
	 *    VERIFY rqbufsz encoding — F1 §5.2 / PG332 line range TBD. */
	qpconfi  = 0;
	qpconfi |= (0u     << 0);          /* QPEN = 0 */
	qpconfi |= (1u     << 2);          /* RQINTEN */
	qpconfi |= (1u     << 3);          /* CQINTEN */
	qpconfi |= (1u     << 5);          /* HWHSHKDIS */
	qpconfi |= ((u32)qp->path_mtu & 0x7) << 8;
	qpconfi |= ((u32)qp->rq_depth & 0xffffu) << 16;

	/* QPADVCONFi: TC=0, TTL=64, PKEY=0xFFFF.  F1 §5.3. */
	qpadvconfi = 0;
	qpadvconfi |= (0u    << 0);         /* traffic class */
	qpadvconfi |= (64u   << 8);         /* TTL */
	qpadvconfi |= (0xFFFFu << 16);      /* PKEY */

	qdepthi  = ((u32)qp->rq_depth << 16) | (u32)qp->sq_depth;

	/* Per-QP register base (F1 §5 macro). */
	{
		u32 q = RN_RDMA_QCSR_REG(qp_idx, 0x00);
		iowrite32(qpconfi,     mmio + q);                 /* QPCONFi */
		iowrite32(qpadvconfi,  mmio + q + 0x04);          /* QPADVCONFi */
		/* RQ base */
		iowrite32(onic_ddr_addr_lsb(&dev->ddr, rq_off),
			  mmio + q + 0x08);                        /* RQBAi */
		iowrite32(onic_ddr_addr_msb(&dev->ddr, rq_off),
			  mmio + q + 0xC0);                        /* RQBAMSBi */
		/* SQ base */
		iowrite32(onic_ddr_addr_lsb(&dev->ddr, sq_off),
			  mmio + q + 0x10);                        /* SQBAi */
		iowrite32(onic_ddr_addr_msb(&dev->ddr, sq_off),
			  mmio + q + 0xC8);                        /* SQBAMSBi */
		/* CQ base */
		iowrite32(onic_ddr_addr_lsb(&dev->ddr, cq_off),
			  mmio + q + 0x18);                        /* CQBAi */
		iowrite32(onic_ddr_addr_msb(&dev->ddr, cq_off),
			  mmio + q + 0xD0);                        /* CQBAMSBi */
		iowrite32(qdepthi,     mmio + q + 0x3C);          /* QDEPTHi */
		iowrite32(pd->pdn,     mmio + q + 0xB0);          /* PDi */
		/* Doorbells: we don't use host-DMA doorbells in B5 (ERNIC
		 * reads SQPIi via MMIO, see B7).  Zero RQWPTRDBADDi and
		 * CQDBADDi defensively. */
		iowrite32(0, mmio + q + 0x20);                    /* RQWPTRDBADDi */
		iowrite32(0, mmio + q + 0x24);                    /* RQWPTRDBADDMSBi */
		iowrite32(0, mmio + q + 0x28);                    /* CQDBADDi */
		iowrite32(0, mmio + q + 0x2C);                    /* CQDBADDMSBi */

		(void)ioread32(mmio + q + 0x00);                  /* flush */
	}

	/* 3. Bind CQs to this slot's CQ region. */
	scq->cq_id   = qp_idx;
	scq->ddr_off = cq_off;
	scq->bound   = true;
	if (rcq != scq) {
		/* Two-CQ case.  ERNIC has only one CQBAi per QP, so if an
		 * app specifies distinct send/recv CQs we'd need to fail.
		 * VERIFY: ibv_rc_pingpong uses the same CQ for both. */
		scq->bound = false; /* undo */
		onic_ddr_qp_slot_free(&dev->ddr, qp_idx);
		return -EINVAL;
	}

	qp->state     = ERNIC_QP_INIT;          /* F7 §5.1 */
	qp->ibqp.qp_num = qp_idx;
	return 0;
}
```

### 6.3 `destroy_qp`

Idempotent. QP may be in INIT (never enabled) in B5, since modify_qp
isn't implemented. Just zero the QCSR slot and free the DDR4 slot:

```c
static int onic_destroy_qp(struct ib_qp *ibqp, struct ib_udata *udata)
{
	struct onic_qp     *qp   = to_onic_qp(ibqp);
	struct onic_ib_dev *dev  = to_onic_ib_dev(ibqp->device);
	void __iomem       *mmio = dev->priv->hw.addr;
	u32                 q    = RN_RDMA_QCSR_REG(qp->qp_num, 0x00);

	/* F7 §5: QPEN=0 first (should already be 0 in B5 since we never
	 * reach RTR/RTS).  Zero QPCONFi + the base/depth regs for
	 * hygiene. */
	iowrite32(0, mmio + q + 0x00);                  /* QPCONFi */
	iowrite32(0, mmio + q + 0x04);                  /* QPADVCONFi */
	iowrite32(0, mmio + q + 0x08);                  /* RQBAi */
	iowrite32(0, mmio + q + 0xC0);                  /* RQBAMSBi */
	iowrite32(0, mmio + q + 0x10);                  /* SQBAi */
	iowrite32(0, mmio + q + 0xC8);                  /* SQBAMSBi */
	iowrite32(0, mmio + q + 0x18);                  /* CQBAi */
	iowrite32(0, mmio + q + 0xD0);                  /* CQBAMSBi */
	iowrite32(0, mmio + q + 0x3C);                  /* QDEPTHi */
	iowrite32(0, mmio + q + 0xB0);                  /* PDi */
	(void)ioread32(mmio + q + 0x00);                /* flush */

	if (qp->send_cq) qp->send_cq->bound = false;
	if (qp->recv_cq && qp->recv_cq != qp->send_cq)
		qp->recv_cq->bound = false;

	onic_ddr_qp_slot_free(&dev->ddr, qp->qp_num);
	qp->state = ERNIC_QP_CLOSED;
	return 0;
}
```

---

## 7. Destroy flow — drain contract

| Verb          | Drain preconditions (F7)                                    | B5 action |
|---------------|-------------------------------------------------------------|-----------|
| `destroy_qp`  | If RTS: QPEN=0, wait `SQPIi == STATCURSQPTRi`. In B5 always INIT, so no drain. | zero QCSR, free DDR4 slot |
| `destroy_cq`  | Bound QP destroyed first (ib_core refcount). | mark unbound, no-op |
| `dereg_mr`    | No QP binds this PD's MR (ib_core destroys QPs first). | zero 8 PDT regs, free DDR4 MR slice, clear `pd->mr` |
| `dealloc_pd`  | `pd->mr == NULL` (ib_core refcount, defensive check). | clear bitmap bit |

---

## 8. Concurrency

- All B5 verbs run in process context (uverbs syscall). No ISR path touches
  these create/destroy writes.
- `pd->mr_lock` guards the single-MR-per-PD invariant.
- `onic_ddr_pool::{qp_lock, mr_lock}` are taken with IRQs disabled (the
  same pools are read from F5 ISR top halves for decoding QP IDs from bank
  bits — see F5 `ernic_qpid_from_bank()`; B5 itself doesn't need that, but
  keep IRQ-safe so future ISR paths can join).
- `qp->state_lock` is allocated but only matters from B6 onward (transitions
  happen under it).
- MMIO writes to QCSR within a single `create_qp` are serialized by the
  fact that only one thread owns the new QP index; no cross-QP ordering is
  needed yet.

---

## 9. Userspace libonic changes

The stubs at `libonic.c:70..113` become real `ibv_cmd_*` passthroughs. No
driver-private cmd/resp extensions needed — the stock uverbs ABI carries
everything we need for B5.

### 9.1 `create_cq`

```c
static struct ibv_cq *
onic_create_cq(struct ibv_context *ctx, int cqe,
	       struct ibv_comp_channel *ch, int comp_vector)
{
	struct ibv_create_cq           cmd  = {};
	struct ib_uverbs_create_cq_resp resp = {};
	struct ibv_cq                 *cq   = calloc(1, sizeof(*cq));
	int ret;

	if (!cq) { errno = ENOMEM; return NULL; }
	ret = ibv_cmd_create_cq(ctx, cqe, ch, comp_vector, cq,
				&cmd, sizeof(cmd), &resp, sizeof(resp));
	if (ret) { free(cq); return NULL; }
	return cq;
}

static int onic_destroy_cq(struct ibv_cq *cq)
{
	int ret = ibv_cmd_destroy_cq(cq);
	if (ret) return ret;
	free(cq);
	return 0;
}
```

### 9.2 `create_qp`

```c
static struct ibv_qp *
onic_create_qp(struct ibv_pd *pd, struct ibv_qp_init_attr *init_attr)
{
	struct ibv_create_qp           cmd  = {};
	struct ib_uverbs_create_qp_resp resp = {};
	struct ibv_qp                 *qp   = calloc(1, sizeof(*qp));
	int ret;

	if (!qp) { errno = ENOMEM; return NULL; }
	ret = ibv_cmd_create_qp(pd, qp, init_attr,
				&cmd, sizeof(cmd), &resp, sizeof(resp));
	if (ret) { free(qp); return NULL; }
	return qp;
}

static int onic_destroy_qp(struct ibv_qp *qp)
{
	int ret = ibv_cmd_destroy_qp(qp);
	if (ret) return ret;
	free(qp);
	return 0;
}
```

### 9.3 `reg_mr` / `dereg_mr`

```c
static struct ibv_mr *
onic_reg_mr(struct ibv_pd *pd, void *addr, size_t length,
	    uint64_t hca_va, int access)
{
	struct ibv_reg_mr          cmd  = {};
	struct ib_uverbs_reg_mr_resp resp = {};
	struct verbs_mr           *vmr  = calloc(1, sizeof(*vmr));
	int ret;

	if (!vmr) { errno = ENOMEM; return NULL; }
	ret = ibv_cmd_reg_mr(pd, addr, length, hca_va, access, vmr,
			     &cmd, sizeof(cmd), &resp, sizeof(resp));
	if (ret) { free(vmr); return NULL; }
	return &vmr->ibv_mr;
}

static int onic_dereg_mr(struct verbs_mr *vmr)
{
	int ret = ibv_cmd_dereg_mr(vmr);
	if (ret) return ret;
	free(vmr);
	return 0;
}
```

**VERIFY:** exact signature of `ibv_cmd_reg_mr` in the installed rdma-core
(OFED 26.01). The prototype varies across releases — some take
`(pd, addr, length, hca_va, access, vmr, cmd, cmd_sz, resp, resp_sz)`,
others bundle cmd/resp. Inspect `/usr/include/infiniband/cmd_*.h` headers
before applying.

---

## 10. Test plan

| Phase | Gate |
|-------|------|
| 1 | Module compiles with `make -C open-nic-driver`. No new warnings. |
| 2 | `sudo insmod onic.ko`, `ibv_devinfo -v` unchanged from B3. |
| 3 | Micro test program: `alloc_pd → reg_mr(64 KiB) → create_cq(128) → create_qp(RC, send=recv=cq) → destroy_qp → destroy_cq → dereg_mr → dealloc_pd`. All seven calls return 0. |
| 4 | `sudo ibv_rc_pingpong -d onic_0100 -g 0` — reaches `ibv_modify_qp`, fails with `EOPNOTSUPP`. Kernel log quiet (no WARN/BUG). |
| 5 | `rmmod onic` clean. `dmesg` shows no leaked refs or "BUG: ". `cat /proc/slabinfo | grep onic` stable across 10 insmod/rmmod cycles. |
| 6 | Probe QCSR post-create_qp: `devmem` the `QPCONFi`/`SQBAi`/`CQBAi`/`PDi` registers for the allocated QP index, confirm values match what the driver wrote. |
| 7 | Probe PDT row post-reg_mr: `devmem` the 8 registers at `RN_RDMA_BASE_ADDRESS + pdn*0x100`, confirm they match. |

Phases 6–7 are the concrete hardware-touching correctness gates; don't
declare B5 done without them.

---

## 11. Patch sketch — file-by-file LoC estimate

| File                                          | Kind     | LoC | Summary |
|-----------------------------------------------|----------|-----|---------|
| `open-nic-driver/onic_ddr_alloc.h`            | new      |  80 | Queue-slot bitmap + MR bitmap + helpers. |
| `open-nic-driver/onic_ddr_alloc.c`            | new      | 110 | Implementations of the 5 API fns. |
| `open-nic-driver/onic_ib.h`                   | modified | +60 | `struct onic_mr/_cq/_qp`, extend `onic_pd`, embed `onic_ddr_pool` into `onic_ib_dev`. |
| `open-nic-driver/onic_ib.c`                   | modified | +340 / −20 | Replace 4 stub pairs (reg/dereg_mr, create/destroy_cq, create/destroy_qp; PD tweaks); wire ops table entries; `INIT_RDMA_OBJ_SIZE` for mr/cq/qp. |
| `open-nic-driver/Makefile`                    | modified | +1 | Add `onic_ddr_alloc.o` to module object list. |
| `libonic-provider/libonic.c`                  | modified | +70 / −40 | Replace 4 pairs of stubs with `ibv_cmd_*` passthroughs. |

**Net new driver code:** ~600 LoC.
**Net new userspace provider code:** ~70 LoC.
**Grand total B5 sketch:** ~670 LoC.

Ops-table hookups (`onic_ib.c`):

```c
/* Replace the STUB_BODY lines in onic_ib_ops with these. */
.create_cq    = onic_create_cq,
.destroy_cq   = onic_destroy_cq,
.create_qp    = onic_create_qp,
.destroy_qp   = onic_destroy_qp,
.reg_user_mr  = onic_reg_user_mr,
.dereg_mr     = onic_dereg_mr,
/* ... modify_qp / post_send / post_recv / poll_cq / req_notify_cq stay
 *     as B3 STUB_BODY until B6/B7/B8. ... */

INIT_RDMA_OBJ_SIZE(ib_ucontext, onic_ucontext, ibucontext),
INIT_RDMA_OBJ_SIZE(ib_pd,       onic_pd,       ibpd),
INIT_RDMA_OBJ_SIZE(ib_cq,       onic_cq,       ibcq),
INIT_RDMA_OBJ_SIZE(ib_qp,       onic_qp,       ibqp),
```

And in `onic_ib_register()`:

```c
/* After bitmap_zero(dev->pd_bitmap, ...): */
onic_ddr_pool_init(&dev->ddr, 0 /* ERNIC0 */);
```

Matching `onic_ddr_pool_fini(&dev->ddr)` before `ib_dealloc_device` in
`onic_ib_unregister()`.

---

## 12. Risks and VERIFY items

1. **DDR4-only MR restriction.** B5 only accepts MRs that can be backed by
   DDR4 staging. Host-memory MR needs the s_axib bridge (B2), which is
   still pending. `ibv_rc_pingpong` registers a small user buffer — we
   will happily allocate DDR4 backing for it and let the pingpong payload
   land in DDR4 rather than host memory. Passing traffic may look odd in
   DMA traces; document this clearly. **Blocker if B5 must support
   host-memory MRs — in that case, B2 lands first.**

2. **CQ-per-QP model.** ERNIC's CQ is per-QP. ibverbs lets apps share
   CQs. B5 rejects CQ sharing with `-EINVAL`. `ibv_rc_pingpong` uses one
   CQ for send+recv on the *same* QP — that's allowed (see §6 code).
   Apps that share one CQ across multiple QPs will fail
   `ibv_create_qp`. Flag for human sign-off: is this acceptable as a
   Track B restriction? **Biggest design call in B5.**

3. **PDT-row == rkey collision.** `lkey == rkey == pdn ∈ [0,255]`. A
   remote host sending RDMA WRITE with an rkey that happens to match an
   in-use PDT row will hit our MR. Track B's "controlled deployments
   only" premise covers this; formal rkey derivation (e.g.,
   `(pdn << 8) | random_tag`, masked down to what BUFRKEY accepts — F1
   says BUFRKEY is 8 bits, so our rkey space is *already* only 256 values
   driver-wide) is a B5.5 topic. **VERIFY:** PG332 line 3793 — whether
   BUFRKEY is really just 8 bits or whether we can widen via an
   undocumented field.

4. **QPCONFi[RQBUFSZ] encoding.** Code uses `rq_depth << 16` assuming
   RQBUFSZ is the RQ depth in 256-B units. F1 §5.2 wasn't crisp on this.
   **VERIFY** against PG332 before applying — may need to be
   `rq_depth * bytes_per_wqe / 256`.

5. **TIMEOUTCONFi defaults.** B5 doesn't program it (INIT, not RTR). B6
   will. Note suggested defaults for B6: timeout=0x14 (~5 ms),
   max_retry=3, max_rnr_retry=6, rnr_timeout=0x14.

6. **Ordering vs MSI-X ISR.** F5 ISR top-half increments per-source
   counters. Between `create_qp` programming QCSR and B6 setting QPEN=1,
   no ERNIC activity should reach this QP's bank bit; but if a spurious
   INTSTS fires (e.g., bank bit for QP index 2 on an unrelated fatal),
   the bottom-half might reach into a QP context that is still mid-create.
   **Mitigation:** the ISR bottom half should check `qp->state >= INIT`
   before touching. Since B5 only transitions up to INIT, and F5's bottom
   half currently only increments counters (per F5 plan), no code change
   is needed for B5 — but call it out so B6 honors it.

7. **Stock `ibv_cmd_create_qp`/`create_cq`/`reg_mr`.** These emit
   vanilla uverbs commands; kernel ib_core fills the standard fields into
   `ib_qp_init_attr`, `ib_cq_init_attr`, `reg_user_mr(start, length,
   virt_addr, access, ...)`. No driver-private extensions needed.
   **VERIFY** the exact prototypes in the installed `rdma-core` headers
   (OFED 26.01) before applying.

8. **`dev->ddr` embedded in `onic_ib_dev`.** B5 treats the allocator as
   per-ib_device. Works because we have ONE ib_device and ONE ERNIC
   today; extending to ERNIC1 requires either a second ib_device or a
   per-port allocator (F4 §2.2 envisions the split). Flag as B5 scope
   boundary.

9. **`iowrite32` barrier semantics.** We issue a read-back after each
   group to flush posted writes. Standard Linux PCIe idiom; matches
   existing onic register accessors.

10. **ERNIC must see DDR4 offsets within its region.** `onic_ddr_addr_msb`
    returns `0xa3500000` for ERNIC0 (base_off=0) and `0xa3500002` for
    ERNIC1 (base_off=0x2_0000_0000). `phase_f4_ddr4_address_probe`
    already confirmed both ERNICs round-trip the full 34-bit range (F4
    update block). Should be fine; re-run that probe post-B5 as a
    regression guard.

---

## 13. Why this shape, not something grander

- **No host-memory MR:** would force B2 s_axib first. B5 is already
  ~700 LoC; adding the bridge doubles the scope.
- **No alloc_mr / fastreg:** `ibv_rc_pingpong` doesn't need it. Defer.
- **No CQ sharing:** ERNIC's one-CQ-per-QP makes shared CQs a full
  emulation layer. Out of scope for the first-real-verbs milestone.
- **Single MR size class:** the F4 5-class allocator is the right
  long-term shape, but B5 only needs one class to unblock pingpong.
  The API (`onic_ddr_mr_alloc(size)`) is class-agnostic; B10 just adds
  more bitmaps.

Everything B5 defers is scoped with a specific downstream story (B6/B7/
B8/B10), not "someday". That's the point.

---

## 14. Appendix — call-out of the exact PG332/F1 lines

- PG332 lines 3562–3660: "RC QP Creation" — the sequence we implement in
  §6.2 is the first two steps of this section (program QCSR, don't set
  QPEN yet). Steps 3+ (DESTQPCONF, MACDESADD, PSN, QPEN=1) are B6.
- PG332 lines 3660–3720: "QP Deletion" — drain rule used in §7. B5's
  INIT-only state means drain is trivially satisfied.
- PG332 lines 3720–3800: "QP Fatal Recovery" — not exercised in B5; noted
  in §12.6.
- PG332 line 3793: `ACCESSDESC[1:0]` encoding (`0b10 = remote write`,
  `0b01 = remote read`, `0b11 = both`). Source for §4.2 `access_desc`
  translation.
- F1 §5.1.2: PDT entry register layout (the 8 × 32b rows). Ground truth
  for §4.2 register writes.
- F1 §5 (QCSR table): register offsets `0x00..0xD8` inside a QP slot.
  Ground truth for §6.2 register writes.
- F1 §5.4: QP0 / QP1 reserved; `XRNIC_CONF_QP_EN` semantics. B5 doesn't
  touch `XRNIC_CONF_QP_EN` — that's a B6 job right before `QPEN=1`.
- F7 §2 / §3: PD / MR 1:1 constraint → §3 and §4.
- F7 §4: CQ lifecycle; deferred-programming rationale for §5.2.
- F7 §5.1: RESET→INIT transition — what §6.2 implements exactly.
