# Chapter 10 — Roadmap: From Working Link to Full NIC

This build is a **correct but bare L2 Ethernet NIC**. This chapter is the gap analysis
between what exists today and a production-grade NIC, organized by tier, with the
**FPGA-vs-driver split** and a **rough effort** estimate for each item so it can be
planned and prioritized.

> Effort key: **S** = days (driver-only, well-scoped) · **M** = 1–2 weeks · **L** =
> multi-week (new RTL + verification) · **XL** = major subsystem.

## 10.1 What exists today ✅

Two independent 100G netdevs from one PF, bidirectional lossless L2, jumbo frames
(`MAX_PKT_LEN=9600`), PTP hardware timestamping, RS-FEC, MSI-X per-queue IRQs + NAPI,
link/carrier state, `ndo_set_mac_address`, `ndo_change_mtu`, RSS **hash** plumbing
(ethtool `-x/-X`), and XDP.

**Advertised offloads:** `netdev->features = NETIF_F_HIGHDMA` only. No checksum, no
segmentation, no scatter-gather, no VLAN offload, no `ndo_set_rx_mode`. That is the
starting point for everything below.

## 10.2 Tier 1 — Table stakes

Features a NIC is simply expected to have. These close the gap between "passes traffic"
and "behaves like a NIC."

| # | Feature | Side | Effort | Notes |
|---|---------|------|--------|-------|
| 1.1 | **RX MAC filtering** (`ndo_set_rx_mode`: promisc / allmulti / unicast + multicast lists) | **FPGA** (classifier was *stripped* — Ch. 4 §4.1) + driver hook | L | Today the datapath is effectively promiscuous; the host sees and drops frames it should never receive. A real NIC filters in HW by destination MAC. Either re-introduce a MAC-filter block ahead of the RX FIFOs, or accept promiscuous + document it. |
| 1.2 | **TX/RX checksum offload** (`NETIF_F_IP_CSUM`, `IPV6_CSUM`, `RXCSUM`) | **FPGA** (compute/verify L3/L4 csum in the datapath) + driver flags + `CHECKSUM_UNNECESSARY`/`CHECKSUM_PARTIAL` | L | Single biggest CPU win. Requires an L3/L4 parse + checksum unit on TX (322 MHz box or packet_adapter) and a verify + result sideband on RX. |
| 1.3 | **Scatter-gather TX** (`NETIF_F_SG`) | **Driver** (QDMA already gathers) | S | Cheapest big win: stop linearizing skbs. QDMA descriptors already support multi-segment gather; advertise `NETIF_F_SG` and build multi-fragment descriptors in `onic_xmit_frame`. |
| 1.4 | **ethtool ring & coalesce control** (`get/set_ringparam`, `get/set_coalesce`) | Driver | S | Ops are currently absent (Ch. 5 §5.1 ethtool list). `-C` is the important half — it maps onto the C2H `cnt_th`/`tmr_cnt` pools that gave the 2.7x RX gain in §2.4. `-G` matters much less: ring depth was measured *not* to be the constraint (8x deeper rings moved single-queue drops <1%). |
| 1.5 | **Pause / flow control** (`get/set_pauseparam`) | Driver (CSRs) **+ FPGA** (pause generation) | S + M | **Now known to be the root cause of the C2H drop gap** — see Ch. 13. Without it the only response to receive overload is discarding: unpaced UDP drops 1.2-3.6 % where a ConnectX-7 with pause enabled drops ~0 (Ch. 8 §8.8.2). `ctl_tx_pause_req` exists in the CMAC wrapper but is never driven, and every RX-path FIFO fill output is unconnected. Driver CSR work is S; driving pause from FIFO fill is M and needs a gateware cycle. |
| 1.6 | **Complete, correct statistics** (per-queue + HW counters through `get_stats64` / `-S`) | Driver + read CMAC/adapter counters | S–M | **Raised in priority:** C2H `DESC_RSP_DROP` (BAR0 `0xB10`) is currently invisible — netdev `rx_dropped` reads 0 while packets are discarded (Ch. 8 §8.8.2). A ConnectX-7 reports the same class of drop in `rx_dropped` exactly. Also surface the CMAC FCS/error and `CMAC_ADPT` drop counters (`+0x3000`, Ch. 9 §9.5) and the plugin diag counters (Ch. 4 §4.5). |
| 1.7 | **`ndo_tx_timeout`** watchdog + `ndo_features_check` / `ndo_set_features` | Driver | S | Required once offloads exist; today there is no TX-timeout handler. |

## 10.3 Tier 2 — Performance (approach line rate on multi-core)

| # | Feature | Side | Effort | Notes |
|---|---------|------|--------|-------|
| 2.1 | **Per-port RSS coexisting with qid-steering** | **FPGA** + driver | L | *The important one.* `EXT_QID=1` currently **disables** the Toeplitz RSS to reuse the qid as the CMAC selector (Ch. 3 §3.2). So each port lands on a fixed queue block and cannot spread flows across CPU cores. The fix: keep **CMAC-select in the high qid bits** (`qid[6+]`) and add a **hash across the low `QID_LO_W` bits** so steering *and* RSS coexist — i.e. `qid = {cmac_sel, rss_hash[5:0]}`. Requires reviving the RSS hash in the plugin RX tag path and per-port indirection tables in the driver. |
| 2.2 | **TSO** (`NETIF_F_TSO`) | **FPGA** (HW segmentation) | L | GSO in software is free-ish (`NETIF_F_GSO`), but true TSO needs a segmentation engine. |
| 2.3 | **GRO / LRO** | Driver (GRO) / FPGA (LRO) | S (GRO) | GRO is driver-side and cheap; enable in `onic_rx_poll`. |
| 2.4 | **Interrupt moderation / adaptive coalescing**, **XPS**, **aRFS** | Driver | M | **Highest-value item measured so far.** The C2H completion thresholds were hardcoded to pool index 0 (cnt_th=2 packets, tmr_cnt=1); selecting cnt_th=64/tmr=25 took single-port RX from **36.8 to 98.5 Gbit/s** and dual-port aggregate to **104.5 Gbit/s** (driver commit `f33fed9`, now exposed as `cmpl_cnt_idx`/`cmpl_tmr_idx` module params). Remaining work: pick a shipped default, expose via `ethtool -C` (with 1.4), and make it adaptive. |
| 2.5 | ~~**Reproducible timing closure**~~ ✅ | Build flow | ~~M~~ done | **Resolved 2026-07-29.** `_do_impl` now takes `-impl_strategies` (a list → concurrent `impl_1..N` off one synthesis) plus `-max_threads`/`-ultrathreads`. `Performance_ExplorePostRoutePhysOpt` closes clean deterministically at WNS +0.008 ns; `-post_impl` picks the best-WNS run for `write_cfgmem`. See Ch. 6 §6.6 for the strategy sweep data. |

## 10.4 Tier 3 — Robustness / production hardening

| # | Feature | Side | Effort | Notes |
|---|---------|------|--------|-------|
| 3.1 | **PCIe FLR + AER handling**, clean reset paths | FPGA + driver | M | Function-level reset and PCIe error recovery. |
| 3.2 | **Link-flap recovery** (partial today) + robust re-alignment | Driver | S–M | A link-recovery/watchdog workqueue already exists (Ch. 5 §5.1); harden and test it against real flaps. |
| 3.3 | **Datapath ECC** on the FIFOs + expose correctable/uncorrectable counts | FPGA | M | The QDMA C2H path already has a 7-bit ECC (Ch. 3 §3.1); extend coverage and surface counts. |
| 3.4 | **Remove dead OFED link dependency** | Driver | S | The module still compiles the RDMA `.c` files, so it links OFED `ib_*` symbols (Ch. 5 §5.6). Drop them from the Makefile wildcard to remove the MLNX_OFED build/load requirement. |
| 3.5 | **Remove dead `port_id` RTL** | FPGA | S | `h2c_qid_corrected` / `s_axis_h2c_tuser_port_id` are inert (Ch. 3 §3.6); delete for clarity. |

## 10.5 Tier 4 — Deployment / lifecycle

| # | Feature | Side | Effort | Notes |
|---|---------|------|--------|-------|
| 4.1 | **Boot-persistent driver load** (`modules-load.d` + `depmod`/`modprobe install`) | Host | S | So the NIC comes up on reboot without a manual `insmod`. |
| 4.2 | **Persistent host networking** (NM/netplan profiles pinning static IPs + `managed no`) | Host | S | Defeats the NetworkManager IP-strip gotcha permanently (Ch. 7 §7.9, Ch. 8 §8.5-A). |
| 4.3 | **PHC exposed as `/dev/ptpN`** + `ptp4l`/`phc2sys` integration | Driver | M | `ts_info` is already implemented; expose a PTP hardware clock device and wire the servo. |
| 4.4 | **Versioned bitstream/firmware update flow** | Tooling | S–M | `program_fpga.sh` exists (Ch. 6 §6.8); add versioning + a golden/fallback image story. |

## 10.6 Tier 5 — SmartNIC-tier (only past "plain NIC")

The natural extension of the 1-PF/multi-port design (Ch. 2 §2.1), but each item is a
large, separate effort:

| # | Feature | Side | Effort |
|---|---------|------|--------|
| 5.1 | On-chip **L2 switching / MAC learning** between the two ports | FPGA | XL |
| 5.2 | **SR-IOV / VFs** | FPGA + driver | XL |
| 5.3 | **switchdev + port representors** (Linux eswitch model) | Driver | XL |
| 5.4 | **TC / flow offload** (`ndo_setup_tc`, flower) | FPGA + driver | XL |

## 10.7 Recommended order

The three highest-leverage next steps, in order:

1. **TX/RX checksum offload** (§1.2) — biggest CPU win; needs RTL.
2. **Per-port RSS coexisting with qid-steering** (§2.1) — unlocks multi-core line rate.
3. **`ndo_set_rx_mode` MAC filtering** (§1.1) — correctness; stop being promiscuous.

Quick wins to bank alongside them (all **S**, driver-only): scatter-gather (§1.3),
ring/coalesce ethtool ops (§1.4), pause frames (§1.5), GRO (§2.3), and dropping the OFED
dependency (§3.4).

**Done since this chapter was written:** §2.1 per-port RSS (Ch. 11, hardware-verified
2026-07-03) and §2.5 reproducible timing closure (Ch. 6 §6.6, 2026-07-29).

Everything here is incremental on top of a datapath that already moves packets losslessly
at the peer's line rate — none of it is a prerequisite for the NIC to *function*, only to
be *complete*.
