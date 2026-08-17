---
name: project_h2c_no_multidesc_gather
description: NETIF_F_SG scatter-gather TX blocked on au200 1PF/2CMAC — QDMA H2C runs in INTERNAL mode which ignores multi-descriptor SOP/EOP framing; no driver-only fix (6-encoding sweep failed); needs FPGA descriptor-bypass mode or a coalescing shim
metadata: 
  node_type: memory
  type: project
  originSessionId: 86bc0a95-48a1-447e-88ad-491d7b3ea882
---

**UPDATE 2026-07-15 (offline re-diagnosis — see docs/12 §12.14.3):** the FPGA
descriptor-bypass fix below was ATTEMPTED (Phase A, built+run on hardware twice) and
parked at a "byp_in doesn't deliver" blocker (cidx advances, ~0 bytes on wire). Docs
first concluded "needs ILA + Xilinx case"; a fresh offline audit found that premise is
**premature**. Confirmed-correct offline: driver `sw_ctxt.bypass` lands on the right
bit (BIT18, matches EQDMA v5), descriptor packing↔RTL extraction self-consistent, IP
generated for bypass, wiring intact. The actual leads: (1) the byp module
`qdma_subsystem_h2c_byp.sv` was copied from the **CPM5 (Versal)** `dsc_byp_h2c.sv` — the
WRONG IP family; U200=`xcu200` uses **soft `qdma_v5_1` (EQDMA soft)** whose bypass iface
differs (`fmt[3:0]` vs `[2:0]`, etc.); the correct soft-IP reference is encrypted so was
never diffed; (2) the module **dropped the marker loopback** (`mrkr_req`/`mrkr_rsp`,
which the soft IP's bypass iface defines) — hardwired `mrkr_req=0`. Offline-first resume
plan: Vivado `open_example_project` on `qdma_v5_1` → plaintext correct-IP reference →
rebuild byp module (fix `fmt`/`st_mm` decode + restore marker loopback) + mirror
libqdma's bypass queue setup (FMAP + `GLBL_DSC_CFG.MAX_DSC_FETCH`) in `onic_hardware.c`
→ one rebuild → retest. ILA/vendor only if that fails. libqdma is vendored twice
(`onic-driver/libqdma`, `../dma_ip_drivers`) but is a framework, not a drop-in submodule
for the netdev driver — mirror its sequence, don't adopt wholesale.

**NETIF_F_SG scatter-gather TX is disabled on the au200 1PF/2CMAC eth bitstream
(`feature/eth-1pf-2cmac-qid`) because of an OpenNIC descriptor-field-overload bug —
NOT because the QDMA H2C ST engine can't gather.** The engine DOES support
multi-descriptor packets (Xilinx reference DPDK `qdma_user.c` builds one descriptor
per mbuf segment, SOP-first/EOP-last).

Authoritative EQDMA5 H2C ST descriptor (16B, `libqdma/qdma_regs.h struct qdma_h2c_desc`):
`cdh_flags` DW0[15:0] (NUM_GL[2:0], NUM_CDH[6:3], ZERO_CDH[13], EOT[14]) | `pld_len`
DW0[31:16] (reference sets = len) | `len` DW0[47:32] (per-descriptor DMA read length)
| `flags` DW0[63:48] (SOP=bit0, EOP=bit1) | `src_addr` DW1.

The custom `qdma_legacy` driver folds cdh_flags+pld_len into one 32-bit `metadata`
field (DW0[31:0]) and repurposes `metadata[15:0]` as a whole-packet-length sideband
for the shell's `tkeep` generator (`qdma_subsystem_function.sv`). My SG code set
`metadata = total_len` on the SOP descriptor → `cdh_flags = total_len&0xffff` =
bogus NUM_GL/NUM_CDH counts → engine misparses the start-of-packet descriptor and
terminates the packet after desc0. It also left `pld_len=0` (reference mirrors len).

On-wire proof (hex capture at ConnectX-6 peer, 2026-07-14): a 2-descriptor frame
(66B head SOP + 124B frag EOP = 190B) arrived with correct headers/IP-length(176)
but garbage payload (adjacent memory) and exactly one 64B AXI beat short (190→126);
peer drops it (`frame_len != IP_len`). `len`[47:32] and `flags` SOP/EOP were set
CORRECTLY by the driver; the failure is the `metadata`↔`cdh_flags`/`pld_len` overlap.

**No driver-only fix exists — proven by a 6-encoding sweep (2026-07-14).** Tried
metadata modes: legacy(cdh=total,pld=0); Xilinx-reference(cdh=0,pld_len=seg);
pld=seg|cdh=total; total-on-EOP-only; ZERO_CDH(bit13) variants. ALL failed
identically at the fragmented-skb stage (iperf3 "unable to receive parameters").

**Real root cause: the QDMA H2C ST engine runs in INTERNAL mode on this design**
(`qdma_subsystem.sv` ties off the H2C descriptor-bypass input:
`h2c_byp_in_st_vld=0`, `dsc_byp_mode {Descriptor_bypass_and_internal}` in the IP tcl
but bypass unused for H2C). **Internal mode does not honor multi-descriptor SOP/EOP
framing** — SOP/EOP are only meaningful in descriptor-bypass mode (cf. libqdma
`descq_proc_st_h2c_request` sets SOP/EOP only when `conf.desc_bypass`). So each
descriptor is effectively its own packet and no descriptor encoding the driver
writes can make the IP gather. The metadata/cdh_flags theory (and the earlier
"IP can't gather" / "silently dropped") were all wrong along the way.

**Fix requires an FPGA change**: run H2C ST in descriptor-bypass mode with shell
RTL driving `h2c_byp_in_st_{addr,len,sop,eop}` per fragment, OR add a store-and-
coalesce shim ahead of the CMAC that reassembles a driver-fragmented packet. Big
enough that SG stays off (linear TX is 9.1-9.5 Gbit/s, 0 retr) until it's worth it.
Documented in docs/10-roadmap.md §10.2 item 1.3.

**How this surfaced (2026-07-14):** implemented scatter-gather TX (`NETIF_F_SG`) in
open-nic-driver `onic_xmit_frame` (one H2C descriptor per skb fragment; metadata =
total len on every desc; SOP/EOP from `desc->flags`; skb freed only at EOP slot in
`onic_tx_clean`). Driver builds/loads fine and `ethtool -k` shows `scatter-gather:
on`, but **any TCP broke** — the iperf3 control handshake is a fragmented skb.
Symptom signature: FPGA netdev `tx_packets` counts the frame as sent, but it never
reaches the wire (measured FPGA TX 10 pkts → peer RX 8 pkts; `stat_tx_bad_fcs=0`,
peer `rx_crc_errors_phy=0`, `tx_dropped=0`). Linear (single-descriptor) TX is
flawless: 9.45 Gbit/s, 0 retr. `ping` works with SG on (ICMP = linear skb).

**Resolution:** `NETIF_F_SG` is NOT advertised (onic_main.c `onic_apply_netdev_features`);
stack linearizes paged skbs. The multi-descriptor code is retained but dormant.
To enable SG, an FPGA change is required: make the H2C ST path gather multiple
descriptors into one contiguous packet, and re-verify `qdma_subsystem_function.sv`
tkeep-on-last-beat (`axis_h2c_tuser_size[5:0]`) + `axi_stream_size_counter` across
descriptor boundaries. Documented in docs/10-roadmap.md §10.2 item 1.3.

**GRO (RX) is unaffected** — already active via `napi_gro_receive`, default-on soft
feature; roadmap item 2.3 was already satisfied. Related: [[reference_wh_fw_tx_stall_bisect]]
(other silent-TX-drop gotchas on this stack).

**Test bench:** QSFP0 (`.223` enp1s0, onic) ↔ ConnectX-6 (`.180` enp1s0np0). Direct
cable needs a PRIVATE subnet (used 192.168.199.0/24) — `10.42.0.0/24` collides with
the corporate net and the peer answers ARP over the cable but routes IP replies back
via its corporate NIC (ARP flux → asymmetric routing → L3 black-hole). iperf3 server
binary on `.180`: `/home/alex/mpi-shfs/fpga/iperf/src/iperf3` (shared mpi-shfs mount).
