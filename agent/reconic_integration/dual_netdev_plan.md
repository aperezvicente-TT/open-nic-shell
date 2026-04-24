# Dual-CMAC Single-PF RDMA Architecture — Plan

Written 2026-04-22.  Supersedes the PF/function-count confusion in earlier
sessions (v2 build script briefly regressed with `-num_phys_func 1`;
Path A/B driver debate).  This is the committed architecture.

## End goal

One FPGA NIC that is simultaneously a normal multi-port Ethernet netdev
**and** an ibverbs RoCEv2 RDMA device.  Scalable to N CMAC ports.

## Architecture

```
  Host: onic.ko (single kernel module)
    ├─ netdev0 (enp1s0)     — CMAC0 normal ethernet
    ├─ netdev1 (enp1s0d1)   — CMAC1 normal ethernet
    └─ ib_device            — RDMA, N ports (one per CMAC)
                │
                │ PCIe PF0 only (mlx5-style dual-personality)
                ▼
  FPGA shell:
    CMAC0 ─► classifier ┬─RoCE─► ERNIC0 ─► DDR4 ─► host DMA
                        └─other─► plugin arbiter ┐
    CMAC1 ─► classifier ┬─RoCE─► ERNIC1 ─► DDR4 ─► host DMA
                        └─other─► plugin arbiter ┤
                                                 ▼
                              QDMA function slot 0
                              CMAC0 → queues [0, N)
                              CMAC1 → queues [N, 2N)
```

## Key architectural decisions

| Decision | Value | Rationale |
|---|---|---|
| PCIe PFs | **1** (`tl_pf_enable_reg=1`) | Matches shipping RoCE NICs (mlx5, bnxt_re).  One driver, one `ib_device`, one MSI-X pool. |
| Shell function slots | **1** (`-num_phys_func 1`) | Plugin-side CMAC arbitration scales past the QDMA IP's function-context limit.  More CMACs don't require more shell slots. |
| CMAC→queue mapping | **Plugin RTL** (not shell function slots) | Portable, scalable, avoids undocumented QDMA-IP-with-hidden-PF behavior. |
| RDMA datapath | **ERNIC sideband** (not QDMA queues) | ERNIC has its own DMA to DDR4 / host.  RDMA queue carve-out is not needed — orthogonal from the non-RoCE queue partition. |
| Driver structure | **One probe, N netdevs + one ib_device** | `onic_alloc_netdev()` helper + `peer` link already in place; generalizes to `secondaries[]`. |

## Decision log (why earlier approaches were wrong)

**"2 PFs per CMAC" (original OpenNIC design) — abandoned.**
Doesn't scale past 4 ports (PCIe PF limit without ARI; QDMA IP 4-function
ceiling).  `ib_device` ownership across multiple PFs is awkward.
Historical baseline; fine for 2 CMACs but a dead-end for growth.

**"1 PF, N shell function slots" (v3 first draft, `-num_phys_func 2`) — abandoned.**
Bets on QDMA IP honoring function N's contexts when PF N is PCIe-disabled
via `tl_pf_enable_reg`.  Undocumented behavior; even if it works at 2, it
hits the IP's function-context ceiling at 4.  Also added driver complexity
(per-slot QCONF/INDIR_TABLE writes, child qdev with distinct func_id).

**"1 PF, 1 shell slot, plugin arbiter" (this plan).**
CMAC identity is encoded into queue ID in the plugin RTL before packets
reach the QDMA subsystem.  One function, one fmap, queue namespace
partitioned at the plugin.  QDMA IP sees exactly what its designers
expected: one PF, one function, queues [0, 2N).  Scales linearly with
CMAC count and queue budget only.

## Config summary

| Layer | File | Setting | Value |
|---|---|---|---|
| QDMA IP | `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` | `en_bridge_slv` | `true` |
| QDMA IP | same | `tl_pf_enable_reg` | `1` (PF0 only) |
| Shell build | `script/build_2cmac_rdma_v3.sh` | `-num_phys_func` | `1` |
| Shell build | same | `-num_cmac_port` | `2` |
| Shell build | same | `-rdma` | `1` |
| Plugin RTL | `plugin/rdma_onic/rdma_onic_250mhz.sv` | CMAC0+1 non-RoCE arbiter | **NEW — to write** |
| Plugin RTL | same | CMAC-encoded qid tagging | **NEW — to write** |
| Driver | `onic.ko` | Dual netdev from one probe | Done |
| Driver | `onic.ko` | Child qdma_dev for secondary | Done (func_id shared; q_base offset) |
| Driver | `onic.ko` | Secondary QCONF(1)/INDIR_TABLE(1) writes | **Remove** (one slot only) |
| Driver | `onic.ko` | `ib_device` registration | **NEW — to write** |

## Execution plan

1. Revert `-num_phys_func` in v3 script: 2 → 1 (was 2 in draft, now 1).
2. Simplify `onic_init_hardware_slave` — drop QCONF(cmac_id) / INDIR_TABLE(cmac_id) writes; primary's QCONF(0) covers the full [0, 2N) range.
3. Design plugin arbiter (read `rdma_onic_250mhz.sv`; identify how qid is set on C2H stream; pick tuser.qid or hash-offset path).
4. Implement plugin arbiter: `m_axis_qdma_c2h_*[0]` gets CMAC0 packets with qid∈[0, N) and CMAC1 packets with qid∈[N, 2N).  `m_axis_qdma_c2h_*[1]` (and higher) unused — can be tied off.
5. Rebuild shell bitstream (4–8 hrs Vivado).
6. Bench test: two netdevs RX independently; ping both peers; RX counters move on the correct netdev.
7. Add `ib_device` skeleton: one device, two ports, stub verbs returning `-EOPNOTSUPP`.  Verify `rdma link show` enumerates.
8. Fill in verbs against ERNIC BAR2 one at a time (future sessions).

## What this is NOT

- **Not** about enabling s_axib bridge slave for host-memory RDMA buffers — that's the separate Tier 1b track (`tier1b_qdma_audit.md`).  Orthogonal concern.
- **Not** a change to ERNIC wiring or classifier — RoCE traffic still goes sideband to ERNIC.  Only the non-RoCE RX path (CMAC → QDMA) changes.
- **Not** RSS-aware for CMAC1 yet.  Queue selection within each CMAC's range is post-MVP.

## File inventory touched by this plan

| File | Status |
|---|---|
| `script/build_2cmac_rdma_v3.sh` | Edited (num_phys_func 1) |
| `src/qdma_subsystem/vivado_ip/qdma_no_sriov_au200.tcl` | `tl_pf_enable_reg=1` |
| `src/qdma_subsystem/vivado_ip/qdma_subsystem_clk_converter.tcl` | TUSER_WIDTH 16→27 (carries qid) |
| `src/qdma_subsystem/qdma_subsystem_function.sv` | EXT_QID + c2h slice widened 96→107 bits; h2c slice widened 16→27 bits; m_axis_h2c_tuser_qid output added |
| `src/qdma_subsystem/qdma_subsystem.sv` | EXT_QID param + tuser_qid ports on both H2C and C2H |
| `src/open_nic_shell.sv` | axis_qdma_{c2h,h2c}_tuser_qid wires; `EXT_QID=1` under __rdma_enabled__ |
| `src/box_250mhz/box_250mhz.sv` | New h2c and c2h tuser_qid ports |
| `plugin/rdma_onic/box_250mhz/user_plugin_250mhz_inst.vh` | New port connections |
| `plugin/rdma_onic/rdma_onic_250mhz.sv` | **Major RTL work**: RX arbiter, TX demux+arbiter, ERNIC user2rdma_from_qdma_tx tied off |
| `plugin/rdma_onic/packet_classification/packet_filter.sv` | Fixed AXIS violation (tvalid no longer depends on tready) |
| `onic-driver/onic.h` | ONIC_PER_CMAC_QUEUES=64 |
| `onic-driver/onic_hardware.c` | fmap qmax = num_cmacs * 64; reset-only CMAC at probe |
| `onic-driver/onic_main.c` | Dual-netdev probe; qid_base=64 for secondary; BUILD_BUG_ON guard |
| `onic-driver/onic_lib.{h,c}` | onic_init_capacity_slave helper |
| `onic-driver/onic_ethtool.c` | priv->cmac_id (4 sites) |
| `onic-driver/qdma_access/qdma_device.{c,h}` | qdma_create_child_dev |
| `onic-driver/onic_ib.c` | **New file** — future ib_device skeleton |

## Path γ TX-side datapath (NEW — final solution)

```
  Host netdev TX ──► QDMA descriptor ──► QDMA H2C stream
                                              │
                                              ▼
                              plugin TX demux (by tuser.qid)
                                │                       │
               qid < 64 (CMAC0) │                       │ qid ≥ 64 (CMAC1)
                                ▼                       ▼
                      per-CMAC0 TX arbiter    per-CMAC1 TX arbiter
                          │      ▲                  │      ▲
                          │      │                  │      │
        ERNIC0 TX ────────┘      │    ERNIC1 TX ────┘      │
        (rdma2user_to_cmac_tx)   │    (rdma2user1_to_cmac_tx)
                                 │                         │
                                 ▼                         ▼
                         CMAC0 TX AXIS              CMAC1 TX AXIS
```

ERNIC's `user2rdma_from_qdma_tx_*` input is **tied off** — ERNIC reads
WQEs from host memory via its own AXI master (configured by SQBA/RQBA
CSRs through BAR2).  QDMA H2C is reserved entirely for normal netdev TX.
