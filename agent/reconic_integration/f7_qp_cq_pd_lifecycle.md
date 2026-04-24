# F7 — QP / CQ / PD Lifecycle State Machines (ERNIC v4.2)

**Scope:** the QP, CQ, PD/MR state machines that `onic.ko` (and the Track C
gateway firmware, and the Track D orchestrator-driven pairing) build on top of
Xilinx ERNIC v4.2. This is the **shared substrate**. The control surface on
top of it differs per track — see §7.

**Companion header:** `/home/alex/mpi-shfs/fpga/libreconic/ernic_lifecycle.h`
(same enumerations, compiled for both kernel driver and userspace probe tools).

All PG332 citations are line numbers in
`pg332-ernic-4.2.md` (Chapter 3 "Register Space" lines 1452–3041; Chapter 7
"ERNIC Software Flow" lines 3497–3800).

---

## 1. Scope and non-goals

This is the **restricted RC-only subset** ERNIC v4.2 actually implements. It is
NOT a complete ibverbs state machine. Differences from what a ConnectX exposes:

- No UD except the dedicated QP1 for CM/MAD (PG332 lines 3562–3578).
- No SRQ, no XRC, no atomics, no flow-steering, no user-space UAR mmap.
- **One MR per QP** (enforced at driver level; §3). PD/MR collapse to a single
  handle.
- **One-shot CC only** — Track B observes CNP scheduling for logging; there is
  no runtime rate-limit loop (§9).
- `QP_STATE_SQD` (standard-ibverbs drain state), `QP_STATE_SQE` (IB-native
  send-queue-error), and the distinction between INIT/RTR/RTS-during-modify do
  not appear as separate hardware states in PG332. ERNIC exposes two observable
  state bits: `QPFATAL` (STATQPi[0]) and `QPEN` (QPCONFi[0]); everything else
  in §5 is driver-side bookkeeping.
- Max QPs: `C_NUM_QP` up to 2048 (PG332 lines 137, 324, 1378); our Track B
  production cap is 256.
- Doorbell path: AXI-Lite only (HW handshake mode disabled by default, PG332
  line 910); set `QPCONFi[4] HWHSHKDIS=1`.

If a verb needs a state this doc doesn't list, reject it at `ib_modify_qp`
with `-EOPNOTSUPP` rather than faking it.

---

## 2. PD lifecycle

ERNIC's MR/PD table is the "PD table" per PG332 lines 1455–1497. It is
**2048 rows × 8 × 32-bit registers** (PG332 lines 1455–1497 + Figure 9 in §3.1
at line 1378). Each row holds:

| Row offset | Register | Purpose |
|---|---|---|
| 0x00 | `PDPDNUM` | 24-bit PD number |
| 0x04 | `VIRTADDRLSB` | MR virtual address [31:0] |
| 0x08 | `VIRTADDRMSB` | MR virtual address [63:32] |
| 0x0C | `BUFBASEADDRLSB` | MR physical base [31:0] |
| 0x10 | `BUFBASEADDRMSB` | MR physical base [63:32] |
| 0x14 | `BUFFERKEY` | R_KEY for the MR |
| 0x18 | `WRRDBUFLEN` | MR byte length |
| 0x1C | `ACCESSDESC` | `[1:0]` access: `'b10` = remote-write enable (PG332 line 3793), PD number in upper bits |

### 2.1 States

```
                     +----------+
     row free  ----> |   FREE   |
                     +----+-----+
                          | ernic_pd_alloc()
                          v
                     +----------+
                     | ALLOC'D  |  (PDPDNUM written; VIRT/BUF/KEY/LEN/ACCESS still zero)
                     +----+-----+
                          | ernic_mr_register() binds MR (§3)
                          v
                     +----------+
                     |  BOUND   |  (PD is 1:1 with an MR; can be referenced by a QP's QCSR_PDi)
                     +----+-----+
                          | ernic_mr_deregister()
                          v
                     +---------------+
                     | DEREGISTERING | (zero the 8 registers; wait for no outstanding WQE)
                     +------+--------+
                            | release row
                            v
                     +----------+
                     |   FREE   |
                     +----------+
```

### 2.2 Rules

- **PD/MR are 1:1 in ERNIC.** A PD row that has no MR bound is useless — ERNIC
  only looks up PDT entries when processing an inbound `R_KEY`. We therefore
  collapse `ibv_alloc_pd` + `ibv_reg_mr` into a single `ernic_pd_alloc` +
  `ernic_mr_register` pair and reject multi-MR-per-PD at the driver.
- **Teardown order: invalidate row first, then tear down the QP.** If any QP
  has `QCSR_PDi` pointing at this row and is still enabled, incoming RDMA-WRITE
  with the matching `R_KEY` would hit a half-zeroed row. Order:
  1. Drain the QP per §5 (wait `STATQPi[9] SQEMPTY`, `[10] OSTQEMPTY`).
  2. Zero `ACCESSDESC` first (revokes remote access).
  3. Zero `BUFFERKEY` (R_KEY lookup now mismatches).
  4. Zero `VIRTADDRLSB/MSB`, `BUFBASEADDRLSB/MSB`, `WRRDBUFLEN`, `PDPDNUM`.
  5. Mark row FREE.

### 2.3 Allocation strategy

Bitmap of 2048 rows. Row 0 is reserved for QP1's PD. Rows 1..N are allocated
in order and `PDPDNUM` is set to `row_index + 1` so PD number 0 is reserved
(avoids confusion with cleared rows that read 0).

---

## 3. MR lifecycle

Single-MR-per-QP. Enforced at the driver: `ernic_mr_register` takes the PD
handle it will live under, and the PD has no prior MR.

### 3.1 States

```
  NONE  ---ernic_mr_register()-->  REGISTERED  ---ernic_mr_deregister()-->  NONE
                                      |
                                      | associated QP posts WRITE/READ
                                      | that hits the R_KEY
                                      v
                             (no state change — MR is passive)
```

MR never enters an ERROR state on its own; if the remote side uses a stale
R_KEY, ERNIC responds with NAK syndrome `0x01` (Invalid Request) which pushes
the *QP* into FATAL (not the MR).

### 3.2 Registration (PG332 lines 3583–3607)

1. Allocate physical memory, get DMA address.
2. Pick a free PDT row.
3. Write `PDPDNUM` (PG332 line 3599). Protection domain number is the *link*
   between MR and QP (the note immediately before PG332 line 3650 requires
   `QCSR_PDi` to match this `PDPDNUM`).
4. Write `VIRTADDRLSB/MSB` (PG332 line 3601).
5. Write `BUFBASEADDRLSB/MSB` (PG332 line 3603).
6. Write `BUFFERKEY` = driver-assigned R_KEY (PG332 line 3605).
7. Write `WRRDBUFLEN` = byte length, `ACCESSDESC[1:0]` = `'b10` for remote
   write, `'b01` for remote read (PG332 line 3606–3607).

### 3.3 Association with QP

When a QP is brought to RTR (§5), the driver writes the PDT row index into
`QCSR_PDi`. PG332 line 3650 (step 8 of RC QP Creation): *"PD number that the
QP is associated with is configured by writing to Protection Domain number
register."*

### 3.4 Deregistration

Precondition: no QP references this MR, OR all referring QPs are CLOSED. Then
zero the 8 registers in the order from §2.2 (ACCESSDESC first).

**Open question (FAE):** PG332 does not state whether an in-flight inbound
RDMA-WRITE that has already been ACK'd but is still being DMA'd to host memory
will complete cleanly if we zero `BUFBASEADDRLSB` mid-transfer. We assume the
drain in §2.2 step 1 covers this for outbound; for *inbound*, Track B
serializes deregister against the responder path by toggling `QPEN=0` first
and waiting one PMTU round-trip. Mark as "FAE query" to Xilinx.

---

## 4. CQ lifecycle

### 4.1 States

```
   NONE  --create-->  CREATED  --arm (QPCONFi[3]=1)-->  ARMED
                         ^                                |
                         |                                v
                         +--disarm-------------------  POLLING
                                                         |  (driver servicing CQEs)
                                                         v
                                               +-> ERR (CQFULL = STATQPi[4])
                                               v
                                         +--destroy--> NONE
```

In practice Track B keeps every CQ permanently `ARMED` (interrupt-driven
completions) and the transition CREATED → ARMED happens in one register
burst. POLLING is an ephemeral state entered on every IRQ and exited when the
bank bit is W1C-cleared.

### 4.2 Create (PG332 lines 3569–3572, 3618–3626)

1. Allocate DDR4 region for CQEs. CQE = **4 bytes** (PG332 Table 10 memory
   requirement, line 3108: `2048 QPs × 128 CQEs × 4 B = 1 MB`). Base must be
   **32-byte aligned** (PG332 register `CQBAi` bits `[31:5]`, per F1 audit
   §5.10).
3. Write `QCSR_CQBAi` (0x18_0018 + i·0x100) low and `QCSR_CQBAMSBi`
   (0x18_00D0) high.
4. Write `QCSR_QDEPTHi` with the CQ depth sub-field (PG332 calls it out as a
   sub-field of `QDEPTHi` alongside SQ/RQ depths).
5. Pre-allocate a 4-byte doorbell slot in the ERNIC doorbell memory pool;
   write its address into `QCSR_CQDBADDi`/`QCSR_CQDBADDMSBi` (PG332 line
   3577, 3625). ERNIC writes the running CQ completion count here so host
   polling is cache-line-local.

### 4.3 Arm

Set `QPCONFi[3] CQINTEN = 1` (F1 audit §5.5). Global `INTEN[4] WQECOMPL` must
also be set so the interrupt fires (F1 audit §5.3).

### 4.4 Poll sources

ERNIC signals completion in four places, any of which the driver may use:

1. **Global IRQ** — `INTSTS[4] WQECOMPL` asserted.
2. **Per-bank bit** — `CQINTSTSn` (32 banks, 32 QPs each; PG332 lines
   2159–2436). `bank = (qpid / 32) + 1`, `bit = qpid % 32`, with the caveat
   that bank-1 bit-0 is the management QP (`C_NUM_QP`), not QP 0 — see F1
   audit §5.4 and §2 of this doc.
3. **`CQHEADi`** — monotonically-incrementing head pointer, the hardware's
   authoritative "how many completions have been written" value (PG332 lines
   3678–3680, 995, 1030, 1078).
4. **Host-side doorbell write** — the 4-byte slot at `CQDBADDi`; same value
   as `CQHEADi` but readable from normal DRAM (faster than CSR read).

Driver uses source 2 to identify *which* QP, source 4 to read head, then
reads CQEs from the DDR4 CQ memory and advances its local tail.

### 4.5 Overflow

`STATQPi[4] CQFULL=1` (F1 audit §5 bonus). This is terminal for the QP — it
will transition to FATAL next (CQ overflow is one of the fatal causes per
PG332 line 4132 comment and §5.4 below). Driver must treat CQFULL as a hard
error, mark the CQ state ERR, and start QP fatal recovery (§5.5).

### 4.6 Destroy

Precondition: owning QP is CLOSED (§5.7). Then:

1. Disarm: clear `QPCONFi[3]`.
2. Zero `CQBAi`/`CQBAMSBi`, `CQDBADDi`/`CQDBADDMSBi`.
3. Free the DDR4 region and doorbell slot.

---

## 5. QP state machine

This is the centerpiece. ERNIC v4.2 hardware exposes two boolean state bits:

- `QPCONFi[0] QPEN` — 1 iff the QP is processing traffic (PG332 §3.1 / F1 audit §5.5).
- `STATQPi[0] QPFATAL` — 1 iff the QP has hit a fatal condition (PG332 lines
  4098–4132, F1 audit §5 bonus).

The other "states" below are **driver-invented bookkeeping** that mirrors the
IB verbs vocabulary and corresponds to distinct register-write groups from
PG332 Chapter 7 (RC QP Creation, lines 3612–3651).

### 5.1 State diagram

```
              ernic_qp_create()
   (none) ----------------------> +---------+
                                  |  RESET  |   QPEN=0, all per-QP regs zero
                                  +----+----+
                                       | ernic_qp_modify(..., RESET -> INIT)
                                       | writes: QPCONF (RQBUFSZ, PATHMTU, HWHSHKDIS),
                                       |         RQBAi, SQBAi, CQBAi, QDEPTHi,
                                       |         RQWPTRDBADDi, CQDBADDi, QCSR_PDi
                                       v
                                  +---------+
                                  |  INIT   |   QPEN still 0; buffers programmed
                                  +----+----+
                                       | ernic_qp_modify(..., INIT -> RTR)
                                       | writes: MACDESADD{LSB,MSB}i, DESTQPCONFi,
                                       |         IPDESADDR1..4i (QPCONFi[7] for IPv6),
                                       |         LSTRQREQi (remote PSN),
                                       |         TIMEOUTCONFi (retry/RNR),
                                       |         QPADVCONFi (TC/TTL/PKey),
                                       |         QPCONFi[2]=1 (RQINTEN if needed)
                                       v
                                  +---------+
                                  |   RTR   |   ready to receive; QPEN still 0
                                  +----+----+
                                       | ernic_qp_modify(..., RTR -> RTS)
                                       | writes: SQPSNi, QPCONFi[0]=1 (QPEN),
                                       |         bumps XRNIC_CONF_QP_EN to cover this QP
                                       v
                                  +---------+
                                  |   RTS   |<----------+
                                  +----+-+--+           |
                                       | |              | ernic_qp_handle_fatal()
                   ibv_post_send       | |              | clears QPURC, reinit per PG332
                   writes SQ memory,   | |              | lines 3755–3800
                   rings SQPIi         | |              |
                                       | |              |
                                       | |              |
                                       | +---> transmit WQEs, emit completions
                                       |       to CQ -> host polls (§4.4)
                                       |
                                       | FATALERR (INTSTS[7]) fires:
                                       | - CQFULL (CQ overflow)
                                       | - invalid packet, retry-exhausted, NAK-fatal
                                       | - RQ overflow (STATQPi[1])
                                       v
                                  +---------+
                                  |   ERR   |   QPFATAL=1, driver stops posting
                                  +----+----+
                                       | ernic_qp_handle_fatal() step 1:
                                       | set QPCONFi[6] QPURC = 1
                                       v
                                  +----------------+
                                  | UNDER_RECOVERY |   draining; see PG332 3728–3753
                                  +----+-----------+
                                       | drain complete (SQEMPTY=1, OSTQEMPTY=1,
                                       | CQHEADi == SQPIi, RESPHNDSTS[16]=1)
                                       | reinitialize per PG332 3755–3800
                                       v
                                  goes back to RTR (or CLOSED if app gave up)
                                       .
                                       . ernic_qp_destroy():
                                       .   drain (§5.7), QPEN=0, zero regs,
                                       .   decrement XRNIC_CONF_QP_EN
                                       v
                                  +---------+
                                  | CLOSED  |
                                  +---------+
```

### 5.2 Transition: RESET → INIT

Driver writes (all per-QP, QCSR base `0x18_0000 + (i-1)*0x100`):

| Register | Value | Source |
|---|---|---|
| `QPCONFi` | `HWHSHKDIS=1`, `PATHMTU`, `RQBUFSZ`; `QPEN=0` | PG332 3573, 3622 |
| `RQBAi` / `RQBAMSBi` | RQ base (256-B aligned) | PG332 3570, 3619 |
| `SQBAi` / `SQBAMSBi` | SQ base (32-B aligned) | PG332 3570, 3619 |
| `CQBAi` / `CQBAMSBi` | CQ base (32-B aligned) | PG332 3572, 3621 |
| `QDEPTHi` | SQ/RQ/CQ depths (min 16 per PG332 3620) | PG332 3571, 3620 |
| `RQWPTRDBADDi`/MSB | host RQ producer doorbell | PG332 3578, 3626 |
| `CQDBADDi`/MSB | host CQ completion doorbell | PG332 3577, 3625 |
| `QCSR_PDi` | PDT row index (PD/MR link) | PG332 3650 |

No interrupt fires. Purely a configuration step.

### 5.3 Transition: INIT → RTR

Driver writes (PG332 lines 3627–3651):

| Register | Value | PG332 ref |
|---|---|---|
| `MACDESADDLSBi`/`MSBi` | remote MAC | line 3629 |
| `DESTQPCONFi` | remote QPN | line 3630 |
| `IPDESADDR1i` (..4i for IPv6) | remote IP; `QPCONFi[7]` selects v4/v6 | line 3631 |
| `LSTRQREQi` | initial remote PSN | line 3634 |
| `TIMEOUTCONFi` | `[5:0]` timeout, `[10:8]` max retry, `[13:11]` max RNR retry, `[20:16]` RNR timeout | line 3647 |
| `QPADVCONFi` | TC/TTL/PKey | line 3797 (reinit path) — also programmed at init |
| `QPCONFi[2]` RQINTEN | 1 if RQ-side interrupts desired | F1 audit §5.5 |

`QPEN` still 0 — the QP cannot receive or send yet.

### 5.4 Transition: RTR → RTS

1. Write `SQPSNi` (PG332 line 3635) with local starting PSN.
2. Bump `XRNIC_CONF_QP_EN` (0x10_0044) to cover this QP index. F1 audit §6.2
   flags this as a 12-bit field whose exact COUNT-vs-MASK semantics are an
   FAE-query; Track B currently programs it as a COUNT and picks QP IDs
   densely from 1 upward.
3. Set `QPCONFi[0] QPEN = 1` (F1 audit §5.5; PG332 ch.7 does not dedicate a
   line to this single bit but the "QP can now be used" phrasing at line
   3657 implies it).

The first WQE may be posted any time after QPEN=1. Posting is:

- Write WQE into SQ memory at offset `SQPIi_current * sizeof(WQE)` (Table 2
  structure).
- Write `SQPIi_current + 1` to `QCSR_SQPIi`. This is the doorbell (PG332
  lines 975–985, 3659).

### 5.5 Transition: * → ERR (fatal)

Entered via any of (PG332 lines 4098–4132):

| Cause | How observed |
|---|---|
| Invalid packet from peer | `INTSTS[0] PKTVALERR` + fatal buffer entry |
| Retry exhausted | `STATQPi[26:24] CURRETRY == max`, then `QPFATAL=1` |
| NAK-fatal received | `STATQPi[22:16] NACKSYND` latched, `QPFATAL=1` |
| CQ full while posting completion | `STATQPi[4] CQFULL=1` → `QPFATAL=1` |
| RQ overflow | `STATQPi[1] RQOVFL=1`; ERNIC sends RNR NACK out, and if the sender exhausts RNR retries, eventually `QPFATAL=1` |
| Illegal opcode posted by us | `INTSTS[5] ILLOPCODE`, `QPFATAL=1` |

`INTSTS[7] FATALERR` fires. Driver reads `FATALERRBUFBA` per PG332 line 3742
to find which QP, and the 16-bit fatal code ("Table 5: Decoding for FATAL
Codes"). On entering ERR the driver MUST stop pushing `SQPIi` doorbells
(PG332 line 3747).

### 5.6 Transition: ERR → UNDER_RECOVERY → RTR

Exactly the sequence in PG332 lines 3742–3800:

**Drain phase:**
1. Set `QPCONFi[6] QPURC = 1` (PG332 line 3748).
2. Poll `STATQPi[9] SQEMPTY == 1 && [10] OSTQEMPTY == 1` (line 3749–3750).
3. Poll `CQHEADi == SQPIi` (line 3751).
4. Poll `RESPHNDSTS[16]` set (line 3752).
5. Clear `QPCONFi[0]` (QPEN=0), keep `QPCONFi[6]` (QPURC=1) (line 3753).

**Reinit phase:**
6. `XRNICADCONF[0]` (SWOVREN) = 1 — enables software writes to otherwise-RO
   pointers (F1 audit §5.2, PG332 line 3759).
7. Zero the pointer-state registers: `STATRQPIDBi`, `STATRQBUFCAi`,
   `STATRQBUFCAMSBi`, `RQCIi`, `STATCURSQPTRi`, `SQPIi`, `SQPSNi`,
   `LSTRQREQi`, `STATMSN`, `CQHEADi` (line 3760–3770).
8. Poll `CQHEADi == 0` (line 3771).
9. Write new `SQPSNi`, `LSTRQREQi` (line 3772–3774).
10. Rewrite Ethernet-side regs: `MACDESADDMSBi`/`LSBi`, `IPDESADDR1..4i` (line
    3775–3790).
11. Re-configure `QPCONFi[7]` IP version, `ACCESSDESC` access=`'b10` (line
    3791–3793).
12. Re-initialize retry-count fields in `STATQPi[26:24]` / `[30:28]` (line
    3792).
13. Re-program `QPCONFi` (RQINTEN/CQINTEN/PMTU/HWHSHKDIS/RQBUFSZ) and
    `QPADVCONFi` (TC/TTL/PKey) (line 3794–3798).
14. `QPCONFi[0]=1` (QPEN), `QPCONFi[6]=0` (clear QPURC) (line 3799).
15. `XRNICADCONF[0]=0` (SWOVREN off) (line 3800).

Driver considers the QP to have re-entered **RTR** after step 11 and **RTS**
after step 14 (one-shot — there is no wait-for-peer equivalent of standard IB
RTR).

### 5.7 Transition: * → CLOSED (destroy)

Per PG332 lines 3707–3723, and matches the fatal-recovery drain:

1. Wait `STATQPi[9] SQEMPTY==1 && [10] OSTQEMPTY==1` (line 3712).
2. Wait for all CQEs by checking `CQHEADi == SQPIi` (line 3714).
3. `XRNICADCONF[0]=1` (SWOVREN), `QPCONFi[0]=0` (QPEN off) (line 3716).
4. Zero `RQWPTRDBADDi`, `SQPIi`, `CQHEADi`, `RQCIi`, `STATRQPIDBi`,
   `STATCURSQPTRi`, `SQPSNi`, `LSTRQREQi`, `STATMSN`; set `QPCONFi[6]`
   QPURC=1 (line 3718–3720).
5. `XRNICADCONF[0]=0` (line 3721).
6. Decrement `XRNIC_CONF_QP_EN` accordingly.
7. Free SQ/RQ/CQ memory (line 3723).

---

## 6. Event / IRQ flow

Global `INTEN` / `INTSTS` layout (F1 audit §5.3):

| Bit | Name | Driver action |
|---|---|---|
| 0 | `PKTVALERR` | Log packet validation error; the FATALERR bit normally follows for the affected QP. |
| 1 | `MADRX` | QP1 MAD packet received. Track B: deliver to CM state machine. Tracks C/D: deliver to gateway/orchestrator. |
| 3 | `RNRNACKGEN` | ERNIC generated an RNR NACK (local RQ was empty). If RQOVFL sticks, treat as overflow. Log-only if transient. |
| 4 | `WQECOMPL` | Loop through `CQINTSTSn` banks 1..N, find set bits → QP IDs → for each, read `CQHEADi`, compare to `prev_cq_head`, read the new CQE(s) from DDR4 starting at `CQBAi + (prev_cq_head * 4)`, advance `prev_cq_head`, deliver to `ibv_poll_cq()` (Track B) or to the gateway handler (C) / orchestrator RPC return (D). W1C the bank bit. |
| 5 | `ILLOPCODE` | QP is heading to FATAL — same flow as bit 7. |
| 6 | `RQPKT` | RQ packet landed. Similar loop with `RQINTSTSn` banks. Track B only cares for SEND opcodes (RDMA WRITE/READ don't signal RQ). |
| 7 | `FATALERR` | Read `FATALERRBUFBA` → extract QPN from bits `[31:16]`, fatal code from `[15:0]` (PG332 line 3744–3746). Transition that QP to ERR → UNDER_RECOVERY (§5.6). |
| 8 | `CNPSCHD` | One-shot CC scheduled a CNP. Loop `CNPSCHDSTSn` banks. Track B: log and increment counter; do NOT alter QP state (§9). |

After handling, W1C the bit in INTSTS. Banks (`RQINTSTSn`, `CQINTSTSn`,
`CNPSCHDSTSn`) are also W1C per bank bit (PG332 line 1846, lines 2158+).

**IRQ → QP mapping helper** (F1 audit §5.4):
```
qpid_from_bank(bank_idx, bit)  = (bank_idx - 1) * 32 + bit
                                 except bank 1 bit 0 => qpid = C_NUM_QP (mgmt QP)
```

---

## 7. Who owns transitions — per track

| Transition / Event | Track B (`onic.ko` ibverbs) | Track C (gateway fw) | Track D (TT↔TT) |
|---|---|---|---|
| PD alloc | `ib_alloc_pd` → `ernic_pd_alloc` | gateway REQ `PD_ALLOC` handler | orchestrator RPC `pd.alloc` |
| MR register | `ib_reg_mr` → `ernic_mr_register` | gateway REQ `MR_REG` | orchestrator RPC `mr.reg` |
| CQ create/arm | `ib_create_cq` | gateway REQ `CQ_CREATE` | orchestrator RPC `cq.create` |
| QP create (RESET) | `ib_create_qp` | gateway REQ `QP_CREATE` | orchestrator RPC `qp.create` |
| RESET → INIT | `ib_modify_qp` w/ attr_mask=... (IB state INIT) | gateway REQ `QP_MODIFY` (local state=INIT) | orchestrator pair-config message |
| INIT → RTR | `ib_modify_qp` (IB state RTR; driver validates dest-QP/MAC/IP are present) | gateway exchanges with peer, then `QP_MODIFY` RTR | orchestrator distributes rendezvous info, issues RTR to both sides |
| RTR → RTS | `ib_modify_qp` (IB state RTS) | gateway sets RTS after peer confirms | orchestrator broadcasts RTS |
| Post WR | `ib_post_send` | gateway REQ `POST_SEND` forwards WQE | orchestrator-relayed `post` message; data path stays local once posted |
| Poll CQ | `ib_poll_cq` via IRQ (§6) | gateway REQ `POLL_CQ` OR async notification channel | orchestrator callback / event stream |
| FATAL handling | kernel workqueue runs `ernic_qp_handle_fatal` | gateway fw detects, retries or reports to host | orchestrator informs both peers, decides drop-vs-recover |
| Destroy | `ib_destroy_qp` | gateway REQ `QP_DESTROY` | orchestrator RPC `qp.destroy` |

**Key point: the state machine is shared.** Only the control surface — who
calls which driver entrypoint, and how the peer exchange is coordinated — is
track-specific. The register writes and the PG332-defined ordering constraints
are identical in all three.

---

## 8. Error recovery / drain semantics

### 8.1 Peer disappears mid-connection

- Retry-timeout path (PG332 line 4118–4126): `TIMEOUTCONFi` retry count
  decrements on each unacknowledged segment; when exhausted, `QPFATAL=1` fires
  and the driver runs §5.6. For Track B, surface this to the app as
  `IBV_WC_RETRY_EXC_ERR` on any outstanding CQEs (we fabricate the CQE since
  ERNIC may not post one for the failed WQE; FAE query).
- Track C/D: the gateway / orchestrator decides whether to reconnect (re-run
  RESET → INIT → RTR → RTS with a fresh PSN).

### 8.2 Retry exhaustion

See §5.5 row 2. Fatal code from `FATALERRBUFBA` base entry identifies
"retries-exhausted". Driver runs §5.6 unless app explicitly requested destroy.

### 8.3 CQ overflow

Fatal. Driver MUST allocate CQ depth ≥ SQ depth (IB requires this; ERNIC does
not, so enforce in the driver). Overflow implies driver bug or missed CQE
drain. Recovery requires QP destroy-and-recreate; §5.6 recovery does not
reopen CQ entries that were never posted.

### 8.4 Destroy drain guarantees

Per §5.7 steps 1–2 (PG332 lines 3712–3714): driver waits for both
`STATQPi[9] SQEMPTY` AND `STATQPi[10] OSTQEMPTY` AND `CQHEADi == SQPIi` before
clearing `QPEN`. This guarantees no in-flight WQE can stomp freed memory.

Timeout: driver caps the wait at `T = TIMEOUTCONFi_timeout × (max_retry + 1) ×
4` (a heuristic upper bound on retry settling). If exceeded, force-FATAL via
writing `QPCONFi[6]=1` and fall through §5.6 / then §5.7.

---

## 9. One-shot CC interaction

Track B scope B9 (see `rdma_production_full_stack.md`): observe-only.

- `INTSTS[8] CNPSCHD` fires when ERNIC schedules a CNP for a QP.
- Driver reads `CNPSCHDSTSn` banks to identify which QP (PG332 lines
  2437–2440).
- **No state-machine action.** The QP stays in RTS. ERNIC locally halves its
  outstanding-WQE window (the 16→8 one-shot mentioned in the caller's spec) —
  this is internal hardware behaviour, no CSR is written by the driver.
- Driver logs and increments a per-QP counter for ethtool.
- W1C the bank bit; move on.

Once a real Track B CC loop lands (post-Tier-2), this may expand to adjusting
`TIMEOUTCONFi` at runtime. Out of scope here.

---

## 10. Testing approach

### 10.1 Phase map

| Phase | Tests | Gates |
|---|---|---|
| **F7a** | Unit test the state enum transitions in userspace using the `ernic_lifecycle.h` header and a mock register backend. No hardware. | header compiles + enums cover PG332 flows |
| **F7b** | Integrate with `phase_f2_ernic_counters`: drive RESET→INIT→RTR→RTS via an ioctl shim in `onic.ko` (stubbed), verify `XRNIC_CONF_QP_EN` increments and `QPEN` asserts on the actual FPGA. No data-plane traffic yet. | hardware register inspection via F2 probes |
| **F7c** | Scapy injector sends a SEND to our QP, verify `INTSTS[6] RQPKT` + `RQINTSTSn` bank bit + RQ write pointer advances. Exercises the RQ/RX half of §5.4. | packet arrives + status bits match |
| **F7d** | Loopback small RDMA_WRITE from another ERNIC-enabled FPGA (or phase_f2 test harness). Verify `CQHEADi` increments and `INTSTS[4] WQECOMPL` fires. Test CQ polling loop (§4.4). | CQE read + CQINTSTSn cleared |
| **F7e** | Inject a fatal (invalid R_KEY in a remote WRITE); verify transition to ERR, run §5.6 recovery, verify re-enter RTS and next WQE completes. | fatal-buffer entry read, recovery completes, next CQE lands |
| **F7f** | Destroy path — post N WQEs, wait drain, destroy QP, verify all registers zeroed and `XRNIC_CONF_QP_EN` decrements. | `STATQPi == 0` post-destroy |

### 10.2 Concrete phase test names (for CI)

- `phase_f7a_lifecycle_unit`
- `phase_f7b_qp_enable`
- `phase_f7c_send_rx`
- `phase_f7d_write_cq`
- `phase_f7e_fatal_recovery`
- `phase_f7f_destroy_drain`

Each one keyed off the state transitions in §5 so regressions are localized.

---

## 11. Open questions (FAE queries)

1. `XRNIC_CONF_QP_EN` (0x10_0044, 12-bit): count vs. mask? F1 audit §6.2 flags
   this. Affects §5.4 step 2.
2. Does ERNIC post a synthetic CQE on retry-exhaustion, or is the only
   indicator `FATALERRBUFBA` + `STATQPi[22:16]`? Affects §8.1 error surfacing.
3. In-flight inbound RDMA-WRITE during MR deregister — see §3.4. Safe drain
   interval?
4. `RESPHNDSTS[16]` (polled in §5.6 drain phase steps 4, 7): PG332 calls this
   "sq pici db check en" but doesn't document the register offset in the
   sections we've read. Need Xilinx confirmation of both its offset and bit
   definition before F7e can be implemented.
5. `STATMSN` offset — F1 audit §4 flags the GCSR alias as misleading but
   neither it nor PG332 Table 8 (as extracted) shows the canonical per-QP
   offset. Verify before §5.7 step 4 and §5.6 step 7.

---

*Doc owner: RDMA track working group. Last touch 2026-04-23 alongside F1
register-map audit. Cross-references: `f1_register_map_audit.md`,
`rdma_production_full_stack.md` §B.*
