# B3.5 — `libonic` userspace rdma-core provider

**Status:** design + patch sketch only. Nothing applied to the repo.
**Last updated:** 2026-04-23.
**Prereqs landed:** B3 kernel `ib_device onic_0100` registered, dual-port
ACTIVE, `/dev/infiniband/uverbs1` present, `/sys/class/infiniband/onic_0100/`
populated, `driver_id=RDMA_DRIVER_UNKNOWN`, `uverbs_abi_ver=1`,
`uverbs_no_driver_id_binding=1`.
**Unblocks:** `ibv_devices` / `ibv_devinfo -d onic_0100` enumeration, and
from there B5 (PD/MR slab + real verbs uAPI), B11 (perftest).

---

## 1. Scope and non-goals

**In scope:**

1. Ship a shared object `libonic-rdmav<N>.so` that rdma-core's plugin loader
   picks up and whose `match_device` returns a non-NULL `verbs_device` for
   `onic_0100` / `onic_0101` / anything carrying our PCI ID or our
   `driver_id` sysfs label.
2. Provide the *minimum* user-side verbs that `ibv_devinfo -v` and any
   `ibv_alloc_pd` caller hit without crashing:
   `alloc_context`/`free_context`, `query_device_ex`, `query_port`,
   `alloc_pd`/`dealloc_pd`.
3. Passthrough via the public `ibv_cmd_*` helpers (no bespoke ioctls) —
   kernel does all the real work; this lib is pure envelope.
4. Stubs for every other verb entry point (`create_cq`, `create_qp`,
   `reg_mr`, `post_send`, ...): set `errno = EOPNOTSUPP` and return
   NULL / -1. Never SEGV, never return garbage.
5. Build cleanly against the rdma-core sources matching the installed
   runtime (see §11.1 — *this is the critical risk*).
6. Installable via `make install` into
   `/usr/lib/x86_64-linux-gnu/libibverbs/`.

**Explicitly out of scope (deferred):**

- Real QP / CQ / MR lifecycle — owned by B5/B6/B7/B8 once the kernel
  uverbs handlers exist.
- Doorbell mmap / completion polling — B8.
- Integration into upstream rdma-core's `providers/` tree, Debian
  packaging, dkms — deferred until API stabilises.
- Non-OFED / non-DOCA-HOST distros. We target this one machine first.

---

## 2. Runtime facts discovered on this box

All commands run before writing this doc. The brief lists some values that
disagree with what's actually installed; the **installed box wins** and
the doc below uses those values.

| What | Brief said | Installed | Verified by |
|---|---|---|---|
| libibverbs pkg version | 2601.0.7-1 (MLNX_OFED 26.01) | **2510.0.11-1 (DOCA-HOST 3.2.1)** | `dpkg -l libibverbs1` |
| Provider ABI suffix | `-rdmav59` | **`-rdmav57`** | `ls /usr/lib/x86_64-linux-gnu/libibverbs/` → `libmlx5-rdmav57.so` |
| Private symbol | — | `verbs_register_driver_57@IBVERBS_PRIVATE_57` | `nm -D libmlx5-rdmav57.so` |
| `rdma-core-dev` / `libibverbs-dev` | — | installed 2510.0.11-1 | `dpkg -l libibverbs-dev` |
| Provider-dev header `driver.h` | assumed present | **NOT shipped** (see §11.1) | `find /usr/include -name driver.h` → none |
| Reference PCI VID:DID of onic HW | `0x10ee` (Xilinx) | **`1e52:401e`** on this host | `lspci -nn -s 0000:01:00.0` |
| Modalias of onic_0100 | pci:v10EE… expected | — (device not yet bound / ib_device not registered at the time of check; `cat /sys/class/infiniband/onic_0100/device/modalias` is the definitive value once B3 is loaded) | `cat /sys/class/infiniband/mlx5_0/device/modalias` works for reference |

**Decisions driven by the above:**

- The filename MUST be `libonic-rdmav57.so`, not `-rdmav59`.
- The private symbol the loader calls is `verbs_register_driver_57` —
  any helper macros in rdma-core that expand to that name are the right
  ones. If we hand-roll (see §3.3), the call site must be literally
  `verbs_register_driver_57(&verbs_provider_onic)`.
- The match table must cover **both** `0x10ee` (if we ever bind to a U200
  PCIe function directly) and `0x1e52:0x401e` (what's in the host right
  now — looks like a Tenstorrent card ID). Safer: also match by the
  kernel `driver_id` string so naming is robust under PCI ID churn.

---

## 3. rdma-core provider architecture reference

### 3.1 How libibverbs finds providers

1. `ibv_get_device_list()` walks `/sys/class/infiniband/*`, reads
   `.../device/modalias` for each.
2. It then `dlopen`s every `libXXX-rdmavNN.so` in the provider dir
   (`/usr/lib/x86_64-linux-gnu/libibverbs/`).
3. Each provider registers itself during its `__attribute__((constructor))`
   (or via an explicit `PROVIDER_DRIVER` macro) by calling
   `verbs_register_driver_<N>(&verbs_provider_<name>)`.
4. For each device in the sysfs list, libibverbs walks the registered
   providers in order and calls `match_device(sysfs_dev)`. The first
   provider that returns non-NULL owns the device.

### 3.2 Key structs (names stable across 2024+ rdma-core)

Full definitions live in rdma-core's private `providers/driver.h` / `util/`.
Signatures below are the subset we need; they compile against rdma-core's
real headers. Treat as authoritative **only after the user checks out the
matching rdma-core source** (§11.1).

```c
/* Rough shape — confirm from rdma-core source, provide driver.h path. */
struct verbs_match_ent {
    uint32_t vendor;            /* PCI vendor or kernel driver_id tag */
    uint32_t device;            /* PCI device */
    const char *modalias;       /* optional modalias glob */
    enum { VERBS_MATCH_PCI, VERBS_MATCH_MODALIFUSED_DRIVER_ID } kind;
};

struct verbs_device_ops {
    const char *name;                     /* "onic" */
    uint32_t match_min_abi_version;       /* 1  — matches kernel uverbs_abi_ver */
    uint32_t match_max_abi_version;       /* 1 */
    const struct verbs_match_ent *match_table;
    uint32_t driver_id;                   /* RDMA_DRIVER_UNKNOWN (0) */
    bool     match_device;                /* or an fn ptr, version-dependent */

    struct verbs_device *(*alloc_device)(struct verbs_sysfs_dev *sysfs_dev);
    void (*uninit_device)(struct verbs_device *vd);

    struct verbs_context *(*alloc_context)(struct ibv_device *device,
                                           int cmd_fd, void *private_data);
    void (*free_context)(struct ibv_context *ctx);
};

/* Registration: */
void verbs_register_driver_57(const struct verbs_device_ops *ops);
```

### 3.3 Three implementation routes (pick one in §4)

**A. Build in-tree against upstream rdma-core.**
Clone github.com/linux-rdma/rdma-core at tag `v57.x`, add
`providers/onic/`, hook it into `providers/CMakeLists.txt`. Use the real
`PROVIDER_DRIVER()` macro from `util/driver.h`. **Pros:** textbook, works.
**Cons:** rebuilds the whole rdma-core; can clash with installed
`libibverbs1`.

**B. Build out-of-tree against rdma-core source, link against installed
`libibverbs.so`.** Clone rdma-core just to get headers
(`providers/driver.h`, `util/util.h`, `kernel-abi/*`), build
`libonic-rdmav57.so` standalone with `-I path/to/rdma-core`. **Pros:**
cheap, easy to iterate. **Cons:** must keep rdma-core tree at a tag
whose ABI (= 57) matches what's installed; header churn between minor
versions is real.

**C. Hand-roll the ABI: declare the structs ourselves, call the private
symbol directly.** Fragile — the struct layout is *not* guaranteed
stable across rdma-core versions. **Reject** unless (B) proves
impossible. Flagged here only so we don't "discover" it later.

**Recommendation: route (B).** §7 shows the build system for it.

---

## 4. Match strategy

Match by **PCI vendor/device** pair *and* by the kernel `driver_id`
attribute exposed through sysfs. rdma-core's match walker tries entries
in order; the first hit wins.

```c
/* libonic.c — match_table */
static const struct verbs_match_ent onic_match_table[] = {
    /* Xilinx / AMD Alveo U200 (brief-stated target) */
    VERBS_PCI_MATCH(0x10ee, 0x903f, NULL),
    VERBS_PCI_MATCH(0x10ee, 0x9034, NULL),
    VERBS_PCI_MATCH(0x10ee, 0x9038, NULL),
    /* Currently-populated slot on this host (VERIFY: may be a stand-in) */
    VERBS_PCI_MATCH(0x1e52, 0x401e, NULL),
    /* Fallback: match any ib_device with driver name "onic" regardless of PCI.
     * Relies on kernel's ib_device name prefix. */
    VERBS_NAME_MATCH("onic_", NULL),
    {}
};
```

`VERBS_PCI_MATCH` / `VERBS_NAME_MATCH` are the rdma-core helper macros in
`util/driver.h`. If that header is locked to PCI-only matching, fall back
to writing the driver-name match in `alloc_device()` itself — it receives
the `verbs_sysfs_dev*` and can inspect the kernel device name.

**Alternative rejected:** matching on `sys_image_guid` is fragile because
the guid is derived at probe time from the MAC and varies per card.

---

## 5. Context allocation

`alloc_context()` is where rdma-core hands us an already-opened fd for
`/dev/infiniband/uverbsN`. We do two things:

1. Allocate our `struct onic_context` (a `verbs_context` wrapper with
   extra fields we'll fill later).
2. Install our op table by setting every field of `verbs_set_ops(...)`.

```c
struct onic_context {
    struct verbs_context ibvctx;   /* MUST be last-ish for verbs_get_ctx */
    /* room to grow: doorbell BAR mapping, per-ctx uar, etc. — B5/B8 */
};
```

No `ibv_cmd_get_context` call is needed because the kernel's
`uverbs_no_driver_id_binding = 1` means there's no driver-specific open
ioctl; the bare open of `/dev/infiniband/uverbs1` plus the context alloc
in libibverbs is enough.

`free_context()` closes any mmaps (none in B3.5) and frees the struct.

---

## 6. Op table

The table is the `struct verbs_context_ops` (inside `verbs_context`).
Only the ops listed below are non-stub. Every other slot gets a tiny
`errno=EOPNOTSUPP; return -1;` stub (or `return NULL` for pointer
returns).

### 6.1 Real (passthrough) ops

| Verb | Implementation | Why passthrough works |
|---|---|---|
| `query_device_ex` | `ibv_cmd_query_device_any()` | Kernel B3 `onic_query_device` returns all fields. |
| `query_port`      | `ibv_cmd_query_port()`      | Kernel B3 `onic_query_port` handles it. |
| `alloc_pd`        | `ibv_cmd_alloc_pd()`        | Kernel B3 PD bitmap (§5 of b3_ib_device_skeleton.md). |
| `dealloc_pd`      | `ibv_cmd_dealloc_pd()`      | Clears bitmap bit. |

```c
static int onic_query_device_ex(struct ibv_context *ctx,
                                const struct ibv_query_device_ex_input *in,
                                struct ibv_device_attr_ex *attr,
                                size_t attr_size)
{
    struct ibv_query_device_ex cmd = {};
    struct ib_uverbs_ex_query_device_resp resp = {};
    int ret;

    ret = ibv_cmd_query_device_any(ctx, in, attr, attr_size,
                                   &resp, sizeof(resp));
    if (ret)
        return ret;
    /* Any fields the kernel didn't fill (e.g. driver-private) go here.
     * For B3.5 there are none — kernel B3 returns a complete attr set. */
    return 0;
}

static int onic_query_port(struct ibv_context *ctx, uint8_t port,
                           struct ibv_port_attr *attr)
{
    struct ibv_query_port cmd;
    return ibv_cmd_query_port(ctx, port, attr, &cmd, sizeof(cmd));
}

static struct ibv_pd *onic_alloc_pd(struct ibv_context *ctx)
{
    struct ibv_alloc_pd cmd = {};
    struct ib_uverbs_alloc_pd_resp resp = {};
    struct ibv_pd *pd = calloc(1, sizeof(*pd));
    if (!pd)
        return NULL;
    if (ibv_cmd_alloc_pd(ctx, pd, &cmd, sizeof(cmd), &resp, sizeof(resp))) {
        free(pd);
        return NULL;
    }
    return pd;
}

static int onic_dealloc_pd(struct ibv_pd *pd)
{
    int ret = ibv_cmd_dealloc_pd(pd);
    if (ret)
        return ret;
    free(pd);
    return 0;
}
```

### 6.2 Stubs (all set `errno = EOPNOTSUPP`)

`create_cq`, `destroy_cq`, `resize_cq`, `req_notify_cq`, `poll_cq`,
`create_qp`, `modify_qp`, `query_qp`, `destroy_qp`,
`post_send`, `post_recv`, `create_srq`, `destroy_srq`, `modify_srq`,
`query_srq`, `post_srq_recv`, `reg_mr`, `rereg_mr`, `dereg_mr`,
`alloc_mw`, `dealloc_mw`, `bind_mw`,
`create_ah`, `destroy_ah`, `attach_mcast`, `detach_mcast`,
`create_flow`, `destroy_flow`.

Pattern — all of them use one macro:

```c
#define STUB_ERRNO() do { errno = EOPNOTSUPP; } while (0)

#define STUB_INT(name, ...)                                            \
    static int onic_##name(__VA_ARGS__)                                \
    { STUB_ERRNO(); return -1; }

#define STUB_PTR(ret_t, name, ...)                                     \
    static ret_t *onic_##name(__VA_ARGS__)                             \
    { STUB_ERRNO(); return NULL; }

STUB_PTR(struct ibv_cq,  create_cq,
         struct ibv_context *ctx, int cqe, struct ibv_comp_channel *ch,
         int comp_vec)
STUB_INT(destroy_cq,     struct ibv_cq *cq)
STUB_INT(poll_cq,        struct ibv_cq *cq, int ne, struct ibv_wc *wc)
STUB_INT(req_notify_cq,  struct ibv_cq *cq, int solicited_only)
STUB_PTR(struct ibv_qp,  create_qp,
         struct ibv_pd *pd, struct ibv_qp_init_attr *a)
STUB_INT(modify_qp,      struct ibv_qp *qp, struct ibv_qp_attr *a, int mask)
STUB_INT(query_qp,       struct ibv_qp *qp, struct ibv_qp_attr *a, int mask,
                         struct ibv_qp_init_attr *ia)
STUB_INT(destroy_qp,     struct ibv_qp *qp)
STUB_INT(post_send,      struct ibv_qp *qp, struct ibv_send_wr *w,
                         struct ibv_send_wr **bad)
STUB_INT(post_recv,      struct ibv_qp *qp, struct ibv_recv_wr *w,
                         struct ibv_recv_wr **bad)
STUB_PTR(struct ibv_mr,  reg_mr,
         struct ibv_pd *pd, void *addr, size_t len, uint64_t hca_va, int acc)
STUB_INT(dereg_mr,       struct ibv_mr *mr)
STUB_PTR(struct ibv_ah,  create_ah,
         struct ibv_pd *pd, struct ibv_ah_attr *a)
STUB_INT(destroy_ah,     struct ibv_ah *ah)
STUB_INT(attach_mcast,   struct ibv_qp *qp, const union ibv_gid *g, uint16_t l)
STUB_INT(detach_mcast,   struct ibv_qp *qp, const union ibv_gid *g, uint16_t l)
```

---

## 7. Files the provider ships

Target directory (new, outside `open-nic-driver/`):

```
/home/alex/mpi-shfs/fpga/libonic-provider/
├── libonic.c          (~320 LoC)  — main provider + ops + stubs
├── libonic.h          (~60  LoC)  — onic_context, onic_device structs
├── Makefile           (~60  LoC)  — standalone build against rdma-core
├── install.sh         (~15  LoC)  — sudo install + ldconfig
└── README.md          (optional) — usage blurb
```

### 7.1 `libonic.h`

```c
/* SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause */
#ifndef LIBONIC_H
#define LIBONIC_H

#include <infiniband/verbs.h>
#include <infiniband/driver.h>   /* from rdma-core source tree (see §11.1) */
#include <util/util.h>

struct onic_device {
    struct verbs_device vdev;
};

struct onic_context {
    struct verbs_context ibvctx;
    /* future: uar base, doorbell fd, per-ctx locks — B5/B8 */
};

static inline struct onic_context *to_onic_ctx(struct ibv_context *ctx)
{
    return container_of(ctx, struct onic_context, ibvctx.context);
}

#endif
```

### 7.2 `libonic.c`

```c
/* SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause
 * libonic.c — userspace RDMA provider for the onic ib_device.
 * Matches B3 kernel: PD only, everything else -EOPNOTSUPP stub.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <infiniband/driver.h>
#include <infiniband/verbs.h>
#include <util/util.h>
#include <kernel-abi/ib_user_verbs.h>
#include "libonic.h"

/* ---- real ops ---- */

static int onic_query_device_ex(struct ibv_context *ctx,
                                const struct ibv_query_device_ex_input *in,
                                struct ibv_device_attr_ex *attr,
                                size_t attr_size)
{
    struct ib_uverbs_ex_query_device_resp resp = {};
    struct ibv_query_device_ex cmd = {};
    return ibv_cmd_query_device_any(ctx, in, attr, attr_size,
                                    &resp, sizeof(resp));
}

static int onic_query_port_op(struct ibv_context *ctx, uint8_t port,
                              struct ibv_port_attr *attr)
{
    struct ibv_query_port cmd;
    return ibv_cmd_query_port(ctx, port, attr, &cmd, sizeof(cmd));
}

static struct ibv_pd *onic_alloc_pd_op(struct ibv_context *ctx)
{
    struct ib_uverbs_alloc_pd_resp resp = {};
    struct ibv_alloc_pd            cmd  = {};
    struct ibv_pd                 *pd   = calloc(1, sizeof(*pd));
    if (!pd) {
        errno = ENOMEM;
        return NULL;
    }
    if (ibv_cmd_alloc_pd(ctx, pd, &cmd, sizeof(cmd), &resp, sizeof(resp))) {
        free(pd);
        return NULL;
    }
    return pd;
}

static int onic_dealloc_pd_op(struct ibv_pd *pd)
{
    int ret = ibv_cmd_dealloc_pd(pd);
    if (ret)
        return ret;
    free(pd);
    return 0;
}

/* ---- stubs (§6.2) ---- */

#define STUB_ERRNO() do { errno = EOPNOTSUPP; } while (0)

#define STUB_INT_0(fn, arg)                                             \
    static int onic_##fn(arg) { STUB_ERRNO(); return -1; }
#define STUB_PTR(rt, fn, args)                                          \
    static rt *onic_##fn args { STUB_ERRNO(); return NULL; }

STUB_PTR(struct ibv_cq,  create_cq,
         (struct ibv_context *c, int cqe, struct ibv_comp_channel *ch, int v))
static int onic_destroy_cq(struct ibv_cq *cq)           { STUB_ERRNO(); return -1; }
static int onic_resize_cq(struct ibv_cq *cq, int cqe)   { STUB_ERRNO(); return -1; }
static int onic_poll_cq(struct ibv_cq *cq, int n, struct ibv_wc *wc)
                                                        { STUB_ERRNO(); return -1; }
static int onic_req_notify_cq(struct ibv_cq *cq, int s) { STUB_ERRNO(); return -1; }

STUB_PTR(struct ibv_qp,  create_qp,
         (struct ibv_pd *p, struct ibv_qp_init_attr *a))
static int onic_modify_qp(struct ibv_qp *q, struct ibv_qp_attr *a, int m)
                                                        { STUB_ERRNO(); return -1; }
static int onic_query_qp(struct ibv_qp *q, struct ibv_qp_attr *a, int m,
                         struct ibv_qp_init_attr *ia)   { STUB_ERRNO(); return -1; }
static int onic_destroy_qp(struct ibv_qp *q)            { STUB_ERRNO(); return -1; }
static int onic_post_send(struct ibv_qp *q, struct ibv_send_wr *w,
                          struct ibv_send_wr **bad)
                                                        { STUB_ERRNO(); *bad = w; return -1; }
static int onic_post_recv(struct ibv_qp *q, struct ibv_recv_wr *w,
                          struct ibv_recv_wr **bad)
                                                        { STUB_ERRNO(); *bad = w; return -1; }

STUB_PTR(struct ibv_mr,  reg_mr,
         (struct ibv_pd *p, void *a, size_t l, uint64_t va, int acc))
static int onic_dereg_mr(struct ibv_mr *mr)             { STUB_ERRNO(); return -1; }
STUB_PTR(struct ibv_ah,  create_ah,
         (struct ibv_pd *p, struct ibv_ah_attr *a))
static int onic_destroy_ah(struct ibv_ah *ah)           { STUB_ERRNO(); return -1; }
static int onic_attach_mcast(struct ibv_qp *q, const union ibv_gid *g, uint16_t l)
                                                        { STUB_ERRNO(); return -1; }
static int onic_detach_mcast(struct ibv_qp *q, const union ibv_gid *g, uint16_t l)
                                                        { STUB_ERRNO(); return -1; }

/* ---- context alloc/free ---- */

static const struct verbs_context_ops onic_ctx_ops = {
    .query_device_ex  = onic_query_device_ex,
    .query_port       = onic_query_port_op,
    .alloc_pd         = onic_alloc_pd_op,
    .dealloc_pd       = onic_dealloc_pd_op,

    .create_cq        = onic_create_cq,
    .destroy_cq       = onic_destroy_cq,
    .resize_cq        = onic_resize_cq,
    .poll_cq          = onic_poll_cq,
    .req_notify_cq    = onic_req_notify_cq,
    .create_qp        = onic_create_qp,
    .modify_qp        = onic_modify_qp,
    .query_qp         = onic_query_qp,
    .destroy_qp       = onic_destroy_qp,
    .post_send        = onic_post_send,
    .post_recv        = onic_post_recv,
    .reg_mr           = onic_reg_mr,
    .dereg_mr         = onic_dereg_mr,
    .create_ah        = onic_create_ah,
    .destroy_ah       = onic_destroy_ah,
    .attach_mcast     = onic_attach_mcast,
    .detach_mcast     = onic_detach_mcast,
};

static struct verbs_context *
onic_alloc_context(struct ibv_device *ibdev, int cmd_fd, void *private_data)
{
    struct onic_context *ctx;

    ctx = verbs_init_and_alloc_context(ibdev, cmd_fd, ctx, ibvctx,
                                       RDMA_DRIVER_UNKNOWN);
    if (!ctx)
        return NULL;

    verbs_set_ops(&ctx->ibvctx, &onic_ctx_ops);
    return &ctx->ibvctx;
}

static void onic_free_context(struct ibv_context *ctx)
{
    struct onic_context *octx = to_onic_ctx(ctx);
    verbs_uninit_context(&octx->ibvctx);
    free(octx);
}

static struct verbs_device *
onic_device_alloc(struct verbs_sysfs_dev *sysfs_dev)
{
    struct onic_device *dev = calloc(1, sizeof(*dev));
    if (!dev)
        return NULL;
    return &dev->vdev;
}

static void onic_uninit_device(struct verbs_device *vd)
{
    free(container_of(vd, struct onic_device, vdev));
}

/* ---- match table (§4) ---- */

static const struct verbs_match_ent onic_match_table[] = {
    VERBS_PCI_MATCH(0x10ee, 0x903f, NULL),   /* Xilinx U200 candidate */
    VERBS_PCI_MATCH(0x10ee, 0x9034, NULL),
    VERBS_PCI_MATCH(0x1e52, 0x401e, NULL),   /* what lspci shows today (VERIFY) */
    VERBS_NAME_MATCH("onic_", NULL),         /* fallback by ib_device name */
    {},
};

/* ---- provider descriptor + registration ---- */

static const struct verbs_device_ops verbs_provider_onic = {
    .name                   = "onic",
    .match_min_abi_version  = 1,
    .match_max_abi_version  = 1,
    .match_table            = onic_match_table,
    .alloc_device           = onic_device_alloc,
    .uninit_device          = onic_uninit_device,
    .alloc_context          = onic_alloc_context,
    .free_context           = onic_free_context,
};

PROVIDER_DRIVER(onic, verbs_provider_onic);
```

### 7.3 `Makefile`

```make
# libonic-provider/Makefile
# Builds libonic-rdmav57.so against the rdma-core source tree checked out
# by the user. Override RDMA_CORE=... on the command line if needed.

RDMA_CORE      ?= /opt/src/rdma-core
ABI_VER        ?= 57
LIBNAME        := libonic-rdmav$(ABI_VER).so
PROVIDER_DIR   := /usr/lib/x86_64-linux-gnu/libibverbs

CFLAGS  += -Wall -Wextra -Werror -fPIC -O2 -std=gnu11
CFLAGS  += -I$(RDMA_CORE)
CFLAGS  += -I$(RDMA_CORE)/libibverbs
CFLAGS  += -I$(RDMA_CORE)/providers
CFLAGS  += -I$(RDMA_CORE)/util
CFLAGS  += -I$(RDMA_CORE)/kernel-headers
CFLAGS  += $(shell pkg-config --cflags libibverbs)

LDFLAGS += -shared -Wl,--version-script=libonic.map
LDLIBS  += $(shell pkg-config --libs libibverbs)

OBJS := libonic.o

all: $(LIBNAME)

$(LIBNAME): $(OBJS) libonic.map
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

libonic.map:
	printf '%s\n' \
	  'IBVERBS_PROVIDER_1.0 {' \
	  '  local: *;' \
	  '};' > $@

install: $(LIBNAME)
	install -m 0644 $(LIBNAME) $(PROVIDER_DIR)/
	ldconfig

uninstall:
	rm -f $(PROVIDER_DIR)/$(LIBNAME)
	ldconfig

clean:
	rm -f $(OBJS) $(LIBNAME) libonic.map

.PHONY: all install uninstall clean
```

All symbols of interest are hidden via the version script — the only
exported symbol is what `PROVIDER_DRIVER` itself exports (typically a
constructor that calls `verbs_register_driver_57`).

### 7.4 `install.sh`

```sh
#!/bin/sh
# install.sh — copy libonic-rdmavNN.so into the distro provider dir.
set -eu
: "${ABI_VER:=57}"
LIB="libonic-rdmav${ABI_VER}.so"
DEST="/usr/lib/x86_64-linux-gnu/libibverbs"

[ -f "$LIB" ] || { echo "build first: make"; exit 1; }
sudo install -m 0644 "$LIB" "$DEST/"
sudo ldconfig
echo "installed: $DEST/$LIB"
```

---

## 8. Install flow

```sh
# 0. Prereqs (once)
sudo apt install rdma-core libibverbs-dev ibverbs-utils build-essential
# VERIFY: the ABI suffix on this box
ls /usr/lib/x86_64-linux-gnu/libibverbs/   # look for libmlx5-rdmavNN.so → N=57

# 1. Clone the matching rdma-core source (tag = upstream release = ABI).
#    Installed libibverbs1 is 2510.0.11-1 → upstream v57.x tree.
git clone --branch v57.0 --depth 1 \
    https://github.com/linux-rdma/rdma-core.git /opt/src/rdma-core
# VERIFY: /opt/src/rdma-core/providers/driver.h exists and compiles
ls /opt/src/rdma-core/providers/driver.h
ls /opt/src/rdma-core/util/util.h

# 2. Build
cd /home/alex/mpi-shfs/fpga/libonic-provider
make RDMA_CORE=/opt/src/rdma-core

# 3. Install
./install.sh        # or: sudo make install

# 4. Confirm
ls -l /usr/lib/x86_64-linux-gnu/libibverbs/libonic-rdmav57.so
sudo ldconfig -p | grep onic
```

---

## 9. Test plan

### Phase 1 — compile

```sh
cd /home/alex/mpi-shfs/fpga/libonic-provider
make RDMA_CORE=/opt/src/rdma-core 2>&1 | tee /tmp/b3p5_build.log
```

Expected: one `.so`, no warnings, `nm -D libonic-rdmav57.so | grep
verbs_register_driver_57` shows the symbol as UNDEFINED (we call the
private libibverbs entry point).

### Phase 2 — enumeration

```sh
sudo make install
ibv_devices
# Expected: two lines, mlx5_0 and onic_0100. If only mlx5_0 appears,
# dlopen probably rejected our .so — run with strace:
strace -f -e trace=open,openat -o /tmp/ibv_devices.strace ibv_devices
grep libonic /tmp/ibv_devices.strace
```

Common failure: `libonic-rdmav57.so: undefined symbol …` — means we're
using the wrong ABI suffix or `driver.h` signatures don't match.

### Phase 3 — devinfo

```sh
ibv_devinfo -d onic_0100
# Expected: transport IB, link_layer Ethernet, 2 ports, state PORT_ACTIVE,
# max_mtu 4096, GID0 present on each port (RoCEv2 default).

ibv_devinfo -v -d onic_0100
# Expected: full attr dump matching B3's onic_query_device caps:
# max_qp=255, max_cq=255, max_mr=255, max_pd=256, max_sge=1, vendor_id=0x10ee.
```

### Phase 4 — PD alloc (positive path)

```sh
cat > /tmp/pd_test.c <<'EOF'
#include <infiniband/verbs.h>
#include <stdio.h>
int main(void) {
    int n;
    struct ibv_device **l = ibv_get_device_list(&n);
    for (int i = 0; i < n; i++)
        if (!strcmp(ibv_get_device_name(l[i]), "onic_0100")) {
            struct ibv_context *c = ibv_open_device(l[i]);
            struct ibv_pd *pd = ibv_alloc_pd(c);
            printf("pd=%p handle=%u\n", (void *)pd, pd ? pd->handle : 0);
            if (pd) ibv_dealloc_pd(pd);
            ibv_close_device(c);
        }
    ibv_free_device_list(l);
    return 0;
}
EOF
gcc /tmp/pd_test.c -libverbs -o /tmp/pd_test && /tmp/pd_test
# Expected: "pd=0x... handle=0" (or similar non-NULL), no leaks.
dmesg | tail       # Expect no EOPNOTSUPP log from the kernel side.
```

### Phase 5 — verb stub (negative path, must NOT SEGV)

```sh
sudo ibv_rc_pingpong -d onic_0100 -g 0
# Expected failure: "ibv_create_qp: Operation not supported", exit 1.
# MUST NOT SEGV, MUST NOT hang, MUST close cleanly.
# Kernel dmesg shows: onic_ib: b3_stub: create_qp -> -EOPNOTSUPP
```

---

## 10. Full patch sketch

See §7.1, §7.2, §7.3, §7.4 above — those ARE the files, labelled with
target paths. The user's integration work is:

```
mkdir -p /home/alex/mpi-shfs/fpga/libonic-provider
cd       /home/alex/mpi-shfs/fpga/libonic-provider
# Paste §7.1 → libonic.h
# Paste §7.2 → libonic.c
# Paste §7.3 → Makefile
# Paste §7.4 → install.sh
chmod +x install.sh
```

No changes to `open-nic-driver/` — this is a strictly additive, separate
component.

---

## 11. Risks and VERIFY items

### 11.1 Private header `driver.h` not in the distro (HEADLINE RISK)

`libibverbs-dev` ships `verbs.h`, `verbs_api.h`, `ib_user_ioctl_verbs.h`
and a handful of vendor-extension headers (`mlx5dv.h`, `efadv.h`), but
NOT the provider-internal `driver.h` that defines
`struct verbs_device_ops`, `struct verbs_match_ent`, `PROVIDER_DRIVER`,
`ibv_cmd_*` wrappers, and the `verbs_register_driver_57` symbol. Grep
confirmed this on the target box:

```
$ find /usr/include -name driver.h 2>/dev/null
(empty)
$ nm -D /usr/lib/x86_64-linux-gnu/libibverbs/libmlx5-rdmav57.so | grep register_driver
U verbs_register_driver_57@IBVERBS_PRIVATE_57
```

**The symbol exists** (`IBVERBS_PRIVATE_57` namespace in
`libibverbs.so.1`) but its declaration is only in rdma-core's source
tree under `providers/driver.h` / `libibverbs/driver.h`. **You cannot
build this provider without that source tree.**

**Required action (HUMAN SIGN-OFF):**

Choose between routes A/B/C from §3.3. Route B (clone rdma-core @ v57.0
just for headers, link against installed `libibverbs.so.1`) is
recommended. Anyone approving this doc must confirm:

1. They're okay cloning `https://github.com/linux-rdma/rdma-core.git`
   and pinning to a matching tag (`v57.0`, matching
   `libibverbs1=2510.0.11-1`).
2. That they understand `libibverbs-dev` upgrades *will* force a
   coordinated rebuild of `libonic-rdmav<N>.so` whenever the distro
   bumps the ABI suffix (e.g., next rdma-core release would be v58 →
   need `libonic-rdmav58.so`).

If (1) is not acceptable: fall back to route C (hand-rolled ABI). That
moves the risk from "build breaks on rdma-core bump" to "load silently
misbehaves on rdma-core bump" — strictly worse. Do not pick C.

### 11.2 `PROVIDER_DRIVER` macro name and signature

`PROVIDER_DRIVER()` in rdma-core has been stable since v22 but its exact
expansion (whether it takes one or two args, whether it registers via
constructor or via `verbs_register_driver_<N>()`) has varied. Confirm in
`/opt/src/rdma-core/util/util.h` before trusting §7.2:

```sh
grep -n 'define PROVIDER_DRIVER' /opt/src/rdma-core/util/util.h
```

If it's a single-arg macro, the call site in §7.2 becomes
`PROVIDER_DRIVER(verbs_provider_onic);` (drop the first "onic" literal).

### 11.3 ABI suffix drift

Today: `-rdmav57`. Next OFED / DOCA-HOST upgrade: likely `-rdmav58`.
The filename, the Makefile, and the `verbs_register_driver_<N>()` call
are all version-locked. When the base package bumps:

1. `ls /usr/lib/x86_64-linux-gnu/libibverbs/` to read the new N.
2. Update `ABI_VER` in Makefile, rebuild, reinstall.
3. Run Phase 2 of test plan.

Track against the installed `libibverbs1` package version in CI.

### 11.4 Kernel `uverbs_abi_ver = 1` vs userspace match

B3 kernel sets `uverbs_abi_ver = 1`. Our `match_min_abi_version` and
`match_max_abi_version` must bracket 1. §7.2 has both set to 1 — if B5
bumps the kernel's ABI to 2 (e.g., to carry provider-private context
cookies), this provider's match will silently *fail* with no error
message. Grep for `match_min_abi_version` in a passing `strace` run
during Phase 2 to catch this early.

### 11.5 `ibv_cmd_query_device_any` name

rdma-core older than v49 used `ibv_cmd_query_device_ex`. Newer uses
`ibv_cmd_query_device_any`. v57 should have the new name — verify:

```sh
grep -n 'ibv_cmd_query_device' /opt/src/rdma-core/libibverbs/*.h
```

If only the old name exists, use that instead.

### 11.6 PCI VID:DID in match table (VERIFY)

Host shows `1e52:401e` (Tenstorrent-looking). Brief says `10ee`
(Xilinx). We include both. Once B3 is actually loaded in this host and
`ls /sys/class/infiniband/onic_0100/device/modalias` produces a real
string, pin the match table to that VID:DID exactly and drop the
guesses. Modalias parsing in rdma-core is strict — a bogus entry is
ignored, not fatal.

### 11.7 RDMA-CM and librdmacm not covered

`ibv_rc_pingpong` uses raw verbs; `rping` (librdmacm) goes through
an RDMA-CM path that hits `create_id` → netlink → kernel CMA module →
provider. CMA works regardless of our provider because it operates on
the netdev layer for RoCE; but CM message exchange won't succeed until
B5 gives us real QPs. Not a B3.5 blocker.

### 11.8 `driver_id = RDMA_DRIVER_UNKNOWN` binding

Kernel has `uverbs_no_driver_id_binding = 1`. That's the *only* way a
provider with `driver_id = RDMA_DRIVER_UNKNOWN` can bind cleanly; if
the user ever sets that to 0 in the kernel driver, rdma-core will
refuse to open a context. Keep the two sides in sync.

### 11.9 Teardown race when `onic.ko` unloads while a ctx is open

If userspace holds a `struct ibv_context` and the kernel driver is
rmmod'd, libibverbs sees `/dev/infiniband/uverbs1` disappear and the
next verb call returns EIO. Our stubs don't know the difference
between EIO-from-kernel and our own EOPNOTSUPP, but since we don't
cache any kernel state in the userspace side, there's no leak. Worth
testing in Phase 5: `rmmod onic` while `/tmp/pd_test` is mid-loop
should yield a clean crash of the test process only.

---

## 12. Summary for human review

- **Critical open item:** §11.1 — `driver.h` not shipped. User must
  decide on route A/B/C before this gets implemented. Recommended: B.
- **ABI correction:** the brief said `-rdmav59` / MLNX_OFED 26.01, but
  the installed runtime is `-rdmav57` / DOCA-HOST 3.2.1 / rdma-core
  v57.x. All code in §7 uses 57.
- **Match table:** includes a guess for `1e52:401e` (what lspci shows
  right now on this host) plus Xilinx `10ee:*` candidates plus a
  name-prefix fallback. Tighten once B3 is loaded and modalias is
  readable.
- **Real verbs:** 4 (`query_device_ex`, `query_port`, `alloc_pd`,
  `dealloc_pd`). **Stubs:** everything else (≈20 ops). Every stub sets
  `errno = EOPNOTSUPP` and returns NULL / -1.
- **Total footprint:** ~450 LoC across 4 files in a new directory
  `/home/alex/mpi-shfs/fpga/libonic-provider/`. No edits to
  `open-nic-driver/`.
