# B3 — ib_device Skeleton for onic.ko (dual-port RoCEv2)

**Status:** design + patch sketch only. Nothing applied to source.
**Last updated:** 2026-04-23.
**Prereqs landed:** F1 register audit, F5 MSI-X dispatch skeleton (ERNIC0/1 ISRs),
F7 QP/CQ/PD lifecycle header, dual-netdev probe (`onic_setup_primary`,
`onic_setup_secondary`).
**Depends on:** kernel `ib_core` module (`CONFIG_INFINIBAND=m` confirmed in
6.8.0-107-generic). `modprobe ib_core` must be loaded or the symbol dependency
will keep `onic.ko` from inserting.
**Unblocks:** B5 PD/MR slab (replaces the B3 bitmap), B6 CQ allocator, B7 QP
allocator + state machine wiring, B8 completion delivery.

---

## 1. Scope and non-goals

**In scope for B3:**

1. Register one `struct ib_device` per master PF (not per ERNIC) with
   `phys_port_cnt = 2`. Port 1 backs ERNIC0 / CMAC0 / primary netdev, port 2
   backs ERNIC1 / CMAC1 / secondary netdev.
2. Implement the minimum verb set to satisfy `ibv_devinfo -v` and
   `ibv_alloc_pd`: `query_device`, `query_port`, `get_port_immutable`,
   `get_link_layer`, `get_dev_fw_str`, `alloc_ucontext` / `dealloc_ucontext`,
   `alloc_pd` / `dealloc_pd`.
3. Advertise the restricted capability set from the F1/F7 audit — no atomics,
   no SRQ, no multicast, no XRC, no MEM_WINDOW, `max_sge = 1`,
   `max_qp = max_mr = max_cq = 255`.
4. Hook `ib_device_set_netdev(ibdev, netdev, port)` so the kernel's RoCE GID
   cache auto-populates from each netdev's link-local IPv6 + MAC.
5. Stub every other op with `-EOPNOTSUPP`; return cleanly, never crash.
6. Clean teardown in `onic_teardown_netdev` (master PF only) before
   `onic_ernic_irq_teardown`.

**Explicitly out of scope (deferred):**

- Any real QP / CQ / MR / AH allocation — B5/B6/B7/B8 own those. B3's
  `create_qp` / `create_cq` / `reg_user_mr` etc. return `-EOPNOTSUPP`.
- uverbs mmap regions for doorbells / CQ buffers — no user-visible HW mapping
  yet (B8).
- ERNIC-side table programming (QP_CONF, PD_CONF, etc.). F7 §2–5 describes
  what these will do; B3 touches none of it.
- Management QP (QP1) / process_mad — not needed for RoCEv2.
- GID add/del callbacks (`add_gid` / `del_gid`). RoCE auto-GID works without
  them when `ip_gids = 1` in `ib_port_attr`; verify in Phase 3 of the test
  plan.

---

## 2. Integration points summary

New files:

```
onic_ib.h   (~80 LoC)  — public setup/teardown surface + onic_ib_dev struct
onic_ib.c   (~500 LoC) — ib_device_ops table, query_*, PD bitmap, stubs
```

Touched files (diff only):

| File | What changes |
|---|---|
| `onic.h` | `#include "onic_ib.h"`, add `struct onic_ib_dev *ib_dev` + `struct mutex ib_lock` to `onic_private` |
| `onic_main.c::onic_setup_primary` | call `onic_ib_register(priv)` after `register_netdev`, before `netif_carrier_off` path |
| `onic_main.c::onic_probe` | after secondary is set up, call `onic_ib_set_port2_netdev(primary, secondary)` so port 2 binds to the secondary netdev |
| `onic_main.c::onic_teardown_netdev` | call `onic_ib_unregister(priv)` BEFORE `onic_ernic_irq_teardown`, master-only |
| `Makefile` | nothing — wildcard already picks up `onic_ib.o` |

Call flow:

```
onic_probe(pdev)
  └─ onic_setup_primary(pdev, &primary)
       ├─ alloc_netdev / init_hw / init_interrupt
       ├─ onic_ernic_irq_setup(primary)          # F5
       ├─ register_netdev(primary->netdev)
       └─ onic_ib_register(primary)              # B3 — NEW
             └─ ib_alloc_device / ib_set_device_ops
             └─ ib_register_device("onic_<bdf>")
             └─ ib_device_set_netdev(ibdev, primary->netdev, port=1)
  └─ onic_setup_secondary(primary, &secondary)
       └─ register_netdev(secondary->netdev)
  └─ onic_ib_set_port2_netdev(primary, secondary) # B3 — NEW, link port 2

onic_remove(pdev)
  └─ onic_teardown_netdev(secondary)
  └─ onic_teardown_netdev(primary)
       ├─ disable CMAC RX
       ├─ cancel link_recovery_work
       ├─ onic_ib_unregister(primary)            # B3 — NEW, master-only
       ├─ onic_ernic_irq_teardown(primary)       # F5
       └─ onic_clear_interrupt / _hardware / _capacity
```

**Ordering rationale:** `onic_ib_unregister` runs before `onic_ernic_irq_teardown`
so that the bottom-half workers (once B8 lands) can still reach the IB
ucontext/QP state while ISRs may fire; by the time ERNIC IRQs go silent, no
verb-side code is left running. For B3 specifically this ordering is overkill
— no ISR calls anything IB-related yet — but we fix the teardown contract now
so B8 doesn't have to move things around.

---

## 3. `ib_device_ops` initialization

Kernel 6.8 uses `struct ib_device_ops` (see `include/rdma/ib_verbs.h:2336`).
We set it via `ib_set_device_ops(ibdev, &onic_ib_ops)` after
`ib_alloc_device`. The `INIT_RDMA_OBJ_SIZE(ib_pd, onic_pd, ibpd)` macro
(line 2295) tells the IB core to kzalloc our driver struct *inline* with
`ib_pd`; we use that for ucontext and PD in B3.

Leaving an op NULL is NOT enough for all callbacks — some are
"mandatory-if-you-opt-into-the-feature" and the core BUGs if called with a
NULL pointer. Safer to point them at explicit `-EOPNOTSUPP` stubs.

Full table is in the §10.2 `onic_ib.c` sketch (`static const struct
ib_device_ops onic_ib_ops`).

---

## 4. `query_device` / `query_port` / `get_port_immutable`

Notes (full code in §10.2):

- **query_device**: fills `ib_device_attr` per the restricted capability set
  — `max_qp=255`, `max_qp_wr=1024`, `max_sge=1`, `max_cq=255`, `max_cqe=1024`,
  `max_mr=255`, `max_pd=256`, `atomic_cap=IB_ATOMIC_NONE`, `max_mcast_grp=0`,
  `max_srq=0`, `max_ah=0`, `device_cap_flags=0`. `sys_image_guid` = EUI-64
  derived from primary netdev MAC. Rejects any non-empty `ib_udata` (no
  provider-specific fields in B3).
- **query_port**: maps `netif_running(ndev) && netif_carrier_ok(ndev)` →
  `IB_PORT_ACTIVE` + `phys_state=5` (LINK_UP); else `IB_PORT_DOWN` +
  `phys_state=3` (DISABLED). `max_mtu=active_mtu=IB_MTU_4096`,
  `gid_tbl_len=4`, `ip_gids=1`, `port_cap_flags=0` (no CM_SUP),
  `pkey_tbl_len=1`, `active_width=IB_WIDTH_4X`, `active_speed=IB_SPEED_EDR`.
  Port number is 1 or 2; anything else returns `-EINVAL`.
- **get_port_immutable**: calls `ib_query_port` internally, then stamps
  `core_cap_flags = RDMA_CORE_PORT_IBA_ROCE_UDP_ENCAP` — this is the line
  that turns on RoCEv2 semantics in the core (GID cache on, SMI/MAD off, SA
  bypass). `max_mad_size=0`.
- **get_link_layer**: always `IB_LINK_LAYER_ETHERNET`.
- **get_netdev**: `rcu_dereference` the per-port netdev, `dev_hold` before
  returning (API contract).
- **query_pkey**: returns `0xFFFF` for index 0, `-EINVAL` otherwise.
- **query_gid**: returns `-EINVAL` — RoCE core GID cache owns these, this
  callback shouldn't fire.
- **get_dev_fw_str**: `"ERNIC v4.2 (F5+B3 2026-04-23)"`.

---

## 5. PD allocator (throwaway bitmap)

B3 uses a plain `DECLARE_BITMAP(pd_bitmap, 256)` + `spinlock_t` in
`onic_ib_dev`. `alloc_pd` does `find_first_zero_bit` → `set_bit`,
`dealloc_pd` does `clear_bit`. `pd->pdn` is the allocated index; it's
opaque to B3 but will become the ERNIC `PD_NUM` register field in B5 (F7 §2
"PD state machine").

Replacement target: B5 swaps the bitmap for a PD slab backed by an ERNIC
`PD_CONF` write per entry (F7 §2). Struct definitions in `onic_ib.h` (§10.1),
allocator in `onic_ib.c` (§10.2).

---

## 6. ucontext implementation

Empty structs in B3 — `alloc_ucontext` returns 0, `dealloc_ucontext` is a
no-op. The core kzallocs `struct onic_ucontext` for us because of
`INIT_RDMA_OBJ_SIZE(ib_ucontext, onic_ucontext, ibucontext)` in the ops
table. B8 will add per-ucontext mmap xarrays for doorbells and CQ buffers.

---

## 7. Ops that stub with `-EOPNOTSUPP`

Every op below has a one-liner that logs once (ratelimited) and returns
`-EOPNOTSUPP`. The log line helps Phase 4 of testing confirm that
`ibv_rc_pingpong` is taking the path we think it is.

| Op | File:line (future impl) | Log token |
|---|---|---|
| create_cq / destroy_cq | B6 `onic_ib_cq.c` | `b3_stub: create_cq` |
| create_qp / destroy_qp | B7 `onic_ib_qp.c` | `b3_stub: create_qp` |
| modify_qp / query_qp | B7 (state machine F7 §5) | `b3_stub: modify_qp` |
| post_send / post_recv | B7 doorbell path | `b3_stub: post_send` |
| poll_cq | B8 completion delivery | `b3_stub: poll_cq` |
| req_notify_cq | B8 | `b3_stub: req_notify_cq` |
| create_ah / destroy_ah | B7 (no AH in restricted set) | `b3_stub: create_ah` |
| reg_user_mr / dereg_mr | B5 MR slab | `b3_stub: reg_user_mr` |
| alloc_mr / map_mr_sg | B5 | `b3_stub: alloc_mr` |

Pattern (all stubs expand from one macro — see `STUB_BODY` in §10.2):

```c
#define STUB_BODY(name) \
    pr_info_ratelimited("onic_ib: b3_stub: " name " -> -EOPNOTSUPP\n"); \
    return -EOPNOTSUPP
```

MR-returning stubs (`reg_user_mr`, `alloc_mr`) return `ERR_PTR(-EOPNOTSUPP)`
instead — signature constraint.

---

## 8. Setup / teardown flow

### 8.1 Registration

Called from `onic_setup_primary` after `register_netdev` succeeds and before
`netif_carrier_off`. Deliberately AFTER `onic_ernic_irq_setup` so that by the
time the IB core sees the device, the ERNIC ISRs are already armed.
Master-PF only (matches F5 gating pattern).

Sequence inside `onic_ib_register` (full code in §10.2):

1. Early-return 0 on non-master-PF.
2. `ib_alloc_device(onic_ib_dev, ibdev)` — core kzallocs the outer struct.
3. Initialise `pd_lock`, zero `pd_bitmap`, compute `node_guid` (EUI-64
   stretch: `mac[0..2] | 0x02, 0xFF, 0xFE, mac[3..5]`).
4. Set `ibdev.node_type = RDMA_NODE_IB_CA`, `phys_port_cnt = 2`,
   `num_comp_vectors = 1`, `dev.parent = &pdev->dev`.
5. `ib_set_device_ops`, `rcu_assign_pointer(dev->port[0].netdev, priv->netdev)`.
6. `ib_register_device("onic_<bus><devfn>")` — unique across cards.
7. `ib_device_set_netdev(ibdev, priv->netdev, port=1)` AFTER register (API
   contract). Unwind via `ib_unregister_device` + `ib_dealloc_device` on
   failure.
8. Stash `priv->ib_dev = dev`.

`onic_ib_set_port2_netdev(primary, secondary)` is a one-liner: RCU-assign
`port[1].netdev`, call `ib_device_set_netdev(..., port=2)`. Invoked from
`onic_probe` once `onic_setup_secondary` succeeds (§2 call flow).

`onic_ib_unregister(priv)` null-checks `priv->ib_dev`, then
`ib_unregister_device` + `ib_dealloc_device`, clears pointer.

### 8.2 Teardown ordering contract

In `onic_teardown_netdev`, master PF only, we call `onic_ib_unregister` BEFORE
`onic_ernic_irq_teardown`. Secondary teardown is a no-op for IB (it never
owned an `ib_dev`). If `priv->ib_dev` is NULL we fall through cleanly — this
is the case on the secondary's teardown path and on non-master PFs.

### 8.3 Kbuild / module dep

`onic.ko` will gain a `depends` line on `ib_core` automatically once it
references `ib_register_device` et al. Verify:

```sh
grep CONFIG_INFINIBAND /boot/config-$(uname -r)      # =m, confirmed on target
modprobe ib_core
lsmod | grep ib_core                                  # must show a refcount
modinfo ./onic.ko | grep depends                      # expect "ib_core"
```

If `ib_core` is not loaded when `insmod onic.ko` runs, the load fails with
`Unknown symbol ib_register_device`. The target box (6.8.0-107-generic) has
`CONFIG_INFINIBAND=m`, so `modprobe ib_core` before insmod. Consider adding
this to the load script / systemd unit later (not a B3 scope item).

---

## 9. Test plan

### Phase 1 — compile

```sh
cd /home/alex/mpi-shfs/fpga/open-nic-driver
make KDIR=/lib/modules/$(uname -r)/build 2>&1 | tee /tmp/b3_build.log
```

Expected: no warnings (`-Werror -Wall` per Makefile). Undefined-references
triage: if `ib_register_device` / `ib_alloc_device` are missing from
`Module.symvers`, check that `/lib/modules/$(uname -r)/kernel/drivers/infiniband/core/ib_core.ko`
exists and its symbols are in `Module.symvers`.

### Phase 2 — insmod

```sh
modprobe ib_core
modprobe ib_uverbs
insmod ./onic.ko debug_level=2
dmesg | tail -40         # look for: "ib_device 'onic_XXXX' registered (2 ports, RoCEv2)"
ls /dev/infiniband/      # expect uverbs0
ls /sys/class/infiniband # expect onic_<bdf>
```

### Phase 3 — ibv_devinfo

```sh
sudo apt install libibverbs-dev ibverbs-utils
ibv_devices                 # expect 1 entry with our name + node_guid
ibv_devinfo -v              # all 2 ports, state=ACTIVE iff CMAC is up
ibv_devinfo -v | grep -E "max_qp|max_cq|max_mr|max_pd|max_sge|phys_port_cnt"
ibv_devinfo -v | grep -E "active_mtu|phys_state|port_cap_flags|PortGID"
```

Checks the cap ceiling matches §4.1 and that the GID cache populated at least
one entry per port from the netdev's link-local IPv6 + MAC. If GIDs are
empty, check `ip -6 addr show dev onic*` — the netdev needs to be up for the
kernel to assign a link-local IPv6.

### Phase 4 — ibv_rc_pingpong (negative path)

```sh
# One shell, server side:
ibv_rc_pingpong -d onic_<bdf> -g 0
# Other shell, client side (same host is fine):
ibv_rc_pingpong -d onic_<bdf> -g 0 localhost
```

Expected failure point: `ibv_create_qp` returns NULL with errno=EOPNOTSUPP.
dmesg should show `b3_stub: create_qp`. The test MUST NOT crash, hang, or
leak.

### Phase 5 — rmmod

```sh
rmmod onic
dmesg | tail -20      # no "leaked", no oops, no "still holding"
ls /dev/infiniband/   # gone
lsmod | grep onic     # gone
```

---

## 10. Patch sketch

### 10.1 `onic_ib.h` (new file)

```c
/*
 * Copyright (c) 2026 Tenstorrent Inc.
 *
 * onic_ib.h — B3 skeleton for the ib_device carried by master PF.
 *
 * SPDX-License-Identifier: GPL-2.0
 */
#ifndef __ONIC_IB_H__
#define __ONIC_IB_H__

#include <linux/bitops.h>
#include <linux/spinlock.h>
#include <rdma/ib_verbs.h>

struct onic_private;

#define ONIC_IB_MAX_PD 256

struct onic_ib_dev {
    struct ib_device      ibdev;    /* MUST be first — to_onic_ib_dev casts */
    struct onic_private  *priv;
    __be64                node_guid;
    struct {
        struct net_device __rcu *netdev;
    } port[2];
    DECLARE_BITMAP(pd_bitmap, ONIC_IB_MAX_PD);
    spinlock_t            pd_lock;
};

struct onic_pd {
    struct ib_pd ibpd;
    u32          pdn;
};

struct onic_ucontext {
    struct ib_ucontext ibucontext;
};

static inline struct onic_ib_dev *to_onic_ib_dev(struct ib_device *ibdev)
{
    return container_of(ibdev, struct onic_ib_dev, ibdev);
}

static inline struct onic_pd *to_onic_pd(struct ib_pd *pd)
{
    return container_of(pd, struct onic_pd, ibpd);
}

int  onic_ib_register(struct onic_private *priv);
void onic_ib_unregister(struct onic_private *priv);
int  onic_ib_set_port2_netdev(struct onic_private *primary,
                              struct onic_private *secondary);

#endif /* __ONIC_IB_H__ */
```

### 10.2 `onic_ib.c` (new file, abbreviated — combines §3–7)

```c
/*
 * Copyright (c) 2026 Tenstorrent Inc.
 *
 * onic_ib.c — B3 ib_device skeleton: query_device/_port/_immutable,
 * empty ucontext, bitmap PD allocator, -EOPNOTSUPP stubs for the rest.
 *
 * SPDX-License-Identifier: GPL-2.0
 */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/netdevice.h>
#include <linux/inetdevice.h>
#include <rdma/ib_verbs.h>
#include <rdma/ib_addr.h>
#include <rdma/ib_cache.h>

#include "onic.h"
#include "onic_ib.h"

/* ----- query_* (§4) ----- */

static int onic_query_device(struct ib_device *ibdev,
                             struct ib_device_attr *attr,
                             struct ib_udata *udata)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(ibdev);

    if (udata->inlen || udata->outlen)
        return -EINVAL;

    memset(attr, 0, sizeof(*attr));
    attr->fw_ver              = 0x0402;
    attr->hw_ver              = 0x0402;
    attr->vendor_id           = 0x10ee;
    attr->vendor_part_id      = dev->priv->pdev->device;
    attr->sys_image_guid      = dev->node_guid;
    attr->max_qp              = 255;
    attr->max_qp_wr           = 1024;
    attr->device_cap_flags    = 0;
    attr->kernel_cap_flags    = 0;
    attr->max_send_sge        = 1;
    attr->max_recv_sge        = 1;
    attr->max_sge_rd          = 1;
    attr->max_cq              = 255;
    attr->max_cqe             = 1024;
    attr->max_mr              = 255;
    attr->max_pd              = ONIC_IB_MAX_PD;
    attr->atomic_cap          = IB_ATOMIC_NONE;
    attr->masked_atomic_cap   = IB_ATOMIC_NONE;
    attr->max_mcast_grp       = 0;
    attr->max_ah              = 0;
    attr->max_srq             = 0;
    attr->max_pkeys           = 1;
    attr->local_ca_ack_delay  = 14;
    attr->max_mr_size         = ~0ULL;
    attr->page_size_cap       = PAGE_SIZE;
    return 0;
}

static int onic_query_port(struct ib_device *ibdev, u32 port,
                           struct ib_port_attr *attr)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(ibdev);
    struct net_device  *ndev;

    if (port < 1 || port > 2)
        return -EINVAL;

    rcu_read_lock();
    ndev = rcu_dereference(dev->port[port - 1].netdev);
    rcu_read_unlock();

    memset(attr, 0, sizeof(*attr));

    if (ndev && netif_running(ndev) && netif_carrier_ok(ndev)) {
        attr->state      = IB_PORT_ACTIVE;
        attr->phys_state = 5; /* LINK_UP */
    } else {
        attr->state      = IB_PORT_DOWN;
        attr->phys_state = 3; /* DISABLED */
    }
    attr->max_mtu        = IB_MTU_4096;
    attr->active_mtu     = IB_MTU_4096;
    attr->phys_mtu       = 4096;
    attr->gid_tbl_len    = 4;
    attr->ip_gids        = 1;
    attr->port_cap_flags = 0;
    attr->max_msg_sz     = 1u << 30;
    attr->pkey_tbl_len   = 1;
    attr->active_width   = IB_WIDTH_4X;
    attr->active_speed   = IB_SPEED_EDR;
    return 0;
}

static int onic_get_port_immutable(struct ib_device *ibdev, u32 port,
                                   struct ib_port_immutable *imm)
{
    struct ib_port_attr a;
    int rv = ib_query_port(ibdev, port, &a);
    if (rv) return rv;
    imm->pkey_tbl_len   = a.pkey_tbl_len;
    imm->gid_tbl_len    = a.gid_tbl_len;
    imm->core_cap_flags = RDMA_CORE_PORT_IBA_ROCE_UDP_ENCAP;
    imm->max_mad_size   = 0;
    return 0;
}

static enum rdma_link_layer
onic_get_link_layer(struct ib_device *ibdev, u32 port)
{
    return IB_LINK_LAYER_ETHERNET;
}

static int onic_query_pkey(struct ib_device *ibdev, u32 port, u16 idx, u16 *pkey)
{
    if (idx > 0) return -EINVAL;
    *pkey = 0xFFFF;
    return 0;
}

static int onic_query_gid(struct ib_device *ibdev, u32 port, int idx,
                          union ib_gid *gid)
{
    return -EINVAL; /* RoCE: GID cache owns these */
}

static struct net_device *onic_get_netdev(struct ib_device *ibdev, u32 port)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(ibdev);
    struct net_device  *ndev = NULL;

    if (port < 1 || port > 2)
        return NULL;
    rcu_read_lock();
    ndev = rcu_dereference(dev->port[port - 1].netdev);
    if (ndev)
        dev_hold(ndev);
    rcu_read_unlock();
    return ndev;
}

static void onic_get_dev_fw_str(struct ib_device *ibdev, char *str)
{
    snprintf(str, IB_FW_VERSION_NAME_MAX, "ERNIC v4.2 (F5+B3 2026-04-23)");
}

/* ----- ucontext (§6) ----- */

static int onic_alloc_ucontext(struct ib_ucontext *uc, struct ib_udata *udata)
{
    return 0;
}
static void onic_dealloc_ucontext(struct ib_ucontext *uc) { }

/* ----- PD allocator (§5) ----- */

static int onic_alloc_pd(struct ib_pd *ibpd, struct ib_udata *udata)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(ibpd->device);
    struct onic_pd     *pd  = to_onic_pd(ibpd);
    int                 bit;

    spin_lock(&dev->pd_lock);
    bit = find_first_zero_bit(dev->pd_bitmap, ONIC_IB_MAX_PD);
    if (bit >= ONIC_IB_MAX_PD) {
        spin_unlock(&dev->pd_lock);
        return -ENOMEM;
    }
    set_bit(bit, dev->pd_bitmap);
    spin_unlock(&dev->pd_lock);

    pd->pdn = bit;
    return 0;
}

static int onic_dealloc_pd(struct ib_pd *ibpd, struct ib_udata *udata)
{
    struct onic_ib_dev *dev = to_onic_ib_dev(ibpd->device);
    struct onic_pd     *pd  = to_onic_pd(ibpd);

    spin_lock(&dev->pd_lock);
    clear_bit(pd->pdn, dev->pd_bitmap);
    spin_unlock(&dev->pd_lock);
    return 0;
}

/* ----- stubs (§7) ----- */

#define STUB_BODY(name) \
    pr_info_ratelimited("onic_ib: b3_stub: " name " -> -EOPNOTSUPP\n"); \
    return -EOPNOTSUPP

static int onic_stub_create_cq(struct ib_cq *cq, const struct ib_cq_init_attr *a,
                               struct ib_udata *u)               { STUB_BODY("create_cq"); }
static int onic_stub_destroy_cq(struct ib_cq *cq, struct ib_udata *u)
                                                                  { STUB_BODY("destroy_cq"); }
static int onic_stub_create_qp(struct ib_qp *qp, struct ib_qp_init_attr *a,
                               struct ib_udata *u)               { STUB_BODY("create_qp"); }
static int onic_stub_modify_qp(struct ib_qp *qp, struct ib_qp_attr *a, int mask,
                               struct ib_udata *u)               { STUB_BODY("modify_qp"); }
static int onic_stub_query_qp(struct ib_qp *qp, struct ib_qp_attr *a, int mask,
                              struct ib_qp_init_attr *ia)        { STUB_BODY("query_qp"); }
static int onic_stub_destroy_qp(struct ib_qp *qp, struct ib_udata *u)
                                                                  { STUB_BODY("destroy_qp"); }
static int onic_stub_post_send(struct ib_qp *qp, const struct ib_send_wr *w,
                               const struct ib_send_wr **bad)    { STUB_BODY("post_send"); }
static int onic_stub_post_recv(struct ib_qp *qp, const struct ib_recv_wr *w,
                               const struct ib_recv_wr **bad)    { STUB_BODY("post_recv"); }
static int onic_stub_poll_cq(struct ib_cq *cq, int n, struct ib_wc *wc)
                                                                  { STUB_BODY("poll_cq"); }
static int onic_stub_req_notify_cq(struct ib_cq *cq, enum ib_cq_notify_flags f)
                                                                  { STUB_BODY("req_notify_cq"); }
static int onic_stub_create_ah(struct ib_ah *ah, struct rdma_ah_init_attr *a,
                               struct ib_udata *u)               { STUB_BODY("create_ah"); }
static int onic_stub_destroy_ah(struct ib_ah *ah, u32 flags)     { STUB_BODY("destroy_ah"); }
static struct ib_mr *onic_stub_reg_user_mr(struct ib_pd *pd, u64 s, u64 l,
                                           u64 va, int acc, struct ib_udata *u)
{ pr_info_ratelimited("onic_ib: b3_stub: reg_user_mr -> -EOPNOTSUPP\n");
  return ERR_PTR(-EOPNOTSUPP); }
static int onic_stub_dereg_mr(struct ib_mr *mr, struct ib_udata *u)
                                                                  { STUB_BODY("dereg_mr"); }
static struct ib_mr *onic_stub_alloc_mr(struct ib_pd *pd, enum ib_mr_type t, u32 n)
{ pr_info_ratelimited("onic_ib: b3_stub: alloc_mr -> -EOPNOTSUPP\n");
  return ERR_PTR(-EOPNOTSUPP); }
static int onic_stub_map_mr_sg(struct ib_mr *mr, struct scatterlist *sg, int n,
                               unsigned int *off)                { STUB_BODY("map_mr_sg"); }

/* ----- ops table (§3) ----- */

static const struct ib_device_ops onic_ib_ops = {
    .owner                       = THIS_MODULE,
    .driver_id                   = RDMA_DRIVER_UNKNOWN,
    .uverbs_abi_ver              = 1,
    .uverbs_no_driver_id_binding = 1,

    .query_device                = onic_query_device,
    .query_port                  = onic_query_port,
    .get_port_immutable          = onic_get_port_immutable,
    .get_link_layer              = onic_get_link_layer,
    .query_pkey                  = onic_query_pkey,
    .query_gid                   = onic_query_gid,
    .get_netdev                  = onic_get_netdev,
    .get_dev_fw_str              = onic_get_dev_fw_str,

    .alloc_ucontext              = onic_alloc_ucontext,
    .dealloc_ucontext            = onic_dealloc_ucontext,
    .alloc_pd                    = onic_alloc_pd,
    .dealloc_pd                  = onic_dealloc_pd,

    .create_cq                   = onic_stub_create_cq,
    .destroy_cq                  = onic_stub_destroy_cq,
    .create_qp                   = onic_stub_create_qp,
    .modify_qp                   = onic_stub_modify_qp,
    .query_qp                    = onic_stub_query_qp,
    .destroy_qp                  = onic_stub_destroy_qp,
    .post_send                   = onic_stub_post_send,
    .post_recv                   = onic_stub_post_recv,
    .poll_cq                     = onic_stub_poll_cq,
    .req_notify_cq               = onic_stub_req_notify_cq,
    .create_ah                   = onic_stub_create_ah,
    .destroy_ah                  = onic_stub_destroy_ah,
    .reg_user_mr                 = onic_stub_reg_user_mr,
    .dereg_mr                    = onic_stub_dereg_mr,
    .alloc_mr                    = onic_stub_alloc_mr,
    .map_mr_sg                   = onic_stub_map_mr_sg,

    INIT_RDMA_OBJ_SIZE(ib_ucontext, onic_ucontext, ibucontext),
    INIT_RDMA_OBJ_SIZE(ib_pd,       onic_pd,       ibpd),
};

/* ----- register / unregister (§8) ----- */

int onic_ib_register(struct onic_private *priv)
{
    struct onic_ib_dev *dev;
    char  name[IB_DEVICE_NAME_MAX];
    int   rv;

    if (!test_bit(ONIC_FLAG_MASTER_PF, priv->flags))
        return 0;

    dev = (struct onic_ib_dev *)ib_alloc_device(onic_ib_dev, ibdev);
    if (!dev)
        return -ENOMEM;

    dev->priv = priv;
    spin_lock_init(&dev->pd_lock);
    bitmap_zero(dev->pd_bitmap, ONIC_IB_MAX_PD);

    {
        const u8 *mac = priv->netdev->dev_addr;
        u8 guid[8] = { mac[0] | 0x02, mac[1], mac[2],
                       0xFF, 0xFE, mac[3], mac[4], mac[5] };
        memcpy(&dev->node_guid, guid, 8);
    }
    memcpy(&dev->ibdev.node_guid, &dev->node_guid, sizeof(__be64));
    dev->ibdev.node_type        = RDMA_NODE_IB_CA;
    dev->ibdev.phys_port_cnt    = 2;
    dev->ibdev.num_comp_vectors = 1;
    dev->ibdev.dev.parent       = &priv->pdev->dev;

    ib_set_device_ops(&dev->ibdev, &onic_ib_ops);
    rcu_assign_pointer(dev->port[0].netdev, priv->netdev);

    snprintf(name, sizeof(name), "onic_%02x%02x",
             priv->pdev->bus->number, priv->pdev->devfn);

    rv = ib_register_device(&dev->ibdev, name, &priv->pdev->dev);
    if (rv) {
        dev_err(&priv->pdev->dev, "ib_register_device(%s) err=%d\n", name, rv);
        ib_dealloc_device(&dev->ibdev);
        return rv;
    }

    rv = ib_device_set_netdev(&dev->ibdev, priv->netdev, 1);
    if (rv) {
        dev_err(&priv->pdev->dev, "ib_device_set_netdev p1 err=%d\n", rv);
        ib_unregister_device(&dev->ibdev);
        ib_dealloc_device(&dev->ibdev);
        return rv;
    }

    priv->ib_dev = dev;
    dev_info(&priv->pdev->dev, "ib_device '%s' registered (2 ports, RoCEv2)\n",
             name);
    return 0;
}

int onic_ib_set_port2_netdev(struct onic_private *primary,
                             struct onic_private *secondary)
{
    struct onic_ib_dev *dev = primary ? primary->ib_dev : NULL;

    if (!dev || !secondary || !secondary->netdev)
        return 0;
    rcu_assign_pointer(dev->port[1].netdev, secondary->netdev);
    return ib_device_set_netdev(&dev->ibdev, secondary->netdev, 2);
}

void onic_ib_unregister(struct onic_private *priv)
{
    struct onic_ib_dev *dev = priv ? priv->ib_dev : NULL;

    if (!dev)
        return;
    ib_unregister_device(&dev->ibdev);
    ib_dealloc_device(&dev->ibdev);
    priv->ib_dev = NULL;
}
```

### 10.3 `onic.h` diff (around line 31 and line 259)

```diff
 #include "onic_hardware.h"
 #include "onic_ptp.h"
 #include "onic_ernic_irq.h"
+#include "onic_ib.h"
```

```diff
 	struct onic_ernic_irq_ctx ernic_irq[2];
 	struct dentry            *dfs_root;   /* /sys/kernel/debug/onic/<netdev>/ */
+
+	/* B3: ib_device for RoCEv2 (master PF only — NULL elsewhere). */
+	struct onic_ib_dev       *ib_dev;
 };
```

### 10.4 `onic_main.c` diff

Around line 335 (`onic_setup_primary`, after `register_netdev` succeeds and
before `netif_carrier_off`):

```diff
 	rv = register_netdev(priv->netdev);
 	if (rv < 0) {
 		dev_err(&pdev->dev, "register_netdev (primary), err = %d", rv);
 		goto clear_interrupt;
 	}
 
+	rv = onic_ib_register(priv);
+	if (rv < 0) {
+		dev_err(&pdev->dev, "onic_ib_register, err = %d", rv);
+		unregister_netdev(priv->netdev);
+		goto clear_interrupt;
+	}
+
 	netif_carrier_off(priv->netdev);
 	*out = priv;
 	return 0;
```

Around line 526 (`onic_probe`, just after secondary setup returns non-fatal
failure or success):

```diff
 	if (primary->hw.num_cmacs >= 2) {
 		rv = onic_setup_secondary(primary, &secondary);
 		if (rv < 0) {
 			dev_err(&pdev->dev,
 				"secondary (CMAC1) setup failed (err=%d); primary still usable\n",
 				rv);
 			rv = 0;
+		} else {
+			/* Bind port 2 of the ib_device to the secondary's netdev
+			 * now that register_netdev() has assigned its name. */
+			(void)onic_ib_set_port2_netdev(primary, secondary);
 		}
 	}
```

Around line 450 (`onic_teardown_netdev`, BEFORE `onic_ernic_irq_teardown`):

```diff
 	cancel_work_sync(&priv->link_recovery_work);
+	onic_ib_unregister(priv);
 	onic_ernic_irq_teardown(priv);
 	onic_clear_interrupt(priv);
```

Note: `onic_ib_unregister` is master-only-safe (it null-checks `priv->ib_dev`
and returns immediately on the secondary path). No extra `test_bit` gating
needed at the call site.

### 10.5 `Makefile`

No change — `BASE_OBJS := $(patsubst $(srcdir)/%.c,%.o,$(wildcard $(srcdir)/*.c ...))`
picks up `onic_ib.c` automatically (F5 precedent: `onic_ernic_irq.c` was
added the same way).

---

## 11. Risks and VERIFY items

### 11.1 Kernel IB core availability (blocker)

- `CONFIG_INFINIBAND=m` is confirmed for the target 6.8.0-107-generic kernel.
- **VERIFY** before first insmod: `modprobe ib_core && lsmod | grep ib_core`
  must show a refcount. If the user's distro ships `ib_core` modular and
  blacklisted, `onic.ko` will refuse to load.

### 11.2 `ib_device_ops` struct layout / kernel version

- The struct has churned between LTS kernels. We target 6.8 specifically;
  field names cited above (`query_device`, `get_port_immutable`,
  `INIT_RDMA_OBJ_SIZE`) all exist at `include/rdma/ib_verbs.h:2336` on this
  kernel.
- **VERIFY** on any future rebase/backport: if `uverbs_abi_ver` disappears
  (merged into `driver_id`), or `INIT_RDMA_OBJ_SIZE` takes a different
  signature, the compile will break immediately — not silent.

### 11.3 RoCE GID cache auto-population

- The core builds GIDs from `netdev->dev_addr` + each assigned IP address on
  the netdev. If `ip_gids = 1` in `query_port`'s result, `add_gid`/`del_gid`
  are optional.
- **VERIFY** in Phase 3 test: `ibv_devinfo -v` should list at least one GID
  per port (the link-local IPv6). If empty, the netdev may be `DOWN`, or the
  port `state` returned in `query_port` may be stuck at `IB_PORT_DOWN` even
  when carrier is up. Double-check `netif_carrier_ok(ndev)` semantics against
  `onic_user_thread_fn`'s carrier toggles.

### 11.4 Unique device name across cards

- We name `onic_<bus><devfn>` (hex). With two cards in one host this yields
  distinct names (different bus numbers). Same-bus collisions are impossible
  because `devfn` differs.
- **VERIFY:** `ls /sys/class/infiniband` after inserting with two cards
  should show two distinct entries.

### 11.5 `active_speed` enum mismatch

- `IB_SPEED_EDR` is ~100 Gb/s but the standard-preferred encoding for
  100 Gb/s is "EDR" (4×25 = 100). If userspace tools (e.g., `ibstat`) parse
  this strictly and prefer `IB_SPEED_HDR`, a future fix may be needed.
- Not a B3 blocker. **VERIFY:** `ibv_devinfo -v` rate line reads "100 Gb/sec".

### 11.6 `driver_id = RDMA_DRIVER_UNKNOWN`

- Upstream has not assigned a slot for ERNIC. `UNKNOWN` works for the core
  but disables provider-specific userspace lib matching. We don't ship a
  userspace provider yet (B5+), so this is fine.
- **VERIFY:** that `ibv_devinfo -v` doesn't print any warning when driver_id
  is UNKNOWN. rxe precedent says it doesn't.

### 11.7 Teardown ordering — `unregister_netdev` vs `ib_unregister_device`

- `ib_device_set_netdev` holds a ref on the netdev. If `unregister_netdev`
  runs while the ib_device is still alive, the netdev goes to
  NETDEV_UNREGISTER state and IB core responds via `get_netdev` returning
  NULL — safe. We then call `ib_unregister_device` which drops its ref.
- **But** our patch calls `onic_ib_unregister` BEFORE `unregister_netdev`
  (they're both inside `onic_teardown_netdev` — see §8.2). That's the safer
  order: IB core quiesces first, then netdev goes.
- **VERIFY** teardown order matches diff in §10.4 — `onic_ib_unregister`
  appears between `cancel_work_sync` and `onic_ernic_irq_teardown`, which is
  BEFORE `unregister_netdev(priv->netdev)` a few lines later.
