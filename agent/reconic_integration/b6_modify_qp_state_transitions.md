# B6 — `modify_qp` State Transitions (RESET→INIT→RTR→RTS) on ERNIC v4.2

**Target path:** `/home/alex/mpi-shfs/fpga/open-nic-shell/agent/reconic_integration/b6_modify_qp_state_transitions.md`
**Status:** DESIGN SKETCH — do not apply. Human applies after review.
**Predecessors:** F1 (register map), F5 (MSI-X wired), F7 (lifecycle reference),
B3 (ib_device skeleton), B3.5 (libonic provider), B5 (create_qp / reg_mr).
**Successors:** B7 (post_send/post_recv), B8 (poll_cq/req_notify_cq),
B9 (fatal recovery, ERR → RESET re-entry).

---

## 1. Scope, non-goals, acceptance gate

### In scope

- `modify_qp` dispatch entry point that reads `(cur_state, new_state)` and
  routes to per-transition helpers.
- `modify_qp` RESET→INIT — validates `IB_QP_STATE | IB_QP_PKEY_INDEX |
  IB_QP_PORT | IB_QP_ACCESS_FLAGS` mask. No new register writes (B5 already
  programmed QPCONFi / QPADVCONFi / RQBAi / SQBAi / CQBAi / QDEPTHi / PDi at
  create_qp time); this transition only validates and advances
  `qp->state = ERNIC_QP_INIT`.
- `modify_qp` INIT→RTR — programs `DESTQPCONFi`, `MACDESADDLSBi`,
  `MACDESADDMSBi`, `IPDESADDR1..4i`, `TIMEOUTCONFi`; also updates
  `QPCONFi[7]` (IP version) if we can do so without clobbering the `QPEN=0`
  bit set at create_qp. Stores `path_mtu`, `rq_psn`, `min_rnr_timer`,
  `timeout`, `retry_cnt`, `rnr_retry` in `struct onic_qp` for `query_qp`.
- `modify_qp` RTR→RTS — programs `SQPSNi`, bumps `XRNIC_CONF_QP_EN`, sets
  `QPCONFi[0] QPEN = 1`.
- `query_qp` — minimum viable, returns driver-stored attrs. No hw readback.
- Libonic userspace `modify_qp` + `query_qp` — ibv_cmd passthrough.
- Attr-mask enforcement per ibverbs rules for RC QPs.
- Reject unsupported transitions (RTS→anything except ERR via fatal path)
  with `-EOPNOTSUPP`; `ERR` and re-entry is B9's job.
- Reject `port_num != 1` (ERNIC1 / port 2 deferred to B7.5+).

### Out of scope

- `post_send` / `post_recv` / WQE build (B7).
- `poll_cq` / `req_notify_cq` (B8).
- Fatal-recovery transitions: `* → ERR`, `ERR → UNDER_RECOVERY → RTR` (B9).
- QP drain semantics at destroy — already in B5 (`onic_destroy_qp`).
- Writing ERNIC1's QCSR range (at +0x200000 from ERNIC0). Port 2 support
  lands in B7.5 or whenever we first drive real peer traffic on port 2.
- `modify_qp_ex` (extended attrs; VERIFY §11 — best guess is NOT needed
  because ibv_rc_pingpong uses plain `ibv_modify_qp`).

### Acceptance gate after B6 applies

1. `sudo ibv_rc_pingpong -d onic_0100 -g 0 -r 16` (server side) plus the
   matching client run get PAST `ibv_modify_qp` on both INIT→RTR and
   RTR→RTS transitions. First failure moves forward to `ibv_post_recv` /
   `ibv_post_send` returning `-EOPNOTSUPP` (B7's job).
2. `dmesg` shows three state-transition log lines per QP, each tagged with
   `qp_num` and the programmed values (dest_qpn / peer MAC / peer IPv4 /
   sq_psn).
3. `/phase_f1/XRNIC_CONF_QP_EN` shadow probe reads a non-zero value equal
   to the number of QPs currently in RTS.
4. No kernel WARN/BUG/lockdep splat. `destroy_qp` path still works; a QP
   moved to RTS and then destroyed correctly clears `QPEN` and frees
   `XRNIC_CONF_QP_EN` (see §6.4 below — B6 must DECREMENT the count on
   destroy, which means patching `onic_destroy_qp` too).

---

## 2. ibv_qp_attr → QCSR register mapping

Full mapping of every attr field B6 consumes; PG332 cites are line numbers
in `pg332-ernic-4.2.md`.

| `ibv_qp_attr` field | `attr_mask` bit | Transition | QCSR register | Bit layout | PG332 |
|---|---|---|---|---|---|
| `qp_state` | `IB_QP_STATE` | all | (driver state only) | — | — |
| `pkey_index` | `IB_QP_PKEY_INDEX` | R→I | already in `QPADVCONFi[31:16]` from B5 | — | 3627 |
| `port_num` | `IB_QP_PORT` | R→I | (routes ERNIC pick; B6 forces 1) | — | — |
| `qp_access_flags` | `IB_QP_ACCESS_FLAGS` | R→I | ignored (access is MR-level in ERNIC) | — | — |
| `path_mtu` | `IB_QP_PATH_MTU` | I→R | `QPCONFi[10:8]` — already 4 from B5 | validate | 3622 |
| `dest_qp_num` | `IB_QP_DEST_QPN` | I→R | `DESTQPCONFi[23:0]` @ `0x48` | `[23:0]=QPN` | 3630 |
| `ah_attr.roce.dmac[6]` | `IB_QP_AV` | I→R | `MACDESADDLSBi`@0x50, `MACDESADDMSBi`@0x54 | see §5 | 3629 |
| `ah_attr.grh.dgid` | `IB_QP_AV` | I→R | `IPDESADDR1..4i` @ 0x60/64/68/6C | see §5 | 3631 |
| `ah_attr.port_num` | `IB_QP_AV` | I→R | picks ERNIC (B6: only 1 legal) | — | — |
| `rq_psn` | `IB_QP_RQ_PSN` | I→R | driver-stored only (no RQ PSN reg) | — | n/a |
| `timeout` | `IB_QP_TIMEOUT` | I→R | `TIMEOUTCONFi[5:0]` | retransmit timeout | 3647 |
| `retry_cnt` | `IB_QP_RETRY_CNT` | I→R | `TIMEOUTCONFi[10:8]` | max retry (3 bit) | 3647 |
| `rnr_retry` | `IB_QP_RNR_RETRY` | I→R | `TIMEOUTCONFi[13:11]` | max RNR retry | 3647 |
| `min_rnr_timer` | `IB_QP_MIN_RNR_TIMER` | I→R | `TIMEOUTCONFi[20:16]` | RNR timeout code | 3647 |
| `sq_psn` | `IB_QP_SQ_PSN` | R→S | `SQPSNi[23:0]` @ 0x40 | `[23:0]=PSN` | 3635 |
| `max_rd_atomic` | `IB_QP_MAX_QP_RD_ATOMIC` | R→S | ignored (ERNIC has no atomics) | — | — |
| `max_dest_rd_atomic` | `IB_QP_MAX_DEST_RD_ATOMIC` | I→R | ignored (no atomics) | — | — |

**Additional GCSR write at RTR→RTS (§6.3):**

| Register | Offset | Action |
|---|---|---|
| `XRNIC_CONF_QP_EN` | `GCSR + 0x44` | Read-modify-write: set count to max(current, qp_num+1) |
| `QPCONFi[0]` | QCSR + 0x00 | Read-modify-write: OR in `0x1` (QPEN=1) |

### LSTRQREQi — deliberately NOT programmed

F7 §5.3 Table row and PG332 line 3634 list `LSTRQREQi` @ 0x44 for "initial
remote PSN" at INIT→RTR. ibverbs `rq_psn` is OUR expected-receive PSN, not
the peer's. PG332 calls `LSTRQREQi` the "last RQ request" — it latches the
last-received inbound PSN, which should start at 0 (already the hw reset
value). We leave it alone. **VERIFY** — §11 §11.2.

---

## 3. State-machine enforcement

### 3.1 Valid transition table

Driver only supports the forward path through the standard RC flow:

```
RESET → INIT    (via ib_modify_qp with IB_QPS_INIT)
INIT  → RTR     (via ib_modify_qp with IB_QPS_RTR)
RTR   → RTS     (via ib_modify_qp with IB_QPS_RTS)
```

Everything else in B6 returns `-EOPNOTSUPP`:

- `RESET → RTR` (skipping INIT) — allowed by IB spec for some HCAs; we
  don't support, ERNIC needs stepwise config.
- `RESET → RTS` — ditto.
- `INIT → RTS` — ditto.
- `RTS → RTS` (re-arm) — no-op path; punt.
- `RTS → SQD` / `SQD → RTS` — drain state not modeled.
- `* → RESET` — use `ib_destroy_qp` instead (B5 handles teardown).
- `* → ERR` via user call — blocked (fatal path is B9 internal only).
- `ERR → RESET`, `ERR → RTR` — B9 recovery only.

### 3.2 Required `attr_mask` bits per transition

Per IB spec Table 11-22 (RC QP), ibverbs validates a subset before we see
the call. We assert on top (returning `-EINVAL`) because trusting core's
validation is fragile across kernel versions.

| Transition | Required bits | Nice-to-have bits we accept |
|---|---|---|
| RESET→INIT | `IB_QP_STATE \| IB_QP_PKEY_INDEX \| IB_QP_PORT \| IB_QP_ACCESS_FLAGS` | — |
| INIT→RTR | `IB_QP_STATE \| IB_QP_AV \| IB_QP_PATH_MTU \| IB_QP_DEST_QPN \| IB_QP_RQ_PSN` | `IB_QP_MAX_DEST_RD_ATOMIC \| IB_QP_MIN_RNR_TIMER` |
| RTR→RTS  | `IB_QP_STATE \| IB_QP_SQ_PSN \| IB_QP_TIMEOUT \| IB_QP_RETRY_CNT \| IB_QP_RNR_RETRY \| IB_QP_MAX_QP_RD_ATOMIC` | — |

If a required bit is missing we return `-EINVAL`. If an unknown/unsupported
bit is set (e.g., `IB_QP_ALT_PATH`) we return `-EOPNOTSUPP`.

### 3.3 Concurrency

`onic_modify_qp` takes `qp->state_lock` (already initialized in B5
create_qp) for the read-modify-write of `qp->state`. `onic_destroy_qp`
checks `qp->state` under the same lock. The MSI-X ISR from F5 does NOT
mutate `qp->state` in B6 (fatal-path state mutation is B9). **VERIFY**
§11.5.

---

## 4. `modify_qp` dispatch switch

Main entry point. Replaces `onic_stub_modify_qp` in `onic_ib.c`.

```c
/* onic_ib.c — new (replaces stub at line ~502) */

static int onic_modify_qp_reset_to_init(struct onic_qp *qp,
                                        struct ib_qp_attr *attr, int mask);
static int onic_modify_qp_init_to_rtr (struct onic_qp *qp,
                                        struct ib_qp_attr *attr, int mask);
static int onic_modify_qp_rtr_to_rts  (struct onic_qp *qp,
                                        struct ib_qp_attr *attr, int mask);

static int onic_modify_qp(struct ib_qp *ibqp, struct ib_qp_attr *attr,
                          int attr_mask, struct ib_udata *udata)
{
    struct onic_qp *qp = to_onic_qp(ibqp);
    enum ib_qp_state new_ib_state;
    enum ernic_qp_state cur;
    int rv = 0;
    (void)udata;

    if (!(attr_mask & IB_QP_STATE)) {
        /* B6 policy: every modify_qp must move state.  No attr-only
         * modifies in this track. */
        pr_info_ratelimited("onic_ib: modify_qp w/o IB_QP_STATE, mask=0x%x\n",
                            attr_mask);
        return -EINVAL;
    }
    new_ib_state = attr->qp_state;

    /* Reject anything outside our supported transition set. */
    if (attr_mask & ~(IB_QP_ATTR_STANDARD_BITS)) {
        pr_info_ratelimited("onic_ib: modify_qp extended bits 0x%x unsupported\n",
                            attr_mask);
        return -EOPNOTSUPP;
    }

    spin_lock(&qp->state_lock);
    cur = qp->state;

    if (cur == ERNIC_QP_RESET && new_ib_state == IB_QPS_INIT) {
        rv = onic_modify_qp_reset_to_init(qp, attr, attr_mask);
    } else if (cur == ERNIC_QP_INIT && new_ib_state == IB_QPS_RTR) {
        rv = onic_modify_qp_init_to_rtr(qp, attr, attr_mask);
    } else if (cur == ERNIC_QP_RTR  && new_ib_state == IB_QPS_RTS) {
        rv = onic_modify_qp_rtr_to_rts(qp, attr, attr_mask);
    } else {
        pr_info_ratelimited("onic_ib: modify_qp unsupported %d -> %d\n",
                            (int)cur, (int)new_ib_state);
        rv = -EOPNOTSUPP;
    }

    spin_unlock(&qp->state_lock);
    return rv;
}
```

**Note on create_qp leaving state at INIT:** B5 sets
`qp->state = ERNIC_QP_INIT` at the end of create_qp. But ibverbs calls
`modify_qp(RESET → INIT)` right after create_qp. Two options:

1. Keep B5 behaviour, treat the user's `RESET → INIT` as a no-op that
   validates and returns 0 when `cur == INIT && new == INIT`.
2. Change B5 to leave state at `ERNIC_QP_RESET`; B6's RESET→INIT then runs.

Option 2 is cleaner but is a cross-patch change to B5. Preferred sketch:

```c
/* In onic_create_qp (B5), change the trailing state assignment from
 *     qp->state = ERNIC_QP_INIT;
 * to
 *     qp->state = ERNIC_QP_RESET;
 * so that the libverbs-mandated RESET -> INIT modify_qp call is the
 * thing that moves us into INIT (matching IB spec expectations). */
```

Patch sketch assumes option 2.

---

## 5. RESET→INIT helper

```c
static int onic_modify_qp_reset_to_init(struct onic_qp *qp,
                                        struct ib_qp_attr *attr,
                                        int mask)
{
    const int required = IB_QP_STATE | IB_QP_PKEY_INDEX |
                         IB_QP_PORT  | IB_QP_ACCESS_FLAGS;

    if ((mask & required) != required) {
        pr_info_ratelimited("onic_ib: R->I missing mask bits "
                            "have=0x%x need=0x%x\n", mask, required);
        return -EINVAL;
    }
    if (attr->port_num != 1) {
        pr_info_ratelimited("onic_ib: R->I port_num=%u, only 1 supported\n",
                            attr->port_num);
        return -EOPNOTSUPP;
    }
    if (attr->pkey_index != 0)
        return -EINVAL;                       /* only pkey 0xFFFF at idx 0 */

    /* No register writes — B5 already programmed QPCONFi/QPADVCONFi/
     * queue bases/depth/PDi.  This transition is pure bookkeeping. */
    qp->state = ERNIC_QP_INIT;
    pr_info("onic_ib: qp[%u] RESET -> INIT (port=%u pkey_idx=%u)\n",
            qp->qp_num, attr->port_num, attr->pkey_index);
    return 0;
}
```

---

## 6. INIT→RTR helper

### 6.1 GID-to-IP extraction

ibverbs uses IPv4-mapped-IPv6 (`::ffff:a.b.c.d`). Stock rdma-core places
the IPv4 in `dgid.raw[12..15]`. We detect by checking bytes `[0..9]==0` and
`[10..11]==0xFF`. For an IPv6 GID we pack four 32-bit LE words matching
ERNIC's `IPDESADDR1..4i` layout.

```c
static bool gid_is_ipv4(const union ib_gid *g)
{
    static const u8 pfx[12] = { 0,0,0,0, 0,0,0,0, 0,0,0xFF,0xFF };
    return memcmp(g->raw, pfx, 12) == 0;
}
```

### 6.2 Helper body

```c
static int onic_modify_qp_init_to_rtr(struct onic_qp *qp,
                                      struct ib_qp_attr *attr,
                                      int mask)
{
    struct onic_ib_dev *dev  = to_onic_ib_dev(qp->ibqp.device);
    void __iomem       *mmio = dev->priv->hw.addr;
    const int required = IB_QP_STATE | IB_QP_AV | IB_QP_PATH_MTU |
                         IB_QP_DEST_QPN | IB_QP_RQ_PSN;
    u32 q      = RN_RDMA_QCSR_REG(qp->qp_num, 0x00);
    u32 destqp, mac_lsb, mac_msb;
    u32 ip1 = 0, ip2 = 0, ip3 = 0, ip4 = 0;
    u32 timeoutconf;
    const u8 *dmac;
    const union ib_gid *dgid;
    bool is_v4;
    u32 qpconfi;
    u8  to_val, rt_val, rnr_rt, rnr_to;

    if ((mask & required) != required) {
        pr_info_ratelimited("onic_ib: I->R missing mask bits "
                            "have=0x%x need=0x%x\n", mask, required);
        return -EINVAL;
    }
    if (rdma_ah_get_ah_flags(&attr->ah_attr) & IB_AH_GRH) {
        dgid = &rdma_ah_read_grh(&attr->ah_attr)->dgid;
    } else {
        pr_info_ratelimited("onic_ib: I->R no GRH in ah_attr\n");
        return -EINVAL;
    }
    dmac = rdma_ah_retrieve_dmac(&attr->ah_attr); /* VERIFY: §11.4 */
    if (!dmac) {
        pr_info_ratelimited("onic_ib: I->R dmac missing\n");
        return -EINVAL;
    }
    if (attr->path_mtu != IB_MTU_4096) {
        pr_info_ratelimited("onic_ib: I->R path_mtu=%d unsupported\n",
                            attr->path_mtu);
        return -EOPNOTSUPP;
    }

    /* DESTQPCONFi: peer QPN in [23:0]. */
    destqp = attr->dest_qp_num & 0x00FFFFFFu;

    /* MAC: LSB holds bytes [0..3] LE; MSB holds [4..5] in [15:0]. */
    mac_lsb = ((u32)dmac[0])       |
              ((u32)dmac[1] <<  8) |
              ((u32)dmac[2] << 16) |
              ((u32)dmac[3] << 24);
    mac_msb = ((u32)dmac[4]) | ((u32)dmac[5] << 8);

    /* IP: IPv4 in IPDESADDR1i (BE); IPv6 in 1..4 as 4 LE words. */
    is_v4 = gid_is_ipv4(dgid);
    if (is_v4) {
        /* IPv4 octets live in dgid.raw[12..15].  ERNIC expects big-endian
         * wire order: byte 0 = MSB.  We pack as raw u32 in LE memory: the
         * iowrite32 will put raw[12] at byte 0 of the reg, i.e. ERNIC
         * sees "raw[12].raw[13].raw[14].raw[15]" on the wire. */
        ip1 = ((u32)dgid->raw[12])       |
              ((u32)dgid->raw[13] <<  8) |
              ((u32)dgid->raw[14] << 16) |
              ((u32)dgid->raw[15] << 24);
        /* VERIFY §11.3: byte order of ERNIC IPDESADDR1i — PG332 doesn't
         * spell out endianness; the reconic_reg.h comments and the
         * libreconic/rdma_api.c gateway code treat it as LE-packed. */
        ip2 = ip3 = ip4 = 0;
    } else {
        /* IPv6: four consecutive 32-bit LE words.  gid.raw is 16 bytes
         * network-order; ERNIC expects network-order too, so memcpy-style
         * packing matches. */
        memcpy(&ip1, &dgid->raw[0],  4);
        memcpy(&ip2, &dgid->raw[4],  4);
        memcpy(&ip3, &dgid->raw[8],  4);
        memcpy(&ip4, &dgid->raw[12], 4);
    }

    /* TIMEOUTCONFi: take raw values the user gave us and clip. */
    to_val = (mask & IB_QP_TIMEOUT)       ? (attr->timeout       & 0x1F) : 14;
    rt_val = (mask & IB_QP_RETRY_CNT)     ? (attr->retry_cnt     & 0x07) : 7;
    rnr_rt = (mask & IB_QP_RNR_RETRY)     ? (attr->rnr_retry     & 0x07) : 7;
    rnr_to = (mask & IB_QP_MIN_RNR_TIMER) ? (attr->min_rnr_timer & 0x1F) : 12;
    timeoutconf = ((u32)to_val  <<  0) |
                  ((u32)rt_val  <<  8) |
                  ((u32)rnr_rt  << 11) |
                  ((u32)rnr_to  << 16);

    /* Program Ethernet + L3 + destination QPN + timeouts. */
    iowrite32(destqp,      mmio + q + 0x48);   /* DESTQPCONFi    */
    iowrite32(timeoutconf, mmio + q + 0x4C);   /* TIMEOUTCONFi   */
    iowrite32(mac_lsb,     mmio + q + 0x50);   /* MACDESADDLSBi  */
    iowrite32(mac_msb,     mmio + q + 0x54);   /* MACDESADDMSBi  */
    iowrite32(ip1,         mmio + q + 0x60);   /* IPDESADDR1i    */
    iowrite32(ip2,         mmio + q + 0x64);   /* IPDESADDR2i    */
    iowrite32(ip3,         mmio + q + 0x68);   /* IPDESADDR3i    */
    iowrite32(ip4,         mmio + q + 0x6C);   /* IPDESADDR4i    */

    /* Update QPCONFi[7] IP version WITHOUT touching QPEN (still 0).
     * Read-modify-write. */
    qpconfi = ioread32(mmio + q + 0x00);
    qpconfi &= ~(1u << 7);
    if (is_v4)
        qpconfi |=  (1u << 7);          /* PG332 line 3631: IPv4 when set.
                                         * VERIFY §11.3 — the polarity. */
    iowrite32(qpconfi, mmio + q + 0x00);
    (void)ioread32(mmio + q + 0x00);   /* flush */

    /* Driver-side bookkeeping for query_qp / recovery. */
    qp->dest_qp_num   = attr->dest_qp_num;
    qp->rq_psn        = attr->rq_psn;
    qp->timeout       = to_val;
    qp->retry_cnt     = rt_val;
    qp->rnr_retry     = rnr_rt;
    qp->min_rnr_timer = rnr_to;
    qp->path_mtu_ib   = attr->path_mtu;
    qp->port_num      = 1;
    memcpy(qp->dmac,  dmac,          6);
    memcpy(&qp->dgid, dgid, sizeof(qp->dgid));

    qp->state = ERNIC_QP_RTR;
    pr_info("onic_ib: qp[%u] INIT -> RTR dest_qpn=%u dmac=%pM "
            "dgid=%pI6c rq_psn=%u\n",
            qp->qp_num, qp->dest_qp_num, qp->dmac,
            qp->dgid.raw, qp->rq_psn);
    return 0;
}
```

**Struct onic_qp additions** (edit `onic_ib.h`):

```c
struct onic_qp {
    /* ...existing B5 fields above... */

    /* B6: driver-stored attrs populated during modify_qp for query_qp
     * and for B9 recovery rewrites. */
    u32                  dest_qp_num;
    u32                  rq_psn;
    u32                  sq_psn;
    u8                   timeout;      /* [4:0] after clip */
    u8                   retry_cnt;    /* [2:0] */
    u8                   rnr_retry;    /* [2:0] */
    u8                   min_rnr_timer;/* [4:0] */
    u8                   path_mtu_ib;  /* IB_MTU_* enum value */
    u8                   port_num;
    u8                   dmac[6];
    union ib_gid         dgid;
};
```

---

## 7. RTR→RTS helper

```c
static int onic_modify_qp_rtr_to_rts(struct onic_qp *qp,
                                     struct ib_qp_attr *attr,
                                     int mask)
{
    struct onic_ib_dev *dev  = to_onic_ib_dev(qp->ibqp.device);
    void __iomem       *mmio = dev->priv->hw.addr;
    u32 q       = RN_RDMA_QCSR_REG(qp->qp_num, 0x00);
    u32 qpen_ct, new_ct, qpconfi;
    const int required = IB_QP_STATE | IB_QP_SQ_PSN;

    if ((mask & required) != required) {
        pr_info_ratelimited("onic_ib: R->S missing mask bits "
                            "have=0x%x need=0x%x\n", mask, required);
        return -EINVAL;
    }

    /* 1. SQPSNi at offset 0x40. */
    iowrite32(attr->sq_psn & 0x00FFFFFFu, mmio + q + 0x40);
    qp->sq_psn = attr->sq_psn;

    /* 2. Global enabled-QP count.  XRNIC_CONF_QP_EN is a 12-bit field
     *    (F1 audit §6.2); RMW to at-least cover this qp_num+1.
     *    F7 §5.4 flags the COUNT-vs-MASK semantics as a VERIFY (§11.6).
     *    We use COUNT semantics: max(current, qp_num + 1). */
    qpen_ct = ioread32(mmio + RN_RDMA_GCSR_XRNIC_CONF_QP_EN) & 0xFFFu;
    new_ct  = qp->qp_num + 1;
    if (new_ct > qpen_ct) {
        iowrite32(new_ct, mmio + RN_RDMA_GCSR_XRNIC_CONF_QP_EN);
        (void)ioread32(mmio + RN_RDMA_GCSR_XRNIC_CONF_QP_EN);
    }

    /* 3. QPCONFi[0] QPEN = 1, preserving everything else B5/B6 wrote. */
    qpconfi  = ioread32(mmio + q + 0x00);
    qpconfi |= 0x1u;
    iowrite32(qpconfi, mmio + q + 0x00);
    (void)ioread32(mmio + q + 0x00);

    qp->state = ERNIC_QP_RTS;
    pr_info("onic_ib: qp[%u] RTR -> RTS sq_psn=%u qp_en_ct=%u -> %u\n",
            qp->qp_num, qp->sq_psn, qpen_ct, max(qpen_ct, new_ct));
    return 0;
}
```

### 7.1 Destroy-path coupling (patch to B5's `onic_destroy_qp`)

We DO NOT decrement `XRNIC_CONF_QP_EN` in B6 (treating the count as a
"high-water mark of ever-used QP ids" until B9 tackles recovery). This is
a documented VERIFY (§11.6). Rationale: decrementing would only be
correct if qp_num==count-1 at destroy, which is brittle. F7 §5.7 step 6
says "decrement accordingly" which is vague; we keep it as-is and
reconsider when B7 actually drives traffic.

**Additive patch to destroy_qp:** none required for B6. Just verify that
`onic_destroy_qp` already clears QPEN by zeroing QPCONFi (it does — `iowrite32(0, mmio + q)`).

---

## 8. `query_qp` — driver-stored passthrough

ibv_rc_pingpong does not call it but OFED's `ibv_query_qp` does during
certain error paths. Replace `onic_stub_query_qp`:

```c
static int onic_query_qp(struct ib_qp *ibqp, struct ib_qp_attr *attr,
                         int attr_mask, struct ib_qp_init_attr *init_attr)
{
    struct onic_qp *qp = to_onic_qp(ibqp);
    (void)attr_mask;  /* per ibverbs, drivers may fill more than asked */

    memset(attr, 0, sizeof(*attr));
    spin_lock(&qp->state_lock);
    switch (qp->state) {
    case ERNIC_QP_RESET:           attr->qp_state = IB_QPS_RESET; break;
    case ERNIC_QP_INIT:            attr->qp_state = IB_QPS_INIT;  break;
    case ERNIC_QP_RTR:             attr->qp_state = IB_QPS_RTR;   break;
    case ERNIC_QP_RTS:             attr->qp_state = IB_QPS_RTS;   break;
    case ERNIC_QP_ERR:
    case ERNIC_QP_UNDER_RECOVERY:  attr->qp_state = IB_QPS_ERR;   break;
    case ERNIC_QP_CLOSED: default: attr->qp_state = IB_QPS_RESET; break;
    }
    attr->cur_qp_state   = attr->qp_state;
    attr->path_mtu       = qp->path_mtu_ib ? qp->path_mtu_ib : IB_MTU_4096;
    attr->dest_qp_num    = qp->dest_qp_num;
    attr->rq_psn         = qp->rq_psn;
    attr->sq_psn         = qp->sq_psn;
    attr->timeout        = qp->timeout;
    attr->retry_cnt      = qp->retry_cnt;
    attr->rnr_retry      = qp->rnr_retry;
    attr->min_rnr_timer  = qp->min_rnr_timer;
    attr->port_num       = qp->port_num ? qp->port_num : 1;
    attr->pkey_index     = 0;
    attr->qp_access_flags= 0;
    spin_unlock(&qp->state_lock);

    if (init_attr) {
        memset(init_attr, 0, sizeof(*init_attr));
        init_attr->qp_type           = IB_QPT_RC;
        init_attr->send_cq           = qp->send_cq ? &qp->send_cq->ibcq : NULL;
        init_attr->recv_cq           = qp->recv_cq ? &qp->recv_cq->ibcq : NULL;
        init_attr->cap.max_send_wr   = qp->sq_depth;
        init_attr->cap.max_recv_wr   = qp->rq_depth;
        init_attr->cap.max_send_sge  = 1;
        init_attr->cap.max_recv_sge  = 1;
    }
    return 0;
}
```

Install in the `onic_ib_ops` table, replacing the stub entry.

---

## 9. Libonic userspace `modify_qp` / `query_qp`

Replace the stubs in `libonic.c` (currently at lines 161–166) with
plain passthroughs — the kernel does all the real work.

```c
/* libonic.c */

static int onic_modify_qp(struct ibv_qp *qp, struct ibv_qp_attr *attr,
                          int attr_mask)
{
    struct ibv_modify_qp cmd = {};
    int ret;

    fprintf(stderr,
            "libonic: modify_qp ENTER qp=%p state=%d mask=0x%x\n",
            qp, attr->qp_state, attr_mask);
    ret = ibv_cmd_modify_qp(qp, attr, attr_mask, &cmd, sizeof(cmd));
    if (ret) {
        fprintf(stderr, "libonic: modify_qp FAIL ret=%d errno=%d (%s)\n",
                ret, errno, strerror(errno));
        return ret;
    }
    fprintf(stderr, "libonic: modify_qp OK new state=%d\n", attr->qp_state);
    return 0;
}

static int onic_query_qp(struct ibv_qp *qp, struct ibv_qp_attr *attr,
                         int attr_mask,
                         struct ibv_qp_init_attr *init_attr)
{
    struct ibv_query_qp cmd = {};
    struct ib_uverbs_query_qp_resp resp = {};
    return ibv_cmd_query_qp(qp, attr, attr_mask, init_attr,
                            &cmd, sizeof(cmd), &resp, sizeof(resp));
}
```

### 9.1 modify_qp_ex — believe NOT needed

B5 found OFED's libibverbs dispatches `ibv_reg_mr` through the `reg_mr_ex`
slot with a 5-argument signature. We're on the lookout for the same
quirk with `modify_qp_ex`. OFED's `ibv_modify_qp_ex` signature is
`(qp, attr_ex, attr_mask_ex)` but `ibv_rc_pingpong` calls the legacy
`ibv_modify_qp`. For the acceptance gate we expect the legacy path to
suffice. **VERIFY** §11.1: if libibverbs calls the `.modify_qp_ex` slot
anyway, add a cast-based shim mirroring `onic_reg_mr_ex_compat`.

Best guess from reading `libibverbs`: `modify_qp_ex` is only used when
the caller (app) calls `ibv_modify_qp_ex` directly — pingpong doesn't.

---

## 10. Patch sketch — file-by-file

### 10.1 `onic-driver/onic_ib.h` — +~15 LoC

Add B6 fields to `struct onic_qp` (see §6.2 listing).

### 10.2 `onic-driver/onic_ib.c` — +~220 LoC, -4 LoC

- Delete `onic_stub_modify_qp` (1 line) and `onic_stub_query_qp` (2 lines).
- Edit `onic_create_qp`: change trailing `qp->state = ERNIC_QP_INIT` to
  `ERNIC_QP_RESET` (1 line).
- Add `gid_is_ipv4` helper (4 lines).
- Add `onic_modify_qp_reset_to_init` (~20 lines).
- Add `onic_modify_qp_init_to_rtr` (~100 lines).
- Add `onic_modify_qp_rtr_to_rts` (~35 lines).
- Add `onic_modify_qp` dispatch (~35 lines).
- Add `onic_query_qp` (~35 lines).
- Update `onic_ib_ops` table: `.modify_qp = onic_modify_qp`,
  `.query_qp = onic_query_qp` (2 lines changed).
- Add `#include <rdma/ib_addr.h>` (already present — verified at line 16).

### 10.3 `libonic-provider/libonic.c` — +~25 LoC, -4 LoC

- Replace `onic_modify_qp` stub (lines 161-162) with ibv_cmd passthrough
  (~15 lines).
- Replace `onic_query_qp` stub (lines 164-166) with ibv_cmd passthrough
  (~7 lines).
- Ops table entries remain unchanged (already point at the symbols).

### 10.4 Total

| File | Delta |
|---|---|
| `onic_ib.h` | +15 LoC |
| `onic_ib.c` | +220 / -4 LoC |
| `libonic.c` | +25 / -4 LoC |
| **Total** | **+260 / -8 LoC** |

---

## 11. Risks and VERIFY items

### 11.1 `modify_qp_ex` dispatch — LIKELY NOT NEEDED

As in B5's `reg_mr_ex` workaround. Guess: pingpong never hits it; other
OFED apps may. Mitigation is a 3-line shim identical in pattern to
`onic_reg_mr_ex_compat`, added only if we observe a dispatch miss in
`strace -e openat,ioctl` during pingpong. **Sign-off risk: LOW.**

### 11.2 `LSTRQREQi` interpretation

F7 §5.3 table writes `LSTRQREQi` at INIT→RTR with "initial remote PSN".
PG332 line 3634 is "Configure last receive queue PSN by writing to
LSTRQREQi". This is ambiguous — is it `rq_psn` (what WE will accept as
the next inbound PSN), or is it the peer's starting send PSN (which
equals our `rq_psn`)? They're numerically the same value during normal
setup, so we write `attr->rq_psn` defensively:

```c
iowrite32(attr->rq_psn & 0x00FFFFFFu, mmio + q + 0x44);  /* LSTRQREQi */
```

Insert this in §6.2's helper just after the TIMEOUTCONF write. **Action:
add the write. Flag for FAE verification.** **Sign-off risk: MEDIUM.**

### 11.3 IPv4 byte-order into `IPDESADDR1i`

PG332 doesn't spell out endianness for these regs. libreconic gateway
code (`rdma_api.c`) and the reconic_reg.h comments suggest the ERNIC
treats these as network-order when packed as shown. VERIFY with a
hardware probe after B6 applies: write a known IPv4 like `10.0.0.1`
(`0x0a000001`) and capture the outgoing header's IPDA to confirm byte
order. **Sign-off risk: MEDIUM** — getting it wrong means packets go to
the wrong address; fix is one-line byte-swap.

Also VERIFY the polarity of `QPCONFi[7]` IP version bit: PG332 3631 says
"Configure the IP address version in the QPCONFi" but we chose
"1 = IPv4" without an unambiguous reference. **Sign-off risk: LOW** —
single-bit test, easy to flip.

### 11.4 `rdma_ah_retrieve_dmac()` — API name

In upstream 6.8 `include/rdma/ib_verbs.h` the helper is
`rdma_ah_retrieve_dmac` returning `const u8 *`. **VERIFY** at compile
time that this symbol exists in OFED's kmod source; if not, use
`attr->ah_attr.roce.dmac` directly (which the B6 context already cites).

### 11.5 Locking between `modify_qp` and `destroy_qp`

Both touch `qp->state`. `destroy_qp` (B5) currently doesn't take
`qp->state_lock`. If B7 adds a fatal-path that sets `ERR` from ISR,
we'll need proper locking everywhere. For B6 the race is benign because
pingpong serializes its calls; FUTURE B9 will tighten. **Sign-off risk:
LOW for now.**

### 11.6 `XRNIC_CONF_QP_EN` count-vs-mask semantics — BIGGEST RISK

F1 audit §6.2 explicitly flags this as an FAE question. F7 §5.4 and §5.7
punt on exact decrement rules. Our B6 sketch uses **COUNT** semantics
(`max(cur, qp_num+1)`). If hardware actually wants a **MASK**
(`set bit N`), we'll have one QP work and then subsequent ones see
stale/wrong mask bits → traffic silently drops. Mitigation:

- After B6 applies, write a phase_f1 probe that sets up a single QP to
  RTS, reads XRNIC_CONF_QP_EN, tears down, creates a new QP with a
  different `qp_num`, and verifies the register behaves as count.
- If mask semantics, change the write to
  `iowrite32(qpen_ct | (1u << qp->qp_num), ...)` and add a
  corresponding clear on destroy.

**Sign-off risk: HIGH.** This is the biggest unknown in B6.

### 11.7 `QPCONFi` RMW hazards

Both INIT→RTR (IP version bit) and RTR→RTS (QPEN bit) do
read-modify-write on QPCONFi. If the hardware latches ANY write to
QPCONFi as a "reconfigure" event (e.g., quiescing the pipeline),
touching it after B5 already programmed it may be unsafe. PG332 Chapter
7 sequence at line 3653 writes "PMTU by writing to QPCONFi register" as
part of RESET→RTS, suggesting writes at this stage are expected.
**Sign-off risk: LOW-MEDIUM.**

### 11.8 F5 MSI-X ISR interaction

F5 left the ISR log-only. During RTR→RTS the first write to QPEN could
in principle trigger an interrupt if ERNIC signals "QP now live". In
practice no evidence PG332 emits such an interrupt. If the ISR DOES
fire during our transition window, we'll see harmless log spam —
actionable handling is B9's problem. **Sign-off risk: LOW.**

### 11.9 ERNIC1 / port 2 deferral

B6 rejects `attr->port_num != 1`. This means a pingpong invocation with
`-p 2` (or OFED resource-lookup on port 2) will fail at modify_qp, which
is the right behavior for now but would bite a future rping multi-path
test. Document in release notes. **Sign-off risk: LOW.**

---

## 12. Test plan

### 12.1 Unit-level (no FPGA)

- Build `onic.ko` out-of-tree; verify `modinfo` loads cleanly with the
  new `onic_ib.o` symbols present.
- Build libonic.so; `ldd` confirms no new deps.

### 12.2 On-FPGA smoke

1. `sudo insmod onic.ko`, `sudo modprobe ib_core rdma_cm`.
2. Bring up `eth0`/`eth1` with `10.0.0.1/24` and `10.0.0.2/24` (or loop
   back via MGT internal loopback if available).
3. `ibv_devices` shows `onic_0100`.
4. Server: `sudo ibv_rc_pingpong -d onic_0100 -g 0 -r 16`.
5. Client (other machine or loopback): `sudo ibv_rc_pingpong -d onic_0100 -g 0 -r 16 <server_ip>`.
6. Observe:
   - `libonic: modify_qp ENTER ... state=1` (INIT) then `state=2` (RTR)
     then `state=3` (RTS) in both ends' stderr.
   - `dmesg` shows 3 state-transition lines per QP, tagged with correct
     dest_qpn / peer MAC / peer IPv4 / sq_psn.
   - Pingpong progresses to `post_recv` / `post_send` and fails there
     with `-EOPNOTSUPP`. That is the expected B6 acceptance point.

### 12.3 Register probes

Using the existing phase_f1 probe utility:

- `phase_f1 probe 0x10_0044` before any pingpong → 0.
- `phase_f1 probe 0x10_0044` after pingpong INIT→RTR→RTS reaches post_* →
  a value >= number of QPs currently in RTS (typically 1 or 2 per end).
- `phase_f1 probe QCSR[qp_num] + 0x48` → matches peer's `qp_num`.
- `phase_f1 probe QCSR[qp_num] + 0x40` → matches the client's starting
  `sq_psn` as negotiated in `ibv_rc_pingpong`.
- `phase_f1 probe QCSR[qp_num] + 0x00` bit 0 == 1.

### 12.4 Negative tests

- `ibv_modify_qp` with `attr_mask` missing `IB_QP_DEST_QPN` at INIT→RTR
  returns `-EINVAL`; dmesg logs the reason.
- `ibv_modify_qp` with `port_num = 2` returns `-EOPNOTSUPP`.
- `ibv_modify_qp` RESET→RTS (skipping) returns `-EOPNOTSUPP`.

### 12.5 Cleanup

- `ctrl+C` the pingpong → userspace closes fd → kernel destroy_qp
  fires → QPCONFi zeroed, slot freed. `XRNIC_CONF_QP_EN` intentionally
  not decremented in B6; `phase_f1` still shows the pre-destroy value
  (DOCUMENTED GAP, not a bug).

---

## 13. Out-of-band notes for the human reviewer

- `IB_QP_ATTR_STANDARD_BITS` is defined in 6.8 headers (`GENMASK(20, 0)`);
  confirm presence in the OFED headers actually linked into the module
  build. If absent, substitute `0x001FFFFF` literal.
- Some OFED releases rename `rdma_ah_read_grh` → `rdma_ah_retrieve_grh`.
  The patch sketch uses `rdma_ah_read_grh` matching 6.8 upstream.
- `union ib_gid` in upstream 6.8 is a 16-byte `raw[16]` + `global.subnet_prefix +
  global.interface_id` union; `%pI6c` printf works.
- All new register writes use `iowrite32` + a readback flush (`ioread32`)
  on the same BAR offset, matching the B5 convention.

---

**END — ready for human review.**
