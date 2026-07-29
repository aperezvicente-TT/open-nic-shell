---
name: tt-rdma-v1-qdma-path-decision
description: "P1 uses QDMA C2H ST queue for SEND/SEND_IMM publish; P2 adds AXI-MM bridge tap for WRITE/READ_RESP — both coexist on the same QDMA IP, no IP regen between phases"
metadata: 
  node_type: memory
  type: project
  originSessionId: ed34fe36-50cb-41d4-bdaf-0045ca258750
---

Decided 2026-05-22. The TT-RDMA-v1 endpoint plugin uses **two** QDMA fabric-side interfaces, lit up in phases on the same PCIe/QDMA IP instance:

| Phase | Interface | Opcodes | Why this surface |
|-------|-----------|---------|------------------|
| **P1** | `m_axis_qdma_c2h_*` (C2H ST AXIS) | SEND, SEND_IMM | Spec semantic is "publish to next pre-posted recv slot" — descriptor-managed ring is the natural fit. ~8.1 Mslots/s at 100 G jumbo, well within PCIe Gen3 x16 completion budget. |
| **P2** | `s_axib_*` via `axi_interconnect_to_sys_mem_mux` (Bridge Slave AXI-MM) | WRITE, WRITE_IMM, READ_RESP | Spec semantic is "place at `base[remote_offset]`" — no descriptors, direct fabric→host TLP. |

**Why both, not one:** The opcode classes have different semantics. Real production HCAs (Mellanox CX-7 etc.) use both surfaces simultaneously: SRQ-style recv for SEND, RDMA direct placement for WRITE. Trying to force everything onto one surface either adds descriptor RTT to WRITE (wrong) or builds a recv-side software layer where the hardware should do it (wrong).

## No PCIe IP regen between phases

The QDMA IP config (`qdma_no_sriov_au250.tcl:43-45`) already enables **both** interfaces simultaneously:
- `CONFIG.dma_intf_sel_qdma {AXI_MM_and_AXI_Stream_with_Completion}`
- `CONFIG.en_bridge_slv {true}`
- `CONFIG.en_axi_mm_qdma {true}`

P1 and P2 are additive shell-RTL plumbing; no Vivado IP regen between them.

## P1 work surface (smallest correct diff)

- `plugin/tt_rdma_v1_endpoint/box_250mhz/user_plugin_250mhz_inst.vh` — drive `m_axis_qdma_c2h_*` from `m_axis_ring_push`. Set `tuser_qid`, `tuser_size=1536`, `tlast` at slot end.
- Host SDK pre-posts 64 C2H descriptors covering the hugepage ring.
- No changes to `box_250mhz.sv`, `open_nic_shell.sv`, or any IP TCL.
- Open follow-up: confirm a free `qid` reserved for the endpoint (audit followup #4 — depends on `EXT_QID` setting in `qdma_subsystem.sv:26`).

## P2 work surface (when WRITE lands)

Touches needed:
- `src/utility/axi_interconnect_to_sys_mem_mux.sv` — currently hand-coded for 2 hard-wired slaves (`s_axi_ernic0_sys_mem`, `s_axi_ernic1_sys_mem`). **Decision: rewrite as parameterized `NUM_MASTERS` generic** before adding the plugin as a 3rd master. Cosmetic upfront cost; makes future endpoint additions and ERNIC removal trivial.
- `src/box_250mhz/box_250mhz.sv` — expose `m_axi_sys_mem_*` master ports to plugins (today only exposes AXIS C2H/H2C).
- `src/open_nic_shell.sv` — wire the new master into the mux.
- Plugin needs an AXIS→AXI-MM ring-slot writer + base/limit CSRs (write to `host_base + slot*1536`).

## Don't use ERNIC as a positive reference

See [[dont-cite-ernic-as-good-architecture]]. ERNIC happens to consume the `s_axib_*` Bridge Slave surface in this shell — that's structural fact, not a model to mimic.

See [[tt-rdma-v1-endpoint-phase-c-landed]] for endpoint context and [[tt-rdma-v1-header-cksum-demo-defers-we-decide]] for the open CRC decision.
