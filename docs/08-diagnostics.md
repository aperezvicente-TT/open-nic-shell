# Chapter 8 — Diagnostics & Troubleshooting

This chapter is the debugging toolkit: how to read the on-chip counters, how to confirm
the flashed image and CMAC health, playbooks for the failures actually hit during
bring-up, and the analysis of the throughput/retransmit behaviour.

## 8.1 The tools

- **`ernic-baremetal bar-poke`** — reads/writes BAR2 registers from user space:
  ```bash
  tools/ernic-baremetal/ernic-baremetal bar-poke 0000:01:00.0 <offset>
  ```
  (The tool name is a historical artifact of the RDMA lineage; it is just a BAR
  peek/poke and is used here purely for the plugin diag counters and CMAC stats.)
- **`dmesg`** — driver probe log (num_cmacs, netdev creation, IRQ setup).
- **`ethtool -S <netdev>`** — per-netdev stats.
- **`ip -s link`** — netdev drop/error counters.

> **BDF note:** the examples use `0000:01:00.0`. The card's BDF changes if you move it to
> a different PCIe slot — re-check with `lspci -d 10ee:`.

## 8.2 Confirm which bitstream is flashed

Read the build-stamp register (system-config `BUILD_STATUS`, BAR2 `0x0`):

```bash
tools/ernic-baremetal/ernic-baremetal bar-poke 0000:01:00.0 0x0
```

The validated **clamp-fix** image reads **`0x07010922`**. If you read a different value,
you are not running the fixed bitstream — reflash (Ch. 6 §6.8) and reboot.

## 8.3 The plugin diagnostic counters (the primary instrument)

The 18 counters at **BAR2 `0x100000 + offset`** (full table in Ch. 4 §4.5 and Ch. 9) let
you watch a packet traverse every hop. The essential six:

| Offset | Counter | Meaning |
|--------|---------|---------|
| `0x100000` | RX0_adap_in | frames received on **CMAC0** |
| `0x100018` | RX1_adap_in | frames received on **CMAC1** |
| `0x100030` | TX0_h2c_demux | H2C frames steered to **CMAC0** |
| `0x100034` | TX1_h2c_demux | H2C frames steered to **CMAC1** |
| `0x100040` | RX_MARK_MISMATCH | should stay **0** (RX qid/grant sanity) |
| `0x100044` | TX_QID_CHANGED | should stay **0** (mid-packet qid stability) |

Read-delta pattern (do this before/after a traffic burst):

```bash
BDF=0000:01:00.0; POKE="tools/ernic-baremetal/ernic-baremetal bar-poke"
for off in 0x100000 0x100018 0x100030 0x100034 0x100040 0x100044; do
  printf "%s = %s\n" $off "$($POKE $BDF $off)"
done
```

### Using the counters to determine CMAC↔peer topology

The physical mapping of CMAC0/CMAC1 to the two cables is **not guessable** — on this
bench it turned out **inverted** from the naive assumption. To determine it authoritatively:

1. Assign IPs and ping **one** peer only.
2. Read `RX0_adap_in` (`0x100000`) and `RX1_adap_in` (`0x100018`).
3. Whichever increments is the CMAC that peer is cabled to.

**Result on this bench:** CMAC0 ↔ `.221`, CMAC1 ↔ `.223`. Likewise, ping out of one
netdev and watch `TX0_h2c_demux` / `TX1_h2c_demux` to confirm the TX demux picks the port
you expect.

## 8.4 CMAC health and netdev counters

- **CMAC RX alignment:** `STAT_RX_STATUS` (per-CMAC `+0x0204`, bit0 = aligned) — must be
  1 for a linked port.
- **CMAC adapter counters** (`CMAC_ADPT` block, per-CMAC `+0x3000` then `+0x0/0x10/0x20/
  0x30/0x40`): TX/RX packet recv/drop/error. **FCS/error counts must be 0** on a clean
  link.
- **Netdev drops:** `ip -s link show enp1s0` — `RX/TX dropped` should be 0.

If pings fail but these are all healthy (carrier up, RX aligned, zero errors/drops), the
problem is almost always **host config** (see §8.5, config drift), not the FPGA.

## 8.5 Failure playbooks

### A. Ping shows 100 % loss but carrier is up → **config drift (NetworkManager)**

**By far the most common false alarm.** NetworkManager re-manages the interface and strips
the manually-added IPv4 (on the host *and* on the remote peers). The source interface then
has no address, so every packet is "lost" although the link is perfect.

**Diagnose:** `ip -4 -br addr show <dev>` shows an **empty** address.
**Fix:** re-assert config with `nmcli device set <dev> managed no` first (Ch. 7 §7.4).
This bit us mid-session: a concurrent ping reported CMAC0 100 % loss; the interfaces had
simply lost their IPs. Re-asserting restored 0 % loss on both ports immediately.

### B. "CMAC0 TX is dead" (stat_tx = 0, all traffic egresses CMAC1) → **plugin clamp bug**

This is the historically important one. Symptom: everything you send comes out CMAC1;
`TX0_h2c_demux` never increments; CMAC0 `stat_tx` = 0. **Root cause:** the demux clamp
underflow (Ch. 4 §4.3) hardwired the port-select to CMAC1. **Fix is in the RTL** (commit
`1781c4f`); confirm you are running build-stamp `0x07010922` (§8.2). *Note the two earlier
"qid-value" fixes failed identically because the demux never read the qid at all.*

### C. Driver reports `num_cmacs = 8`, 6 spurious secondary failures → **CMAC stride bug**

**Root cause:** the `CMAC_SUBSYSTEM_OFFSET` macro aliased every index ≥1 to `0xC000`
(Ch. 5 §5.4). **Fix** is in the driver (commit `274de0c`); rebuild `onic.ko`. Correct
behaviour is exactly **2 netdevs**.

### D. Build fails: no CMAC license → **restore the license file**

`cmac_usplus` OOC synth fails without the node-locked license. Restore
`~/.Xilinx/Xilinx100GEthSubsystem.lic` (Ch. 6 §6.1) or set `XILINXD_LICENSE_FILE`.

### E. Build fails: "IP name `cmac_usplus_0` already in use" → **stale IP cache**

You ran `build.tcl` on a dir with generated IP without cleanup. Use the wrapper (which
passes `-overwrite 1 -rebuild 1`) or delete `build/au200_eth_1pf_2cmac_qid` first
(Ch. 6 §6.2).

### F. Build aborts: "No valid object(s) found" on `set_false_path` → **timing XDC guard**

The PTP CDC false-path targets were optimized away. Fixed by the `fp_to_if`/`fp_from_if`
guards (Ch. 6 §6.5) — ensure you are on this branch.

### G. `insmod` permission denied under sudo → **use the absolute path**

The NOPASSWD sudoers rule matches the exact path
`/home/alex/mpi-shfs/fpga/open-nic-driver/onic.ko`. A relative path won't match.

## 8.6 Throughput and TCP retransmits — the benign-ceiling analysis

Observed: ~**20–22 Gbps per port** and some **TCP retransmits** under load. This is
**expected and benign**, not an FPGA/wire fault. Evidence:

- CMAC **FCS/error counters = 0**; netdev **drops = 0**; `RX_MARK_MISMATCH` /
  `TX_QID_CHANGED` trip-wires = 0.
- The remote peers are **Mellanox NICs in Gen3 ×4 PCIe slots**. Gen3 ×4 usable bandwidth
  is ≈ **22 Gbps**, so ~20–22 Gbps/port *is* the peer's line rate.
- The retransmits are ordinary TCP congestion at that PCIe ceiling: the receiver's slot
  cannot drain 100G, the socket buffer fills, and TCP backs off. On the wire and in the
  FPGA nothing is dropped.

**Conclusion:** to exceed ~22 Gbps/port you would need a faster PCIe slot on the *peer*
side, not any FPGA change. Per-CMAC RSS (multiple queues per port for line-rate scaling)
is possible in the design but unnecessary against a Gen3 ×4 peer.

## 8.7 Open / non-blocking items

These are known, deliberately-deferred loose ends (not defects in the running system):

1. ~~**Timing closure is not reproducible from source**~~ — **resolved 2026-07-29.**
   `-impl_strategies 'Performance_ExplorePostRoutePhysOpt'` closes clean (WNS +0.008 ns,
   TNS 0.000, 0 failing endpoints) with `-ultrathreads 0`, i.e. deterministically, and
   `-post_impl` now writes the `.mcs` from the best-WNS run. Defaults still lands at
   −0.095 ns / 82 endpoints, matching the original observation (Ch. 6 §6.6).
2. **Dead `port_id` RTL** in `qdma_subsystem_function.sv` (`h2c_qid_corrected`,
   `s_axis_h2c_tuser_port_id`) can be removed (Ch. 3 §3.6).
3. **Driver still links OFED** because the RDMA `.c` files still compile; dropping them
   from the Makefile wildcard removes the dependency (Ch. 5 §5.6).
4. **Reboot-persistent host networking** — install NM/netplan profiles pinning the static
   IPs + `managed no` on all three hosts, and a `modules-load.d` entry for `onic`, so
   bring-up survives reboot (Ch. 7 §7.9).

Continue to [Chapter 9 — Reference](09-reference.md).
