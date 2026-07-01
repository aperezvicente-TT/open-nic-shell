# Chapter 5 — The Linux Driver (`onic`, multi-netdev)

The driver lives in a separate repo, `../open-nic-driver`, branch
`feature/eth-dual-netdev-1pf` (module version `0.21`). Its defining custom feature is
**one QDMA PF → N netdevs**, port-representor style, on a partitioned queue range. This
chapter covers its structure, the queue-mapping contract that binds it to the gateware,
and the two behaviours that most often trip people up (TX steering, and the `num_cmacs`
fix).

## 5.1 Source-file inventory

| File | Role |
|------|------|
| `onic_main.c` | PCI driver: `id_table`, `onic_probe`/`onic_remove`, `onic_setup_primary`/`_secondary`, `onic_alloc_netdev`, MAC assignment, `net_device_ops`, module init |
| `onic.h` | `struct onic_private` (per-netdev context), constants `ONIC_MAX_QUEUES`, `ONIC_PER_CMAC_QUEUES`, and the dual-netdev fields (`peer`, `secondaries[]`, `cmac_id`, `qid_base`, `vec_base`) |
| `onic_hardware.c/.h` | QDMA/CMAC HW layer: `onic_init_hardware`, CMAC detect, per-queue QDMA context, doorbells, `onic_enable_cmac`. `ONIC_MAX_CMACS`, `CMAC` register offsets |
| `onic_lib.c` | MSI-X/IRQ + capacity: `onic_acquire_msix_vectors`, `onic_init_capacity[_slave]`, queue IRQ handlers, link-recovery workqueues |
| `onic_netdev.c` | Datapath: open/stop, TX `onic_xmit_frame`, RX `onic_rx_poll`, queue alloc, XDP |
| `onic_register.h` | Shell BAR register map (offsets/macros), `onic_read_reg`/`onic_write_reg` |
| `onic_ethtool.c`, `onic_sysfs.c`, `onic_debugfs.c`, `onic_common.c`, `onic_ptp.c` | ethtool/sysfs/debugfs ops, helpers, PTP timestamping (PTP still active) |
| `libqdma/` | Vendored AMD libqdma — owns the PCI BARs + global CSR programming |
| `qdma_legacy/` | Older QDMA wrapper — programs per-queue contexts (`qdma_write_sw_ctxt`, fmap) |

> libqdma and qdma_legacy coexist by design: **libqdma owns BARs/CSRs; qdma_legacy
> programs per-queue contexts.**

## 5.2 One PF → N netdevs (the representor-style model)

A single PCI probe creates N netdevs, one per CMAC, all sharing one QDMA PF.

- `onic_alloc_netdev(pdev, cmac_id)` (`onic_main.c:226`) does the common work:
  `alloc_etherdev_mq(...)`, sets `netdev->dev_port = cmac_id`, names the interface, and
  derives a **per-CMAC MAC** whose last octet is `(PCI_FUNC << 4) | cmac_id` (so each
  CMAC gets a distinct address; CMAC0 keeps the legacy MAC). Stores `priv->cmac_id`.
- **Primary** — `onic_setup_primary` (`onic_main.c:380`): `cmac_id = 0`, sets
  `ONIC_FLAG_MASTER_PF`, `vec_base = 0`, `qid_base = 0`. It alone calls `qdma_device_open`
  (claims BARs), `onic_init_hardware`, `onic_init_interrupt` (user + error + queue IRQs),
  then `register_netdev`.
- **Secondary** — `onic_setup_secondary(primary, cmac_id, out)` (`onic_main.c:532`):
  shares the primary's BAR2 map + QDMA device via a **child qdev**; takes only queue IRQs.
  Key bindings:
  - `priv->qid_base = cmac_id * ONIC_PER_CMAC_QUEUES` — the queue base for this CMAC.
  - `priv->vec_base = ...` — its slice of the MSI-X vectors.
  - `priv->peer = primary` — back-pointer to the MSI-X/QDMA owner.
- **Spawn loop** — `onic_probe` (`onic_main.c:730`): `for (i = 1; i < hw.num_cmacs && i <
  ONIC_MAX_CMACS; i++)` sets up each secondary; per-CMAC failure is **non-fatal**. The
  primary keeps `secondaries[ONIC_MAX_CMACS]` (slot 0 unused) and `num_secondaries`.
- **Teardown** — `onic_remove`: secondaries first (highest index down), primary last
  (it owns the QDMA reset + BAR unmap). `ONIC_MAX_CMACS = 8`.

Result on this build: **exactly two netdevs** from one PF — CMAC0 (`dev_port 0`) and
CMAC1 (`dev_port 1`).

## 5.3 The queue-mapping invariant and how steering actually works

> **Invariant (must match the gateware's `PER_CMAC_QUEUES`):**
> `ONIC_PER_CMAC_QUEUES = 64` (`onic.h:83`). CMAC *c* owns absolute qids `[c·64, (c+1)·64)`,
> established by `qid_base = cmac_id · 64`. Guarded by
> `BUILD_BUG_ON(ONIC_PER_CMAC_QUEUES > ONIC_MAX_QUEUES)`.

**Relative ↔ absolute.** Each netdev uses *relative* qids `0..num_queues-1`. The child
qdev for a secondary carries `q_base = qid_base`, and every QDMA doorbell/DMAP register
is indexed by the **absolute** id `q_base + qid`. So relative qid 0 on CMAC1's netdev
drives **absolute qid 64**.

**TX → which CMAC.** This is the subtle part, and the code comments here are **stale** —
read carefully:

- The driver sets the QDMA H2C software-context field
  `sw_ctxt.port_id = q_base / ONIC_PER_CMAC_QUEUES` (= `cmac_id`) (`onic_hardware.c:497`),
  and a comment claims the shell arbiter steers on that `port_id`.
- **That is not the live mechanism.** In the gateway, the `port_id`-based steering
  ("Option B") was **reverted to dead code** (Ch. 3 §3.6). The plugin actually demuxes on
  **`qid[6]`** of the H2C `tuser_qid` (Ch. 4 §4.2).
- It still works because the two encodings coincide: since CMAC1's queues live at
  absolute qid ≥ 64, their **`qid[6]` is 1** — which is the CMAC index. QDMA emits that
  absolute qid on `m_axis_h2c_tuser_qid` when it DMAs from the queue, and the plugin
  demuxes it. The `port_id` the driver sets happens to equal the same index, so it is
  harmless but vestigial.

> **Practical takeaway:** the thing that must be correct for TX steering is
> **`qid_base = cmac_id · 64`** (so the absolute qid's bit 6 encodes the CMAC). There is
> **no per-descriptor `tuser_qid`** written by this driver (grep finds none); the qid
> comes from *which queue* the doorbell rings. The 32-bit TX descriptor `metadata` carries
> packet length in `[15:0]` and PTP tag in `[31:16]` — **not** a qid (`onic_netdev.c:1195`).

**RX → which netdev.** Structural: the shell tags each frame with `qid = cmac·64`
(Ch. 4 §4.4) and `EXT_QID=1` writes the completion into that absolute queue's C2H ring.
The driver set that queue's context up under the child qdev bound to that CMAC's netdev,
so each `onic_rx_queue` already has `q->netdev = <the right dev>`; `onic_rx_poll` builds
the skb and calls `eth_type_trans(skb, q->netdev)`.

## 5.4 The `num_cmacs` detection bug and its fix

**Detection** (`onic_hardware.c:220`): the driver reads `CMAC_OFFSET_CORE_VERSION(i)` for
`i` in `[0, ONIC_MAX_CMACS)` and breaks at the first offset whose value ≠
`ONIC_CMAC_CORE_VERSION` (`0x00000301`); `num_cmacs = i`.

**The bug** (fixed in commit `274de0c`): the CMAC base-offset macro was

```c
#define CMAC_SUBSYSTEM_OFFSET(i)  (((i)==0) ? 0x8000 : 0xC000)   // BUGGY
```

which **aliased every `i ≥ 1` to CMAC1's window `0xC000`**. The detection loop kept
re-reading CMAC1's valid version and never broke → `num_cmacs` was mis-detected as the
full **8**, producing 6 spurious CMAC2–7 secondary-setup failures (non-fatal, but noisy,
and it sized the fmap wrong).

**The fix** (`onic_register.h:71`) uses the real `0x4000` stride:

```c
#define CMAC_SUBSYSTEM_OFFSET(i) \
    (CMAC_SUBSYSTEM_0_OFFSET + (i) * (CMAC_SUBSYSTEM_1_OFFSET - CMAC_SUBSYSTEM_0_OFFSET))
// CMAC_SUBSYSTEM_0_OFFSET = 0x8000, CMAC_SUBSYSTEM_1_OFFSET = 0xC000  ->  0x8000 + i*0x4000
```

Now an absent CMAC reads an unpopulated offset → version mismatch → the loop breaks at
the true count (**2**). This matches the shell's BAR map (Ch. 2 §2.7).

## 5.5 Register map (driver's view of the shell)

Accessors: `onic_read_reg`/`onic_write_reg` = `ioread32`/`iowrite32(hw->addr + offset)`;
`hw->addr` = libqdma's BAR2 map + `SHELL_START (0x0)`. Shell window is 16 MB
(`SHELL_END = 0x1000000`).

| Subsystem | Base | Notes |
|-----------|------|-------|
| System config (`SYSCFG_OFFSET`) | `0x0000` | build/reset/status registers |
| QDMA subsystem | `0x1000` | per-func `QDMA_FUNC_OFFSET(i) = 0x1000 + 0x1000·i`; `QCONF(i)` = qbase/numq |
| QDMA subsys ctrl | `0x5000` | |
| **CMAC0** | `0x8000` | |
| **CMAC1** | `0xC000` | stride `0x4000` (§5.4) |

System-config CSRs (offset from `0x0`): `BUILD_STATUS +0x0`, `SYSTEM_RESET +0x4`,
`SYSTEM_STATUS +0x8`, `SHELL_RESET +0xC`, `SHELL_STATUS +0x10`, `USER_RESET +0x14`,
`USER_STATUS +0x18`, `LINK_IRQ_STATUS +0x1C`. `SHELL_RESET` bit0 = QDMA reset, bit4 =
CMAC0, bit8 = CMAC1.

Per-CMAC registers of note (relative to `CMAC(i)`): `RESET +0x0004`, `CORE_VERSION
+0x0024`, `STAT_RX_STATUS +0x0204` (bit0 = RX aligned), `RSFEC_CONF_ENABLE +0x107C`. The
`CMAC_ADPT` block (`+0x3000`) holds TX/RX packet recv/drop/error counters at
`+0x0/0x10/0x20/0x30/0x40` — useful in Ch. 8.

## 5.6 RDMA strip status

All RDMA/ERNIC **call sites** were stripped (commit `dda0ea7`): no `ib_register_device`,
`onic_ib_*`, ERNIC-IRQ, or sysdma init in the Ethernet path. However:

- The RDMA **source files still exist and are still compiled** by the Makefile wildcard
  (`onic_ib.c`, `onic_ernic_irq.c`, `onic_sysdma.c`, `onic_ddr_alloc.c`). Because
  `onic_ib.c` compiles, the module **still links against OFED `ib_*` symbols** — which is
  why the build and load still require MLNX_OFED / `ib_core` (see §5.7). This is
  dead-but-linked; the Ethernet flow never calls into it.
- `onic_shell_reset_ernic()` still pulses `SHELL_RESET` bits 12/13; harmless/no-op on a
  non-RDMA shell, gated by module param `shell_reset_on_load`.

> **Cleanup opportunity (non-blocking):** dropping the RDMA `.c` files from the Makefile
> wildcard would remove the OFED build dependency entirely. Left as-is to minimize churn.

## 5.7 Building and loading

**Build** (`Makefile`): out-of-tree module; `onic-objs` is a wildcard over `.`,
`qdma_legacy`, `hwmon`, `libqdma`, `libqdma/qdma_access/*`. If
`/usr/src/ofa_kernel/x86_64/$(KERNEL_VERS)/Module.symvers` exists it is added as
`KBUILD_EXTRA_SYMBOLS` and OFED includes are prepended (needed only because
`onic_ib.c` compiles — §5.6). `make -j` → `onic.ko`.

**Load** (see also Ch. 7 §7.3):
```bash
sudo modprobe ib_core           # onic links OFED symbols
sudo rmmod onic 2>/dev/null
sudo insmod /home/alex/mpi-shfs/fpga/open-nic-driver/onic.ko
```
> `insmod` **must use the absolute path** to match the NOPASSWD sudoers rule.

`load_and_verify.sh` automates this and **asserts exactly 2 netdevs on one PF** — the
1-PF/2-CMAC contract. Module params: `RS_FEC_ENABLED` (default 1), `debug_level`,
`host_id` (MAC uniqueness), `shell_reset_on_load`.

**Privileges:** root is required for `modprobe`/`insmod`/`rmmod`, `dmesg`, and BAR2 mmap.
On the bench this is scoped via `/etc/sudoers.d/onic-test` (installed by
`tools/install_onic_sudoers.sh`), limited to the exact `onic.ko` path and a fixed set of
`ip`/`dmesg`/`tcpdump`/`ernic-baremetal`/`tee` operations.

Continue to [Chapter 6 — Build & Flash Guide](06-build-and-flash.md).
