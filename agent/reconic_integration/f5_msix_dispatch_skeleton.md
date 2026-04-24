# F5 — MSI-X Dispatch Skeleton for ERNIC0 / ERNIC1

**Status:** design + patch sketch only. Nothing applied to source.
**Last updated:** 2026-04-23.
**Prereqs landed:** F1 register audit (reconic_reg.h fixed), F7 lifecycle header.
**Depends on:** dual-CMAC MSI-X layout in `onic_lib.c::onic_acquire_msix_vectors`
(master PF: `2 × q_per_cmac + non_q_vectors`; secondary inherits from primary).
**Unblocks:** B7 PD/MR attach, B8 CQ polling + event delivery, B9 QP state
machine — all need a live ISR path before they can wire anything up.

---

## 1. Goals and scope

**In scope for F5:**

1. Reserve MSI-X vectors for ERNIC0 and ERNIC1 interrupt aggregation on the
   master PF during probe.
2. Register two ISR stubs (one per ERNIC) that
   (a) read the corresponding `INTSTS` register,
   (b) W1C-ack it *before* scheduling any work,
   (c) increment per-source atomic counters,
   (d) schedule a bottom-half work item that dumps
   `RQINTSTSn / CQINTSTSn / CNPSCHDSTSn` at `pr_debug` level.
3. Enable the ERNIC `INTEN` bits the driver expects to own
   (PKTVALERR, MADRX, RNRNACKGEN, WQECOMPL, ILLOPCODE, RQPKT, FATALERR,
   CNPSCHD — everything except the reserved bit 2).
4. Expose per-source counters via debugfs under
   `/sys/kernel/debug/onic/<pf>/ernic[01]/`.
5. Matching teardown on `onic_remove`: disable `INTEN`, `free_irq`,
   `cancel_work_sync`, remove debugfs entries.

**Explicitly out of scope (deferred to later tasks):**

- Actual CQ/WQE completion delivery (B8).
- QP state-machine transitions on FATAL/RNR (B9).
- Sharing ERNIC IRQs with the secondary netdev. ERNIC0/ERNIC1 belong to the
  master PF only; the secondary netdev never owns ERNIC resources directly in
  the one-PF design (see `MEMORY.md → RDMA Architecture Decision`).
- Any `ib_device` registration. F5 precedes that.

---

## 2. Vector budget decision

**Pick Option A: one MSI-X vector per ERNIC, software demux on `INTSTS`.**

| Option | Vectors used | Pros | Cons |
|---|---|---|---|
| A (chosen) | 2 (one per ERNIC) | Minimal MSI-X pressure; matches ERNIC HW aggregation model — all 9 bits already OR into one IRQ line at the ERNIC boundary. | One ISR demux on every fire. Fine — 1 `ioread32` cost. |
| B (per-source) | 16 (8 × 2 ERNICs) | Per-source latency isolation. | ERNIC v4.2 does NOT expose per-bit IRQ lines — it aggregates internally. You'd have to add RTL to split them. Not a SW-only change. **VERIFY:** PG332 §3 confirms single-wire aggregation per ERNIC instance. |
| C (hybrid) | 4 (fatal + non-fatal × 2) | Nice to have for latency. | Same RTL-change dependency as B. |

Option A also preserves MSI-X headroom for the QDMA queue vectors
(`2 × q_per_cmac`, currently 128) and the existing user / error IRQs.

**Upgrade path:** if completion latency becomes an issue, implement a userspace
poll-mode CQ cap first (B8 already considers this); only then revisit per-source
vectors with an RTL split. Probably never needed.

---

## 3. Interaction with the existing vector layout

Current master-PF layout (`onic_lib.c:385-425`, `onic_acquire_msix_vectors`):

```
vectors requested = 2 × q_per_cmac + non_q_vectors
  non_q_vectors = 1 (user) + 1 (error) = 2 on master
  so master requests 2 × 64 + 2 = 130.
layout (relative to vec_base=0 on primary):
  [0 .. num_q_vectors-1]             — primary's CMAC0 queue vectors
  [num_q_vectors]                    — user IRQ   (primary only; see onic_lib.c:488)
  [num_q_vectors + 1]                — error IRQ  (master only; see onic_lib.c:500)
  [num_q_vectors + 2 .. 2*num_q_vectors + 1] — secondary's CMAC1 queue vectors
```

Secondary's `vec_base = primary->num_q_vectors + non_q` computed at
`onic_main.c:369-373` (where `non_q = 1 + MASTER_PF ? 1 : 0 = 2`).

**F5 change:**

```
non_q_vectors on master becomes 1 + 1 + 2 = 4  (user + error + ernic0 + ernic1)
vectors requested = 2 × q_per_cmac + non_q_vectors  = 132
layout:
  [0 .. num_q_vectors-1]             — primary's CMAC0 queue vectors
  [num_q_vectors]                    — user IRQ
  [num_q_vectors + 1]                — error IRQ
  [num_q_vectors + 2]                — ERNIC0 IRQ       (NEW)
  [num_q_vectors + 3]                — ERNIC1 IRQ       (NEW)
  [num_q_vectors + 4 .. 2*num_q_vectors + 3] — secondary's CMAC1 queue vectors
```

Secondary `vec_base` becomes `primary->num_q_vectors + 4`. The code in
`onic_main.c:369-373` is a `non_q` counter that we extend, so the arithmetic
stays parameterised — no magic constants to chase.

**VERIFY:** `MSIX_CAP` in dmesg under the current bitstream. QDMA Subsystem
PG302 advertises up to 2048 MSI-X; OpenNIC shells typically run with 32 or 64
available. If the fallback allocation in `pci_alloc_irq_vectors` (lower bound
`non_q_vectors + 1`) reduces to fewer than we requested, the existing code in
`onic_acquire_msix_vectors` already degrades `num_q_vectors` gracefully. The
two new ERNIC vectors are in the `non_q_vectors` floor, so they are guaranteed
allocated (or probe fails) — exactly what we want.

---

## 4. Code structure

### New files (not yet applied)

- `open-nic-driver/onic_ernic_irq.h` — public prototypes + per-ERNIC context struct.
- `open-nic-driver/onic_ernic_irq.c` — ISR, bottom half, setup/teardown, debugfs.

### Touched existing files

| File | Change | Size (est. LoC) |
|---|---|---|
| `onic.h` | Add `struct onic_ernic_irq_ctx ernic_irq[2]` + debugfs root dentry to `struct onic_private`. | +8 |
| `onic_lib.c` | Bump `non_q_vectors` by 2 on master in `onic_acquire_msix_vectors`. | +3 |
| `onic_main.c` | Call `onic_ernic_irq_setup(primary)` after `onic_init_interrupt` and before `register_netdev`; call `onic_ernic_irq_teardown(primary)` inside `onic_teardown_netdev` before `onic_clear_interrupt`. Adjust secondary `vec_base` arithmetic automatically (the `non_q` local in `onic_setup_secondary` already reads from `MASTER_PF` flag — we just extend it by 2). | +10 |
| `Makefile` | Add `onic_ernic_irq.o` to `onic-objs`. | +1 |
| `onic_hardware.c` | No change. ERNIC register space is inside the existing `pci_iomap_range(pdev, 2, SHELL_START=0, SHELL_MAXLEN=0x1000000)` map (see `onic_hardware.c:269`), and `reconic_reg.h` offsets (e.g. `RN_RDMA_GCSR_INTSTS = 0x00800000 + 0x00100184`) already include the `RN_RDMA_BASE_ADDRESS`. We can `ioread32/iowrite32(hw->addr + offset)` directly. | 0 |

Total new LoC: roughly **220** across 2 new files + 4 edits — well under the
150-per-file guidance, counting docstrings.

---

## 5. Per-ERNIC context struct

```c
/* onic_ernic_irq.h */
#ifndef __ONIC_ERNIC_IRQ_H__
#define __ONIC_ERNIC_IRQ_H__

#include <linux/workqueue.h>
#include <linux/atomic.h>
#include <linux/debugfs.h>

struct onic_private;

/**
 * struct onic_ernic_irq_ctx - per-ERNIC MSI-X dispatch context
 *
 * There are two of these per master PF, one for ERNIC0 and one for ERNIC1.
 * The ISR reads INTSTS at ernic_base + 0x100184, W1C-acks it, and schedules
 * event_work for RQINTSTS/CQINTSTS/CNPSCHDSTS dumping.
 */
struct onic_ernic_irq_ctx {
	struct onic_private *priv;       /* back-pointer */
	u8                   index;      /* 0 or 1 — which ERNIC */
	u32                  ernic_base; /* 0x00800000 (ERNIC0) or 0x00A00000 (ERNIC1) */
	int                  msix_vid;   /* relative vector ID within master's pool */
	int                  irq;        /* resolved cookie from pci_irq_vector */
	bool                 registered; /* true once request_irq succeeded */
	struct work_struct   event_work;

	/* Latched INTSTS value from the last ISR fire, consumed by event_work.
	 * A single u32 is sufficient because the ISR W1C-clears before scheduling
	 * work and atomic_or accumulates any racing bits. */
	atomic_t             pending_intsts;

	/* Per-source counters — exposed via debugfs. */
	atomic_t             pktvalerr_count;   /* INTSTS[0] */
	atomic_t             madrx_count;       /* INTSTS[1] */
	atomic_t             rnrnackgen_count;  /* INTSTS[3] */
	atomic_t             wqecompl_count;    /* INTSTS[4] */
	atomic_t             illopcode_count;   /* INTSTS[5] */
	atomic_t             rqpkt_count;       /* INTSTS[6] */
	atomic_t             fatal_count;       /* INTSTS[7] */
	atomic_t             cnpschd_count;     /* INTSTS[8] */
	atomic_t             spurious_count;    /* INTSTS==0 on entry */
	atomic_t             total_count;       /* any ISR fire */

	/* debugfs entries; NULL on non-debugfs kernels. */
	struct dentry       *dfs_dir;
};

int  onic_ernic_irq_setup(struct onic_private *priv);
void onic_ernic_irq_teardown(struct onic_private *priv);

#endif /* __ONIC_ERNIC_IRQ_H__ */
```

Add to `struct onic_private` (onic.h:183):

```c
	/* ERNIC MSI-X dispatch (master PF only).  [0] = ERNIC0 (BAR2+0x800000),
	 * [1] = ERNIC1 (BAR2+0xA00000).  The index field disambiguates the ctx
	 * pointer the ISR receives. */
	struct onic_ernic_irq_ctx ernic_irq[2];
	struct dentry            *dfs_root;   /* /sys/kernel/debug/onic/<name>/ */
```

---

## 6. ISR body (sketch)

All register constants come from
`/home/alex/mpi-shfs/fpga/libreconic/reconic_reg.h` (F1 audit, 2026-04-23).

The offsets in that header are **absolute against BAR2** — e.g.
`RN_RDMA_GCSR_INTSTS = 0x00800000 + 0x00100184 = 0x00900184` for ERNIC0. For
the dual-port case, the F5 ISR must compute per-port offsets, not rely on the
hard-coded `RN_RDMA_BASE_ADDRESS`. Use the helper approach below.

```c
/* onic_ernic_irq.c — top */
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/debugfs.h>
#include "onic.h"
#include "onic_hardware.h"
#include "onic_ernic_irq.h"

/* Offsets within a single ERNIC's 2 MB slice (identical for ERNIC0 and
 * ERNIC1; apply ctx->ernic_base). These mirror reconic_reg.h after F1 but
 * expressed relative to the ERNIC base so both ports use the same macros. */
#define ERNIC_OFFSET_INTEN                0x00100180
#define ERNIC_OFFSET_INTSTS               0x00100184
#define ERNIC_OFFSET_RQINTSTS_BASE        0x00100190  /* 64 banks × 4 bytes */
#define ERNIC_OFFSET_CQINTSTS_BASE        0x00100290
#define ERNIC_OFFSET_CNPSCHDSTS_BASE      0x00100390

/* INTSTS / INTEN bit positions — per F1 audit §5.3, PG332 v4.2 Table 8. */
#define ERNIC_INTSTS_PKTVALERR     BIT(0)
#define ERNIC_INTSTS_MADRX         BIT(1)
/* bit 2 RSVD */
#define ERNIC_INTSTS_RNRNACKGEN    BIT(3)
#define ERNIC_INTSTS_WQECOMPL      BIT(4)
#define ERNIC_INTSTS_ILLOPCODE     BIT(5)
#define ERNIC_INTSTS_RQPKT         BIT(6)
#define ERNIC_INTSTS_FATALERR      BIT(7)
#define ERNIC_INTSTS_CNPSCHD       BIT(8)
#define ERNIC_INTSTS_ALL_OWNED     (ERNIC_INTSTS_PKTVALERR   | \
                                    ERNIC_INTSTS_MADRX       | \
                                    ERNIC_INTSTS_RNRNACKGEN  | \
                                    ERNIC_INTSTS_WQECOMPL    | \
                                    ERNIC_INTSTS_ILLOPCODE   | \
                                    ERNIC_INTSTS_RQPKT       | \
                                    ERNIC_INTSTS_FATALERR    | \
                                    ERNIC_INTSTS_CNPSCHD)

static inline u32 ernic_rd(struct onic_private *priv,
			   struct onic_ernic_irq_ctx *ctx, u32 off)
{
	return ioread32(priv->hw.addr + ctx->ernic_base + off);
}

static inline void ernic_wr(struct onic_private *priv,
			    struct onic_ernic_irq_ctx *ctx, u32 off, u32 val)
{
	iowrite32(val, priv->hw.addr + ctx->ernic_base + off);
}

static irqreturn_t onic_ernic_isr(int irq, void *data)
{
	struct onic_ernic_irq_ctx *ctx = data;
	struct onic_private       *priv = ctx->priv;
	u32 intsts;

	/* Probe / torn-down guard: priv->hw.addr is only valid between
	 * onic_init_hardware and onic_clear_hardware. */
	if (unlikely(!priv || !priv->hw.addr))
		return IRQ_NONE;

	intsts = ernic_rd(priv, ctx, ERNIC_OFFSET_INTSTS);
	if (!intsts) {
		atomic_inc(&ctx->spurious_count);
		return IRQ_NONE;
	}

	/* W1C-ack BEFORE scheduling work.  Doing the ack first prevents an
	 * edge-retrigger loop where the bottom half reads RQINTSTS banks slowly
	 * and new bits latch into INTSTS while we're still processing the old
	 * ones.  We don't lose events because RQINTSTS/CQINTSTS banks are W1C
	 * independently of INTSTS — reading them in the bottom half still sees
	 * the bits set. */
	ernic_wr(priv, ctx, ERNIC_OFFSET_INTSTS, intsts);

	/* Accumulate bits into the pending snapshot for the bottom half.  If
	 * work is already queued from a previous fire, this OR just adds our
	 * bits to it; schedule_work is idempotent. */
	atomic_or(intsts, &ctx->pending_intsts);

	atomic_inc(&ctx->total_count);
	if (intsts & ERNIC_INTSTS_PKTVALERR)  atomic_inc(&ctx->pktvalerr_count);
	if (intsts & ERNIC_INTSTS_MADRX)      atomic_inc(&ctx->madrx_count);
	if (intsts & ERNIC_INTSTS_RNRNACKGEN) atomic_inc(&ctx->rnrnackgen_count);
	if (intsts & ERNIC_INTSTS_WQECOMPL)   atomic_inc(&ctx->wqecompl_count);
	if (intsts & ERNIC_INTSTS_ILLOPCODE)  atomic_inc(&ctx->illopcode_count);
	if (intsts & ERNIC_INTSTS_RQPKT)      atomic_inc(&ctx->rqpkt_count);
	if (intsts & ERNIC_INTSTS_FATALERR)   atomic_inc(&ctx->fatal_count);
	if (intsts & ERNIC_INTSTS_CNPSCHD)    atomic_inc(&ctx->cnpschd_count);

	schedule_work(&ctx->event_work);
	return IRQ_HANDLED;
}
```

### Bottom half (stub)

```c
static void onic_ernic_event_worker(struct work_struct *w)
{
	struct onic_ernic_irq_ctx *ctx =
		container_of(w, struct onic_ernic_irq_ctx, event_work);
	struct onic_private       *priv = ctx->priv;
	u32 pending, rq, cq, cnp;
	int i;

	/* Drain pending bits.  Any races with a concurrent ISR are harmless —
	 * the ISR only adds bits via atomic_or. */
	pending = atomic_xchg(&ctx->pending_intsts, 0);
	if (!pending)
		return;

	pr_debug("onic-ernic%u: intsts=0x%03x (fatal=%d wqe_compl=%d rqpkt=%d cnpschd=%d)\n",
		 ctx->index, pending,
		 atomic_read(&ctx->fatal_count),
		 atomic_read(&ctx->wqecompl_count),
		 atomic_read(&ctx->rqpkt_count),
		 atomic_read(&ctx->cnpschd_count));

	/* Dump RQ/CQ/CNP status banks to identify which QPs signaled.  64 banks
	 * × 4 bytes each; read only the ones the pending bit says are relevant
	 * to keep BAR traffic bounded.  NOTE: These per-bank registers are W1C
	 * per PG332 §3.1.  For F5 we don't W1C yet — the real handlers in B8/B9
	 * will own that, because clearing the bank bit without processing the
	 * completion would drop work.  F5 logs only. */
	if (pending & (ERNIC_INTSTS_RQPKT | ERNIC_INTSTS_MADRX)) {
		for (i = 1; i <= 64; i++) {
			rq = ernic_rd(priv, ctx,
				      ERNIC_OFFSET_RQINTSTS_BASE + 4 * (i - 1));
			if (rq)
				pr_debug("  ERNIC%u RQINTSTS%d = 0x%08x\n",
					 ctx->index, i, rq);
		}
	}
	if (pending & ERNIC_INTSTS_WQECOMPL) {
		for (i = 1; i <= 64; i++) {
			cq = ernic_rd(priv, ctx,
				      ERNIC_OFFSET_CQINTSTS_BASE + 4 * (i - 1));
			if (cq)
				pr_debug("  ERNIC%u CQINTSTS%d = 0x%08x\n",
					 ctx->index, i, cq);
		}
	}
	if (pending & ERNIC_INTSTS_CNPSCHD) {
		for (i = 1; i <= 64; i++) {
			cnp = ernic_rd(priv, ctx,
				       ERNIC_OFFSET_CNPSCHDSTS_BASE + 4 * (i - 1));
			if (cnp)
				pr_debug("  ERNIC%u CNPSCHDSTS%d = 0x%08x\n",
					 ctx->index, i, cnp);
		}
	}

	if (pending & ERNIC_INTSTS_FATALERR)
		dev_err(&priv->pdev->dev,
			"ERNIC%u: FATALERR — check STATRQPIDBi / STATQPi registers (not yet dumped in F5)\n",
			ctx->index);
}
```

---

## 7. Setup / teardown flow

```c
/* onic_ernic_irq.c — setup side */

static const char *ernic_irq_name(int idx)
{
	return idx == 0 ? "onic-ernic0" : "onic-ernic1";
}

static int onic_ernic_irq_setup_one(struct onic_private *priv, int idx,
				    u32 base, int rel_vid)
{
	struct onic_ernic_irq_ctx *ctx = &priv->ernic_irq[idx];
	struct pci_dev            *pdev = priv->pdev;
	int rv;

	ctx->priv       = priv;
	ctx->index      = (u8)idx;
	ctx->ernic_base = base;
	ctx->msix_vid   = rel_vid;
	ctx->irq        = pci_irq_vector(pdev, priv->vec_base + rel_vid);
	atomic_set(&ctx->pending_intsts,   0);
	atomic_set(&ctx->pktvalerr_count,  0);
	atomic_set(&ctx->madrx_count,      0);
	atomic_set(&ctx->rnrnackgen_count, 0);
	atomic_set(&ctx->wqecompl_count,   0);
	atomic_set(&ctx->illopcode_count,  0);
	atomic_set(&ctx->rqpkt_count,      0);
	atomic_set(&ctx->fatal_count,      0);
	atomic_set(&ctx->cnpschd_count,    0);
	atomic_set(&ctx->spurious_count,   0);
	atomic_set(&ctx->total_count,      0);
	INIT_WORK(&ctx->event_work, onic_ernic_event_worker);

	/* Make sure INTEN is 0 before we arm the ISR, so any stale latched
	 * bit from bitstream init doesn't immediately fire. */
	ernic_wr(priv, ctx, ERNIC_OFFSET_INTEN, 0);
	(void)ernic_rd(priv, ctx, ERNIC_OFFSET_INTEN);  /* posted-write flush */
	ernic_wr(priv, ctx, ERNIC_OFFSET_INTSTS, ~0u);  /* W1C any stale */

	rv = request_irq(ctx->irq, onic_ernic_isr, 0,
			 ernic_irq_name(idx), ctx);
	if (rv) {
		dev_err(&pdev->dev,
			"ERNIC%d request_irq failed (vec=%d irq=%d): %d\n",
			idx, priv->vec_base + rel_vid, ctx->irq, rv);
		return rv;
	}
	ctx->registered = true;

	/* Only now enable ERNIC's view of the bits.  INTEN is "mask of bits
	 * that can fire INTSTS"; FATALERR cannot be masked out per PG332 §3.1
	 * but writing it here is harmless. */
	ernic_wr(priv, ctx, ERNIC_OFFSET_INTEN, ERNIC_INTSTS_ALL_OWNED);

	dev_info(&pdev->dev,
		 "ERNIC%d IRQ setup: vec=%d irq=%d base=0x%08x inten=0x%03x\n",
		 idx, priv->vec_base + rel_vid, ctx->irq, base,
		 ERNIC_INTSTS_ALL_OWNED);
	return 0;
}

int onic_ernic_irq_setup(struct onic_private *priv)
{
	int rv;

	/* Master PF only.  Secondary netdev never owns ERNIC IRQs in the
	 * one-PF architecture (see MEMORY.md → RDMA Architecture Decision). */
	if (!test_bit(ONIC_FLAG_MASTER_PF, priv->flags))
		return 0;

	/* Relative vector IDs: user = num_q_vectors, error = num_q_vectors+1,
	 * ernic0 = num_q_vectors+2, ernic1 = num_q_vectors+3.  These must be
	 * held in sync with the bump in onic_acquire_msix_vectors (§3). */
	rv = onic_ernic_irq_setup_one(priv, 0, 0x00800000,
				      priv->num_q_vectors + 2);
	if (rv)
		return rv;

	rv = onic_ernic_irq_setup_one(priv, 1, 0x00A00000,
				      priv->num_q_vectors + 3);
	if (rv) {
		/* Unwind ERNIC0. */
		ernic_wr(priv, &priv->ernic_irq[0], ERNIC_OFFSET_INTEN, 0);
		free_irq(priv->ernic_irq[0].irq, &priv->ernic_irq[0]);
		cancel_work_sync(&priv->ernic_irq[0].event_work);
		priv->ernic_irq[0].registered = false;
		return rv;
	}

	onic_ernic_debugfs_init(priv);   /* §8 */
	return 0;
}

void onic_ernic_irq_teardown(struct onic_private *priv)
{
	int i;

	if (!test_bit(ONIC_FLAG_MASTER_PF, priv->flags))
		return;

	onic_ernic_debugfs_exit(priv);

	for (i = 0; i < 2; i++) {
		struct onic_ernic_irq_ctx *ctx = &priv->ernic_irq[i];

		if (!ctx->registered)
			continue;

		/* Disable ERNIC side first so no new IRQs arrive, then free the
		 * vector, then drain any in-flight bottom half.  Order matters:
		 * free_irq synchronises with the current ISR invocation, but
		 * work scheduled by it may still be pending. */
		ernic_wr(priv, ctx, ERNIC_OFFSET_INTEN, 0);
		(void)ernic_rd(priv, ctx, ERNIC_OFFSET_INTEN);
		free_irq(ctx->irq, ctx);
		cancel_work_sync(&ctx->event_work);
		ctx->registered = false;
	}
}
```

---

## 8. Visibility — debugfs layout

Keep this scope-appropriate: one directory per ERNIC under
`/sys/kernel/debug/onic/<netdev_name>/`, with one file per counter (read-only,
decimal). `ethtool -S` integration lands in B10 once the real `ib_device`
exposes per-QP stats; putting it in F5 would bloat `onic_ethtool.c` for a
temporary skeleton.

```c
/* onic_ernic_irq.c — debugfs */
#ifdef CONFIG_DEBUG_FS

#define DEF_COUNTER(fld) do {                                            \
	debugfs_create_atomic_t(#fld, 0444, dir, &ctx->fld);              \
} while (0)

static void onic_ernic_debugfs_init_one(struct onic_private *priv, int idx)
{
	struct onic_ernic_irq_ctx *ctx = &priv->ernic_irq[idx];
	struct dentry             *dir;
	char name[8];

	if (!priv->dfs_root)
		return;

	snprintf(name, sizeof(name), "ernic%d", idx);
	dir = debugfs_create_dir(name, priv->dfs_root);
	if (IS_ERR_OR_NULL(dir))
		return;
	ctx->dfs_dir = dir;

	debugfs_create_x32("ernic_base", 0444, dir, &ctx->ernic_base);
	debugfs_create_u32("msix_vid",   0444, dir, (u32 *)&ctx->msix_vid);
	DEF_COUNTER(pktvalerr_count);
	DEF_COUNTER(madrx_count);
	DEF_COUNTER(rnrnackgen_count);
	DEF_COUNTER(wqecompl_count);
	DEF_COUNTER(illopcode_count);
	DEF_COUNTER(rqpkt_count);
	DEF_COUNTER(fatal_count);
	DEF_COUNTER(cnpschd_count);
	DEF_COUNTER(spurious_count);
	DEF_COUNTER(total_count);
}

static void onic_ernic_debugfs_init(struct onic_private *priv)
{
	priv->dfs_root = debugfs_create_dir(priv->netdev->name, NULL);
	if (IS_ERR_OR_NULL(priv->dfs_root)) {
		priv->dfs_root = NULL;
		return;
	}
	onic_ernic_debugfs_init_one(priv, 0);
	onic_ernic_debugfs_init_one(priv, 1);
}

static void onic_ernic_debugfs_exit(struct onic_private *priv)
{
	debugfs_remove_recursive(priv->dfs_root);
	priv->dfs_root             = NULL;
	priv->ernic_irq[0].dfs_dir = NULL;
	priv->ernic_irq[1].dfs_dir = NULL;
}

#else  /* !CONFIG_DEBUG_FS */
static inline void onic_ernic_debugfs_init(struct onic_private *priv) {}
static inline void onic_ernic_debugfs_exit(struct onic_private *priv) {}
#endif
```

**VERIFY:** `debugfs_create_atomic_t` is available on our kernel (present since
5.5). The current host kernel (6.8 per env) has it.

---

## 9. Test plan

### Phase 1 — Compile only

- `make -C ../kernel M=$PWD` against the host kernel headers.
- Expect zero new warnings. The `onic-objs` addition is the only Makefile
  touch.

### Phase 2 — Probe success (no traffic)

- `sudo rmmod onic && sudo insmod onic.ko debug_level=1`.
- Check dmesg for:
  - `Allocated 132 MSI-X vectors, 64 queue vectors` (was 130 / 64 before F5 —
    2 more vectors).
  - Two lines: `ERNIC0 IRQ setup: vec=66 irq=... base=0x00800000 inten=0x1fb`
    and `ERNIC1 IRQ setup: vec=67 irq=... base=0x00a00000 inten=0x1fb`.
    (Offsets derived from Option A; `0x1fb = all 9 bits except RSVD bit 2`.)
- `cat /proc/interrupts | grep onic-ernic` — expect two rows, counts = 0.
- `ls /sys/kernel/debug/onic/<pf>/ernic0/` — 11 counter files.

### Phase 3 — ISR fires

- Use `phase_f2_roce_inject.py` (existing F2 bring-up script) to send a bad
  RoCE packet with a busted ICRC at ERNIC0. Expected: `PKTVALERR` bit 0
  latches.
- `cat /sys/kernel/debug/onic/<pf>/ernic0/pktvalerr_count` should advance by 1
  per injected bad packet. `total_count` should match.
- `/proc/interrupts` row for `onic-ernic0` should also advance.
- Enable `dyndbg`: `echo 'file onic_ernic_irq.c +p' >/sys/kernel/debug/dynamic_debug/control`
  and observe per-fire `intsts=...` lines.
- Repeat with a packet into ERNIC1 to confirm the per-port demux.

### Phase 4 — Teardown

- `sudo rmmod onic` with IRQs actively firing. Expected: no oops, no hang,
  debugfs directory disappears, `/proc/interrupts` rows vanish.

---

## 10. Patch sketch (new files and diffs)

> **Review before applying.** These are sketches, not tested patches. Line
> numbers reference current file state as read on 2026-04-23.

### 10.1 New file: `open-nic-driver/onic_ernic_irq.h`

See §5 for full contents.

### 10.2 New file: `open-nic-driver/onic_ernic_irq.c`

Concatenate §6, §7, and §8 code blocks into a single file. Add the standard
Xilinx BSD/GPL dual-license header (copy from top of `onic_lib.c`). Estimated
~300 lines total including comments and the debugfs stubs.

### 10.3 Diff: `open-nic-driver/onic.h`

```c
 #include "onic_hardware.h"
 #include "onic_ptp.h"
+#include "onic_ernic_irq.h"
```

Inside `struct onic_private`, after the existing `peer` field (onic.h:251):

```c
 	struct onic_private *peer;
+
+	/* ERNIC MSI-X dispatch (master PF only — zero-initialised on secondary
+	 * and non-master PFs, teardown is a no-op there).
+	 * [0] = ERNIC0 (BAR2 + 0x800000), [1] = ERNIC1 (BAR2 + 0xA00000). */
+	struct onic_ernic_irq_ctx ernic_irq[2];
+	struct dentry            *dfs_root;
 };
```

### 10.4 Diff: `open-nic-driver/onic_lib.c::onic_acquire_msix_vectors`

Around line 389-391 (current `non_q_vectors` calculation):

```c
 	non_q_vectors = 1; /* user interrupt */
-	if (test_bit(ONIC_FLAG_MASTER_PF, priv->flags))
-		non_q_vectors++; /* + error interrupt */
+	if (test_bit(ONIC_FLAG_MASTER_PF, priv->flags)) {
+		non_q_vectors++; /* + error interrupt */
+		non_q_vectors += 2; /* + ERNIC0 IRQ + ERNIC1 IRQ (F5) */
+	}
```

### 10.5 Diff: `open-nic-driver/onic_main.c::onic_setup_secondary`

Around line 369-373. The existing logic already computes `non_q` from
`MASTER_PF`, so extending it by 2 keeps the secondary's `vec_base` correct
automatically:

```c
 		u16 non_q = 1; /* user IRQ */
-		if (test_bit(ONIC_FLAG_MASTER_PF, primary->flags))
-			non_q++; /* + error IRQ */
+		if (test_bit(ONIC_FLAG_MASTER_PF, primary->flags)) {
+			non_q++;     /* + error IRQ */
+			non_q += 2;  /* + ERNIC0 + ERNIC1 IRQs (F5) */
+		}
 		priv->vec_base = primary->num_q_vectors + non_q;
```

### 10.6 Diff: `open-nic-driver/onic_main.c::onic_setup_primary`

After `onic_init_interrupt` (line 315) and before `netif_set_real_num_tx_queues`
(line 321):

```c
 	rv = onic_init_interrupt(priv);
 	if (rv < 0) {
 		dev_err(&pdev->dev, "onic_init_interrupt (primary), err = %d", rv);
 		goto clear_hardware;
 	}
+
+	rv = onic_ernic_irq_setup(priv);
+	if (rv < 0) {
+		dev_err(&pdev->dev, "onic_ernic_irq_setup, err = %d", rv);
+		goto clear_interrupt;
+	}

 	netif_set_real_num_tx_queues(priv->netdev, priv->num_tx_queues);
```

Add teardown in `onic_teardown_netdev` before `onic_clear_interrupt` (line 442):

```c
 	cancel_work_sync(&priv->link_recovery_work);
+	onic_ernic_irq_teardown(priv);
 	onic_clear_interrupt(priv);
```

Note: `onic_ernic_irq_teardown` is a no-op on the secondary and on non-master
PFs (the `ONIC_FLAG_MASTER_PF` check gates setup and teardown symmetrically),
so calling it unconditionally in the shared `onic_teardown_netdev` path is
safe.

### 10.7 Diff: `open-nic-driver/Makefile`

Add `onic_ernic_irq.o` to the `onic-objs` list (exact line depends on the
current Makefile; pattern match `onic_lib.o` and add the new object alongside).

---

## 11. Risks and open questions

1. **MSIX_CAP sufficiency.** If the bitstream advertises fewer than `2 ×
   q_per_cmac + 4` vectors, `pci_alloc_irq_vectors` will return a smaller
   count and the existing fallback in `onic_acquire_msix_vectors:415-420`
   shrinks `num_q_vectors`. The two ERNIC vectors are in the `non_q_vectors`
   floor (min param to `pci_alloc_irq_vectors`), so they are guaranteed. If
   the total MSIX_CAP is less than `non_q_vectors + 1 = 5`, probe fails —
   acceptable because we can't usefully run RDMA without ERNIC IRQs.
   **VERIFY:** `lspci -v -s <bdf> | grep MSI-X` on the target host under the
   current bitstream.

2. **INTEN writability.** Phases 0/0b/1/1b of the F2 bring-up script hit GCSR
   registers cleanly but I can't find an explicit INTEN write in the existing
   driver or probe scripts. If the AXI-Lite path to
   `0x800000 + 0x100180` is actually read-only or tied off in the current
   bitstream, Phase 3 of §9 won't fire. **Flag:** the first live insmod must
   read INTEN back and confirm it reflects what we wrote.
   **VERIFY** during Phase 2 probe.

3. **INTSTS W1C semantics.** Sketch assumes INTSTS is W1C (as F1 audit §5.3
   asserts). If the RTL implements it as W0C or as "write anything to clear",
   writing back the read value still works but wastes a cycle clearing bits
   that weren't set. No correctness impact.

4. **Spurious IRQ handling.** Returning `IRQ_NONE` when `INTSTS == 0` lets the
   kernel's spurious-IRQ detector do its job. If the handler is shared (it's
   not — MSI-X gives us a dedicated vector) this would matter; under MSI-X,
   `IRQ_NONE` just increments a counter. The `spurious_count` atomic lets us
   correlate.

5. **Bottom-half not running during RTNL.** `schedule_work` dispatches on
   `system_wq`, independent of RTNL. The existing `link_recovery_work` path
   takes `rtnl_lock()` in its worker; F5's worker does NOT need RTNL because
   it only touches BAR-mapped MMIO and per-ctx atomics. Good.

6. **Bitstream probe on the secondary / non-master.** On VF / non-master PFs
   the `MASTER_PF` check short-circuits setup and teardown to no-ops. The
   `ernic_irq[]` fields remain zeroed; no accidental `free_irq(0, ...)`
   unless someone removes the `registered` guard.

7. **Concurrent ERNIC0 + ERNIC1 fire.** MSI-X is per-vector, so the two ISRs
   run on potentially different cores with no shared lock. No ordering concern
   — each ctx has its own counters and pending_intsts atomic.

8. **Race between `request_irq` and first fire.** We write `INTEN = 0` before
   `request_irq`, then `INTEN = OWNED` after. A spurious fire in the window
   between `request_irq` and the `INTEN` write would find `INTSTS = 0` (no
   source bits latched because INTEN was 0), return `IRQ_NONE`, bump
   `spurious_count`. Harmless.

9. **Counter overflow.** `atomic_t` is 32-bit signed. At 10 Mpps worst case,
   rollover takes ~215 s. Acceptable for F5 skeleton; B10 will upgrade to
   `atomic64_t` or `percpu` counters when the real IB stats surface emerges.

10. **Teardown ordering vs. the kernel's IRQ workqueue.** `free_irq` calls
    `synchronize_irq` internally, so by the time it returns no ISR is in
    flight. But a work item already in the queue from before can still run,
    which is why we call `cancel_work_sync` AFTER `free_irq`. Reversing that
    order would race.

---

## 12. Changelog

| Date | Who | Change |
|---|---|---|
| 2026-04-23 | F5 design | Initial draft. Vector budget = Option A, 2 MSI-X vectors (one per ERNIC). Pending human review before patches are applied. |
