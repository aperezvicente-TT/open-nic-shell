# Chapter 1 — Introduction & Overview

## 1.1 What this project is

This is a **pure-Ethernet SmartNIC** built on the AMD/Xilinx **OpenNIC shell**, targeting
the **Alveo U200** accelerator card. Its distinguishing feature is the datapath topology:

> **One QDMA PCIe physical function (PF) drives two independent 100 GbE ports**,
> and each port appears to Linux as its own, fully independent network interface.

Concretely, after you load the driver you get two netdevs — e.g. `enp1s0` and
`enp1s0d1` — that behave like two separate 100G NICs, but they are served by a
**single** PCIe endpoint / single QDMA function. There is **no RDMA, no ERNIC, no
packet classifier, and no flow filter** in the datapath: it is a clean L2 Ethernet
NIC with PTP timestamping retained.

```
                         ┌──────────────────────── Alveo U200 (xcu200) ───────────────────────┐
                         │                                                                      │
   Host (x86)            │   ┌────────────┐      ┌───────────────────────┐      ┌───────────┐  │
  ┌───────────┐  PCIe    │   │            │ H2C  │  eth_2cmac_1pf plugin  │      │  CMAC0    │  │  QSFP0
  │  onic.ko  │ ═══════► │   │   QDMA     │═════►│  (box_250mhz)          │═════►│ 100 GbE   │══╪══► .221
  │           │  Gen3    │   │ subsystem  │      │                        │      └───────────┘  │
  │ 2 netdevs │ ◄═══════ │   │  (1 PF)    │◄═════│  TX qid-demux ─┐       │      ┌───────────┐  │  QSFP1
  └───────────┘          │   │            │ C2H  │  RX arbiter  ◄─┴─────  │◄═════│  CMAC1    │══╪══► .223
                         │   └────────────┘      └───────────────────────┘      │ 100 GbE   │  │
                         │                                                       └───────────┘  │
                         └──────────────────────────────────────────────────────────────────────┘
```

- **TX (H2C):** the driver tags every transmit descriptor with a **queue-ID**. The
  plugin decodes one bit of that qid to steer the packet to CMAC0 or CMAC1.
- **RX (C2H):** the plugin arbitrates the two CMAC receive streams into the single
  C2H stream and **tags** each packet with a qid that tells the driver (and QDMA)
  which netdev/queue it belongs to.

## 1.2 Why 1-PF/2-CMAC (and why it's non-trivial)

The **stock** OpenNIC `p2p` design hard-couples ports to PFs: it requires
`NUM_PHYS_FUNC == NUM_CMAC_PORT` — i.e. one PCIe function per 100G port. That is
simple but has drawbacks for our use case:

- It consumes a PCIe function (and its BAR/MSI-X/IRQ budget) per port. On an 8-CMAC
  part that is 8 functions.
- The two ports cannot share a single DMA context, single driver instance, single
  queue pool, or a future switching/representor layer.

Industry multi-port NICs instead put **one PCIe function** in front of an on-chip
switch and expose ports as **representors** (the Linux *switchdev*/*eswitch* model).
This project is a minimal step in that direction: **one function, multiple ports,
steered by queue-ID**. See Ch. 2 §2.1 for the design-space discussion.

The reason it takes real engineering (and not just a parameter flip) is that OpenNIC's
default datapath has **no notion of a per-packet destination port**. We had to add one:

1. Turn on the QDMA **`EXT_QID`** feature so a per-packet queue-ID is carried on the
   AXI-Stream sideband (`tuser`) in both directions (Ch. 3).
2. Widen and *byte-lock* the H2C/C2H `tuser` so the qid survives the clock-domain
   crossings and slice/FIFO IP without being mangled (Ch. 3).
3. Replace the `box_250mhz` user logic with a plugin that **demuxes** H2C by qid on TX
   and **merges + tags** the CMAC streams on RX (Ch. 4).
4. Generalize the `onic` driver so a single PF spawns **N netdevs**, one per CMAC, on a
   partitioned queue range (Ch. 5).

## 1.3 Goals and non-goals

**Goals**
- Two independent 100 GbE netdevs from one QDMA PF, lossless bidirectional traffic.
- Pure L2 Ethernet; retain PTP hardware timestamping.
- A design parameterized to *N* CMACs (the RTL is N-ready; the stock `build.tcl`
  caps `num_cmac_port` at 2 — >2 needs extra CMAC-instantiation work).
- Reproducible build + flash + bring-up.

**Non-goals (explicitly out of scope)**
- **No RDMA / ERNIC.** All ERNIC, DDR, classifier and filter logic is stripped.
- No on-chip L2 switching between the two ports (each port is an independent endpoint;
  there is no MAC-learning bridge in the FPGA).
- No hardware RSS across the two ports (each port maps to a fixed queue block).

## 1.4 The two repositories and branches

| Repo | Branch | HEAD (validated) | Role |
|------|--------|------------------|------|
| `open-nic-shell` | `feature/eth-1pf-2cmac-qid` | `1781c4f` | Gateware — shell, plugin, qid graft, timing fix |
| `open-nic-driver` | `feature/eth-dual-netdev-1pf` | `274de0c` | Linux driver — 1 PF → N netdevs |

Both are pushed to `github.com/aperezvicente-TT/open-nic-{shell,driver}`.

The gateware and driver share a **contract** that must never drift:

> **Queue-mapping invariant:** `PER_CMAC_QUEUES = 64`. CMAC *c* owns the absolute
> queue-ID range `[c·64, (c+1)·64)`. TX packets on those queues egress CMAC *c*;
> RX packets from CMAC *c* are tagged with qid `c·64`.

This one line is enforced in three places — the plugin (RTL), the QDMA `tuser` packing
(RTL), and the driver's queue allocation (C). If any one of them changes the `64`, all
three must change together.

## 1.5 Validated hardware result

On the reference bench (U200 + two remote Mellanox peers), with the timing-closed
bitstream flashed to SPI config flash:

- **Both ports concurrently:** 2000 ICMP packets each, **0 % loss on both**, RTT ≈ 0.13–0.20 ms.
- **CMAC0 (`enp1s0`) ↔ peer `.221`**, **CMAC1 (`enp1s0d1`) ↔ peer `.223`** (topology
  verified via per-CMAC RX diagnostic counters — see Ch. 8).
- Throughput ≈ 20–22 Gbps/port, which is the **remote peer's Gen3 ×4 PCIe slot**
  ceiling, not an FPGA/wire limit (CMAC FCS/error counters and netdev drops all zero).
  TCP retransmits observed under load are benign congestion at that PCIe ceiling (Ch. 8 §8.5).

## 1.6 A note on the debugging history (why the docs stress certain bugs)

Getting here surfaced three instructive bugs that these docs call out explicitly so
they are never re-introduced:

1. **The plugin demux clamp underflow** (Ch. 4 §4.3) — the real root cause of a
   "CMAC0 TX is dead" symptom. An out-of-range clamp compared against a *truncated*
   `NUM_INTF`, hardwiring the port-select to CMAC1 and ignoring the qid entirely.
2. **The driver `num_cmacs` stride bug** (Ch. 5 §5.4) — a CMAC base-offset macro that
   aliased every CMAC index ≥1 to the same address, mis-detecting 8 CMACs.
3. **The timing XDC empty-object-list error** (Ch. 6 §6.5) — `set_false_path` on PTP
   CDC flops that synthesis had optimized away, aborting the build.

See each chapter for the precise mechanism and fix.
