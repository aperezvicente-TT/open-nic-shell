# OpenNIC 1-PF / 2-CMAC Pure-Ethernet NIC — Documentation

This directory is the complete technical reference and operator's guide for the
**single-PF, dual-CMAC, pure-Ethernet** OpenNIC build maintained in this fork.

It documents a variant of the [Xilinx/AMD OpenNIC shell](https://github.com/Xilinx/open-nic-shell)
in which **one QDMA physical function drives two independent 100 GbE (CMAC) ports**,
each surfaced to Linux as its own network interface — with **no RDMA/ERNIC** in the
datapath. The mechanism that makes this possible is a custom **queue-ID (qid) steering**
datapath grafted into the QDMA subsystem and a bespoke `box_250mhz` plugin.

> **Status:** hardware-validated on an Alveo U200 (xcu200), Vivado 2024.2.
> Both CMAC ports pass bidirectional traffic concurrently at 0 % packet loss.

---

## How to read these docs

If you are… | Start with
--- | ---
**New to the project** | Ch. 1 (Introduction), then Ch. 2 (Architecture)
**Trying to understand *how* 1-PF/2-CMAC works** | Ch. 3 (QDMA/qid graft) → Ch. 4 (Plugin)
**Building or flashing a bitstream** | Ch. 6 (Build & Flash)
**Bringing the card up / running traffic** | Ch. 7 (Operation & Bring-up)
**Debugging a problem** | Ch. 8 (Diagnostics & Troubleshooting)
**Looking up a register or offset** | Ch. 9 (Reference)
**Planning what to build next** | Ch. 10 (Roadmap)

---

## Table of contents

| # | Chapter | Contents |
|---|---------|----------|
| 1 | [Introduction & Overview](01-introduction.md) | What this is, goals/non-goals, the two repos, the big picture |
| 2 | [Shell Architecture](02-architecture.md) | Top module, subsystems, clock domains, the end-to-end AXI-Stream datapath, control plane |
| 3 | [QDMA Subsystem & the qid Graft](03-qdma-subsystem.md) | QDMA IP, H2C/C2H engines, `EXT_QID`, the tuser-qid byte-lock, the C2H width chain |
| 4 | [The 1-PF/2-CMAC Plugin](04-plugin-qid-steering.md) | `eth_2cmac_1pf`: TX demux, the clamp bug, RX FIFOs + arbiter, C2H qid tagging, diag CSR |
| 5 | [The Linux Driver](05-driver.md) | `onic` multi-netdev-per-PF, queue-mapping invariant, the `num_cmacs` fix, load/build |
| 6 | [Build & Flash Guide](06-build-and-flash.md) | Prereqs, licenses, `build.tcl`, the build wrapper, timing XDC fix, `.mcs` vs `.bit` |
| 7 | [Operation & Bring-up Runbook](07-operation-runbook.md) | Driver load, netdev↔CMAC map, IP/neighbor config, the NetworkManager gotcha, ping/iperf |
| 8 | [Diagnostics & Troubleshooting](08-diagnostics.md) | Reading the diag counters, CMAC stats, known-good failure playbooks, BW/retransmit analysis |
| 9 | [Reference: Registers, Offsets & Bit-fields](09-reference.md) | Consolidated BAR map, CMAC strides, diag CSR offsets, qid/TUSER bit-field tables |
| 10 | [Roadmap: From Working Link to Full NIC](10-roadmap.md) | Gap analysis by tier (table-stakes → SmartNIC), FPGA-vs-driver split, effort estimates |

---

## The two repositories

This NIC is two coupled pieces of source, on two feature branches:

| Repo | Branch | Role |
|------|--------|------|
| `open-nic-shell` (this repo) | `feature/eth-1pf-2cmac-qid` | FPGA gateware: shell + `eth_2cmac_1pf` plugin + qid graft |
| `open-nic-driver` (`../open-nic-driver`) | `feature/eth-dual-netdev-1pf` | Linux kernel driver: one PF → N netdevs |

Both must be kept in lock-step on the **queue-mapping invariant**
(64 queues per CMAC; CMAC *c* owns absolute qid range `[c·64, (c+1)·64)`) —
see Ch. 4 and Ch. 5.

---

## Conventions used in these docs

- **H2C** = Host-to-Card = the **TX** direction (host → wire).
- **C2H** = Card-to-Host = the **RX** direction (wire → host).
- **CMAC** = the Xilinx *UltraScale+ Integrated 100G Ethernet* MAC hard block; one per physical QSFP port.
- **qid** = QDMA queue identifier. *Absolute* qid = the global queue index; *relative* qid = within a PF.
- Code references are cited as `path:line`.
- Register offsets are given relative to the PCIe BAR noted in each table (usually **BAR2**).
