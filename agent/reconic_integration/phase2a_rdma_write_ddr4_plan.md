# Phase 2a Plan — RDMA WRITE Loopback on DDR4 Device Memory

Written 2026-04-22 from the async research agent's report.  Phase 1b
validated that both ERNICs' 64-bit DDR4 buffer-base registers accept
`0xa350_0000` MSB (24/24 PASS).  Phase 2a drives the first real RDMA
packet end-to-end using those addresses.

## Goal

- ERNIC0 (CMAC0, initiator) posts one RDMA WRITE WQE
- Packet flows CMAC0 TX → loopback cable → CMAC1 RX → plugin classifier
  marks as RoCE → ERNIC1 RX
- ERNIC1 DMAs payload to target buffer in DDR4 (its own AXI master →
  `axi_interconnect_to_sys_mem` (ERNIC1) → `dev_mem` crossbar → MIG DDR4)
- ERNIC0 CQ completion fires
- Host reads target buffer via `/dev/reconic-mm` (QDMA MM bypass) and
  compares against source — match = success

All buffers (CIDB, SQ/CQ/RQ, data, err) live in DDR4 at
`DEVICE_MEM_OFFSET = 0xa350_0000_0000_0000`.  Host-memory path is
blocked (s_axib bridge, Tier 1b not yet done).

## Key libreconic primitives (signatures from `rdma_api.h`)

```c
// Device init
struct rn_dev_t*   create_rn_dev(char* pcie_resource, int* pcie_resource_fd,
                                 uint32_t num_hugepages_request, uint32_t num_qp);
struct rdma_dev_t* create_rdma_dev_port(struct rn_dev_t*, uint8_t port_id);

// Config
void open_rdma_dev(struct rdma_dev_t*, struct mac_addr_t local_mac, uint32_t local_ip,
                   uint32_t udp_sport, uint16_t num_data_buf, uint16_t per_data_buf_size,
                   uint64_t data_buf_baseaddr, uint16_t ipkt_err_stat_q_size,
                   uint64_t ipkt_err_stat_q_baseaddr, uint16_t num_err_buf,
                   uint16_t per_err_buf_size, uint64_t err_buf_baseaddr,
                   uint64_t resp_err_pkt_buf_size, uint64_t resp_err_pkt_buf_baseaddr);
void config_rdma_global_csr(struct rdma_dev_t*);

// Buffers (DDR4 bump allocator, no free-list)
struct rdma_buff_t* allocate_rdma_buffer(struct rn_dev_t*, uint64_t buf_size,
                                          char* buf_location);       // DEVICE_MEM or HOST_MEM

// QP/PD
struct rdma_pd_t*  allocate_rdma_pd(struct rdma_dev_t*, uint32_t pd_num);
struct rdma_qp_t*  allocate_rdma_qp(struct rdma_dev_t*, uint32_t qpid, uint32_t dst_qpid,
                                     struct rdma_pd_t*, uint64_t cq_cidb_addr,
                                     uint64_t rq_cidb_addr, uint32_t qdepth,
                                     char* buf_location, struct mac_addr_t* dst_mac,
                                     uint32_t dst_ip, uint32_t partition_key, uint32_t r_key);
void config_sq_psn(struct rdma_dev_t*, uint32_t qpid, uint32_t sq_psn);
void config_last_rq_psn(struct rdma_dev_t*, uint32_t qpid, uint32_t last_rq_psn);

// WQE / send / completion
void create_a_wqe(struct rdma_dev_t*, uint32_t qpid, uint16_t wrid, uint32_t wqe_idx,
                   uint64_t laddr, uint32_t length, uint32_t opcode,
                   uint64_t remote_offset, uint32_t r_key,
                   uint32_t p0, uint32_t p1, uint32_t p2, uint32_t p3,
                   uint32_t immdt_data);
int  rdma_post_send(struct rdma_dev_t*, uint32_t qpid);
int  poll_cq_cidb(struct rdma_dev_t*, uint32_t qpid, int sq_cidb);

// Teardown
void dump_registers(struct rdma_dev_t*, uint8_t is_sender, uint32_t qpid);
int  destroy_rn_dev(struct rn_dev_t*);
```

## DEVICE_MEM allocator (from `reconic.c:204-266`)

- Simple bump pointer `rn_dev->dev_buffer_offset`, 4 KB aligned
- Total: 4 GB (`DEVICE_MEM_SIZE` in `reconic.h:47`)
- No `free` — allocate everything up-front
- Returned `rdma_buff_t.dma_addr` = `offset | 0xa350_0000_0000_0000`

**Constraint:** `allocate_rdma_qp` allocates SQ/CQ/RQ in ONE domain
(buf_location passed through to all three).  **CIDB must be in the same
domain as SQ/CQ/RQ** — can't mix host+device CIDB with device SQ.  For
this test, CIDB, SQ, CQ, RQ, data, err — all in DDR4.

## Configuration table

| Item | ERNIC0 (initiator / CMAC0) | ERNIC1 (target / CMAC1) |
|---|---|---|
| BAR2 base | 0x800000 | 0xA00000 |
| Port ID (`create_rdma_dev_port`) | 0 | 1 |
| Local MAC | e.g. `00:0a:35:48:01:00` (CMAC0 MAC) | `00:0a:35:48:01:01` (CMAC1 MAC) |
| Local IP | `10.0.0.2` | `10.0.0.3` |
| UDP sport | 4791 (RoCEv2) | 4791 |
| QP ID used | 2 | 2 |
| `dst_qpid` | 2 (points at ERNIC1.QP[2]) | 2 |
| `partition_key` | 0x1234 | 0x1234 |
| `r_key` | 0x00000008 | 0x00000008 (both sides agree) |
| PSN (SQ/RQ) | start at 0xabd / 0xabc | 0xabd / 0xabc (mirror) |

Loopback cable CMAC0 ↔ CMAC1 on the same card (direct DAC or OM3 fiber).
L2 same subnet, so no gateway.  No ARP needed since we program MACs
directly.

## Test flow (pseudocode)

```
1. Open PCIe BAR2 fd.  Open /dev/reconic-mm for DDR4 host-side DMA read.
2. rn_dev = create_rn_dev(bar2_path, &fd, 0 /*hugepages*/, 8 /*num_qp*/)
3. rdma0 = create_rdma_dev_port(rn_dev, 0);  rdma1 = create_rdma_dev_port(rn_dev, 1);

4. Allocate DEVICE_MEM for:
   - cidb_buf  (shared for CQ/RQ doorbells, 1×hugepage)
   - data_buf, err_buf, ipkterr_buf, resp_err_buf (one per ERNIC ideally; can share for loopback)
   - src_payload (ERNIC0 source, 256 B)
   - dst_payload (ERNIC1 target, 256 B)

5. Program both ERNICs:
   open_rdma_dev(rdma0, mac0, ip0, 4791, 256/4096, data_baseaddr0, ...)
   open_rdma_dev(rdma1, mac1, ip1, 4791, 256/4096, data_baseaddr1, ...)
   config_rdma_global_csr(rdma0);  config_rdma_global_csr(rdma1);

6. PDs & QPs:
   pd0 = allocate_rdma_pd(rdma0, 0);   pd1 = allocate_rdma_pd(rdma1, 0);
   qp0 = allocate_rdma_qp(rdma0, qpid=2, dst_qpid=2, pd0,
                          cq_cidb_addr, rq_cidb_addr, qdepth=64,
                          DEVICE_MEM, &mac1, ip1, pkey, rkey);
   qp1 = allocate_rdma_qp(rdma1, qpid=2, dst_qpid=2, pd1,
                          cq_cidb_addr, rq_cidb_addr, qdepth=64,
                          DEVICE_MEM, &mac0, ip0, pkey, rkey);

7. PSNs:
   config_sq_psn(rdma0, 2, 0xabd);   config_last_rq_psn(rdma0, 2, 0xabc);
   config_sq_psn(rdma1, 2, 0xabd);   config_last_rq_psn(rdma1, 2, 0xabc);

8. Populate source payload in DDR4 via write_from_buffer (/dev/reconic-mm).

9. Wait for CMAC link-up (poll both CMAC STAT_RX_STATUS for bit0, timeout 5s).
   Add 500 ms grace after link-up given current marginal timing.

10. Post RDMA WRITE:
    create_a_wqe(rdma0, qpid=2, wrid=0, wqe_idx=0,
                 laddr = src_payload->dma_addr,
                 length = 256,
                 opcode = RNIC_OP_WRITE,
                 remote_offset = dst_payload->dma_addr,
                 r_key, 0, 0, 0, 0, 0);
    rdma_post_send(rdma0, 2);

11. Poll ERNIC0 CQ (poll_cq_cidb) with 5s timeout.

12. Verify:
    - ERNIC0 CQ cidb advanced
    - read_to_buffer(dst_payload->dma_addr) into host scratch, memcmp vs src

13. dump_registers(rdma0, 1, 2);   dump_registers(rdma1, 0, 2);

14. destroy_rn_dev(rn_dev).
```

## Success criteria

1. `memcmp(src, read_back_target, 256) == 0`
2. ERNIC0 CQ cidb advanced by exactly 1
3. ERNIC0 `WQEPROCSTS[1:0] == 00` (no WQE-proc error)
4. ERNIC0 `INSRRPKTCNT` and ERNIC1 `OUTIOPKTCNT` (or similar packet
   counters — exact names per PG332 v4.3 to confirm at bench) increment
   by 1
5. No bits set in either ERNIC's `INTSTS` error fields

## Risks (from research, in priority order)

| Risk | Mitigation |
|---|---|
| Current bitstream WNS = -0.200 ns causes WQE/CSR corruption | Rebuild with slice-narrowing fix in progress.  Also add 500 ms inter-op sleeps during debug.  Watch `WQEPROCSTS`. |
| CMAC link-up timing post-bitstream-load | Poll `CMAC_OFFSET_STAT_RX_STATUS[0]=1` on both ports before posting.  5 s timeout. |
| ERNIC WQE encodes wrong bits of `0xa350_xxxx_xxxx_xxxx` | Test small payload to low DDR4 offset (e.g., 0xa350_0000_0001_0000).  If memcmp fails but WQE completed, suspect MSB aliasing. |
| Classifier misroutes RoCEv2 UDP 4791 packets to netdev | `ethtool -S enp1s0d1` should NOT increment RX counters during RDMA traffic. If it does, classifier broken. |
| QP pair with same `qpid=2` on both ERNICs — ambiguous? | PG332 v4.3 `DESTQPCONFi` explicitly encodes remote QP number.  As long as we set it correctly on both sides, `qpid` on local side is just an index. |

## Open bench questions to resolve during iteration

1. **CMAC link-up latency after program_fpga**: is 1 s enough, or 3 s?
2. **DEVICE_MEM high-bit handling by ERNIC**: does ERNIC pass the full
   0xa350_xxxx_xxxx_xxxx into its AXI master transactions, or does it
   truncate to 40-bit?  Observable by writing to `0xa350_0001_....` and
   checking if the 41st bit survives.
3. **Classifier behavior for dual-ERNIC RoCE**: does `packet_classifier_rtl`
   route ERNIC1-destined packets to ERNIC1 based on dest MAC/IP, or does
   it route by which CMAC they arrived on?  RTL implements the latter
   (per-CMAC classifier) — confirmed, no ambiguity.
4. **CIDB in DDR4 latency**: measurable overhead vs. host CIDB?  Phase 2a
   probably won't care (single-op test) but document for Phase 2+.
5. **Does MAC/IP programming persist across ERNIC re-enable?** — affects
   re-run without rmmod.

## Effort estimate

- Bench setup (cable, peer IP config if needed): 2-4 hrs
- Coding the test (using libreconic primitives from this plan): 1-2 hrs
- Debug iteration (expect 2-3 failure modes to trace): 2-3 hrs
- Total: **5-9 hours of focused work**

## Files to create / modify

- `rdma_test/phase2a_rdma_write_ddr4.c` (new, ~400 LOC)
- `rdma_test/Makefile` (add build target)

No libreconic changes needed — all APIs already exist; just use `DEVICE_MEM`
string where existing `write.c` uses `HOST_MEM`.

## Related docs

- `tier1a_validation_runbook.md` — Tier 1a register bring-up (PASSED)
- `tier1b_qdma_audit.md` — s_axib work still paused; Phase 2a intentionally
  uses DDR4 to sidestep
- `dual_netdev_plan.md` — architecture for single-PF dual-netdev shell
- `phase1b_ernic_data_plane_config.c` in rdma_test/ — DDR4-address register
  regression (24/24 passed)

---

Next session: flash new timing-closed bitstream, re-run phase1b as regression,
then start coding phase2a_rdma_write_ddr4.c following this plan.
