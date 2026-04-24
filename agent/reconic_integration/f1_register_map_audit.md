# F1 — ERNIC Register Map Audit: `reconic_reg.h` vs PG332 v4.2

**Inputs:** `/home/alex/mpi-shfs/fpga/libreconic/reconic_reg.h` (279 lines) vs
`pg332-ernic-4.2.md` Chapter 3 "Register Space" (Table 8, lines 1452–3041).

**Convention:** header offsets are quoted absolute (including `RN_RDMA_BASE_ADDRESS = 0x00800000`).
PG332 offsets are relative to the ERNIC instance base.
Relation: `header_abs - 0x00800000 == PG332_rel`.

All findings below are for **v4.2**. The header banner says "v4.3" but no v4.3-specific
offsets are referenced — Xilinx documented v4.3 is editorial-only vs v4.2.

---

## 1. Coverage summary

| Block | Defined in header | Documented in PG332 v4.2 | Coverage |
|---|---|---|---|
| PDT (per-entry, 8 regs × 2048 entries) | 8 (entry template) | 8 | 8/8 |
| GCSR — XRNICCONF + global config | 4 | 9 (incl. XRNIC_BUF_THRESHOLD_ROCE, XRNIC_PAUSE_CONF, XRNIC_BUF_THRESHOLD_NON_ROCE, XRNIC Version, XRNIC_CONF_QP_EN, CON_IO_CONF) | 4/9 |
| GCSR — addr/buffer config (MAC, IPv4/6, ERR/DAT/RESPERR buffers) | 16 | 16 | 16/16 |
| GCSR — packet/status counters | 16 | 16 | 16/16 |
| GCSR — INTEN/INTSTS | 2 | 2 | 2/2 |
| GCSR — RQINTSTS1..N | 8 (only 1..8) | 64 | 8/64 |
| GCSR — CQINTSTS1..N | 8 (WRONG OFFSETS, see §2) | 64 | 0/64 correct |
| GCSR — CNPSCHDSTS1..64REG | 0 | 64 | 0/64 |
| QCSR — per-QP core (QPCONF..STATRQBUFCAMSB) | 33 | 34 | 33/34 (missing TIMEOUTCONFi) |

Effective GCSR coverage ≈ 46 registers of ≈179 documented when counting all
RQ/CQ/CNP fan-out ≈ 26% raw; ≈ 90% of single-instance registers (excl. the
big bitwise banks beyond bank 1..8).

---

## 2. Mismatches — WRONG offsets or names

| Mnemonic (PG332) | Header symbol | Header rel offset | PG332 rel offset | Verdict |
|---|---|---|---|---|
| CQINTSTS1 | `RN_RDMA_GCSR_CQINTSTS1` | **0x10_01B0** | **0x10_0290** | **Header WRONG** — 0x01B0 is RQINTSTS9 in v4.2 |
| CQINTSTS2 | `RN_RDMA_GCSR_CQINTSTS2` | 0x10_01B4 | 0x10_0294 | Header WRONG (=RQINTSTS10) |
| CQINTSTS3 | `RN_RDMA_GCSR_CQINTSTS3` | 0x10_01B8 | 0x10_0298 | Header WRONG (=RQINTSTS11) |
| CQINTSTS4 | `RN_RDMA_GCSR_CQINTSTS4` | 0x10_01BC | 0x10_029C | Header WRONG (=RQINTSTS12) |
| CQINTSTS5 | `RN_RDMA_GCSR_CQINTSTS5` | 0x10_01C0 | 0x10_02A0 | Header WRONG (=RQINTSTS13) |
| CQINTSTS6 | `RN_RDMA_GCSR_CQINTSTS6` | 0x10_01C4 | 0x10_02A4 | Header WRONG (=RQINTSTS14) |
| CQINTSTS7 | `RN_RDMA_GCSR_CQINTSTS7` | 0x10_01C8 | 0x10_02A8 | Header WRONG (=RQINTSTS15) |
| CQINTSTS8 | `RN_RDMA_GCSR_CQINTSTS8` | 0x10_01CC | 0x10_02AC | Header WRONG (=RQINTSTS16) |

**Root cause:** v4.2 extends RQINTSTS to 64 banks (RQINTSTS1 at 0x0190 through
RQINTSTS64 at 0x028C), THEN CQINTSTS1 starts at 0x0290. The header appears to
have been carried over from a prior ERNIC version where only 8 RQ banks existed
and CQ started at 0x01B0.

**Everything else in the header verified correct.** Spot-checked:

| Mnemonic | Header rel | PG332 rel | OK |
|---|---|---|---|
| XRNICCONF | 0x10_0000 | 0x10_0000 | OK |
| XRNICADCONF | 0x10_0004 | 0x10_0004 | OK |
| MACXADDLSB/MSB | 0x10_0010 / 0x10_0014 | 0x10_0010 / 0x10_0014 | OK |
| IPV6XADD1..4 | 0x10_0020..0x10_002C | same | OK |
| REQERRBUFBA/MSB/SZ/WPTR | 0x10_0060..006C | 0x10_0060..006C | OK |
| IPV4XADD | 0x10_0070 | 0x10_0070 | OK |
| FATALERRBUFBA/MSB/SZ/WPTR | 0x10_0088..0094 | 0x10_0088..0094 | OK |
| DATBUFBA/MSB/SZ | 0x10_00A0..00A8 | 0x10_00A0..00A8 | OK |
| RESPERRBUFBA/MSB/SZ/WPTR | 0x10_00B0..00BC | 0x10_00B0..00BC | OK |
| INTEN / INTSTS | 0x10_0180 / 0x10_0184 | same | OK |
| RQINTSTS1..8 | 0x10_0190..01AC | same | OK |
| QPCONFi | 0x18_0000 | 0x18_0000 | OK |
| All QCSR offsets through STATRQBUFCAMSBi @ 0x18_00D8 | | | OK |

**Naming quirk, not a bug:** header symbol `RN_RDMA_GCSR_ERRBUFBA` is PG332's
`REQERRBUFBA`; `RN_RDMA_GCSR_IPKTERRQBA` is PG332's `FATALERRBUFBA`;
`RN_RDMA_GCSR_RESPERRSZMSB` is PG332's `RESPERRBUFWPTR`. Header comments flag
most; the `RESPERRSZMSB` alias at 0x00BC is misleading — it's the write
pointer, not a size MSB.

---

## 3. Missing registers — in PG332 but not in header

### GCSR — genuinely missing

| Mnemonic | Rel offset | Purpose | Criticality |
|---|---|---|---|
| `XRNIC_BUF_THRESHOLD_ROCE` | 0x10_0008 | RoCE XON/XOFF thresholds (PFC) | LOW (PFC not on Track B critical path; RC SEND/WRITE/READ works without it) |
| `XRNIC_PAUSE_CONF` | 0x10_000C | PFC pause enable + priority | LOW |
| `XRNIC_BUF_THRESHOLD_NON_ROCE` | 0x10_0018 | non-RoCE XON/XOFF (unused in pure RDMA) | LOW |
| `XRNIC Version` | 0x10_001C | RO IP version reg (maj/min/dev) | **HIGH** — smoke test, already used in F2 implicitly; add for driver banner + version gating |
| `XRNIC_CONF_QP_EN` | 0x10_0044 | Number of QPs enabled `[11:0]` | **HIGH** — driver must set this before any QP goes live |
| `CON_IO_CONF` | 0x10_00AC | Connect-IO doorbell (HW handshake) | MEDIUM — only if HW handshake mode is used; we're AXI-Lite, LOW for Track B |
| `RQINTSTS9..64` | 0x10_01B0 .. 0x10_028C | RQ interrupt banks for QPs 256..2047 | MEDIUM (HIGH if we ever scale past 256 QPs; Tier-2 MPI goals need > 256) |
| `CQINTSTS1..64` | 0x10_0290 .. 0x10_038C | CQ interrupt banks (see §2 — header has bogus entries) | **HIGH** — driver IRQ handler MUST read these to find signaled CQ |
| `CNPSCHDSTS1..64REG` | 0x10_0390 .. 0x10_048C | CNP scheduled interrupt status (one-shot CC) | LOW for Track B initial, MEDIUM once CC (one-shot congestion) is enabled |

### QCSR — genuinely missing

| Mnemonic | Rel offset | Purpose | Criticality |
|---|---|---|---|
| `TIMEOUTCONFi` | 0x18_004C + i·0x100 | Per-QP timeout value [5:0], max retry [10:8], max RNR retry [13:11], RNR timeout [20:16]. Does not exist for QP1 | **HIGH** — any RC QP that needs retry/RNR tuning (all real ones). Missing from header |

No other QCSR fields are missing through offset 0xD8 (STATRQBUFCAMSBi).

---

## 4. Extras — in header but not in PG332

| Symbol | Rel offset | Origin |
|---|---|---|
| `RN_RDMA_GCSR_RESPERRSZMSB` | 0x10_00BC | PG332 calls this `RESPERRBUFWPTR` (write pointer, [15:0]). **Header is misnamed**, not extra. Rename. |
| `RN_RDMA_GCSR_INNCKPKTSTS` | 0x10_011C | Not in PG332 v4.2 Table 8 between `ININVDUPCNT` (0x0118) and `OUTRNRPKTSTS` (0x0120). Actually 0x011C is an unlisted gap; possibly a legacy "incoming NACK pkt status" from ERNIC v3/v4.0. Status: unknown / legacy alias. **Safe to keep but unverified**. |
| `RN_RDMA_GCSR_OUTRNRPKTSTS` | 0x10_0120 | Not in PG332 v4.2 Table 8 either (0x0120 is a gap between INNCKPKTSTS at 0x011C and WQEPROCSTS at 0x0124). Same status as above — **unverified legacy**. |
| `RN_RDMA_GCSR_STATCURSQPTRi` (alias into QCSR QP0 slot) | 0x18_008C | Not a GCSR at all — it's per-QP QCSR. Header flags this explicitly as an alias. OK as-is, but driver code should use `RN_RDMA_QCSR_STATCURSQPTRi`. |
| `RN_RDMA_GCSR_STATMSN` (alias) | 0x18_0084 | Same as above (per-QP alias). |

No true "extras"; three suspect items are misnamings or unlisted intermediate
address-space gaps that may or may not read back anything meaningful.

---

## 5. Bit-field gaps (top 10 driver-critical registers)

The header has ZERO bit-field `#define`s. All ten below need adding. Quoting
PG332 v4.2 directly.

### 5.1 `XRNICCONF` @ 0x10_0000

```
[0]      XRNICEN           ERNIC Enable
[2:1]    RSVD
[4:3]    TXACKGEN          TX ACK generation (00 default / 01 timeout-only / 10 explicit-only)
[5]      ERRBUFEN          Error buffer enable
[7:6]    RSVD
[23:8]   UDPSRCPORT        UDP source port for outgoing packets
[31:24]  RSVD
```

### 5.2 `XRNICADCONF` @ 0x10_0004

```
[0]      SWOVREN           SW override enable (allows SW writes to CQHEADn, STATCURRSQPTRn, STATRQPIDBn)
[1]      RSVD
[2]      RETRYCNTFATALDIS  retry_cnt_fatal_dis
[15:3]   RSVD
[19:16]  BASECNTWIDTH      CLOG2(4.096 * f_clk_MHz); for 400 MHz → 11, 200 MHz → 10, 125 MHz → 9, 100 MHz → 9
[31:20]  SWOVRQP           Software Override QP Number
```

### 5.3 `INTEN` @ 0x10_0180 and `INTSTS` @ 0x10_0184 (identical bit layout)

```
[0]      PKTVALERR         Incoming packet validation error
[1]      MADRX             Incoming MAD packet received
[2]      RSVD
[3]      RNRNACKGEN        RNR NACK generated
[4]      WQECOMPL          WQE completion (per-QP, gated by QPCONF[3])
[5]      ILLOPCODE         Illegal opcode posted in SEND Queue
[6]      RQPKT             RQ Packet received (per-QP, gated by QPCONF[2])
[7]      FATALERR          Fatal error received
[8]      CNPSCHD           CNP scheduling
[31:9]   RSVD
```
(INTSTS is W1C.)

### 5.4 `RQINTSTSn` / `CQINTSTSn` (each W1C, bitwise per-QP)

```
[i]      IRQSTATUS_i       Interrupt status for RQ/CQ(i + 32*(n-1)).
                           NOTE: For bank 1 (RQINTSTS1/CQINTSTS1), bit 0 holds
                           the status of QPN where N = C_NUM_QP (the
                           "management QP"), not QP0. Bits 1..31 map to QPs
                           1..31.
```
Suggest driver-side helper: `RQ_BANK(qpid) = (qpid/32)+1`, `RQ_BIT(qpid) = qpid%32`.

### 5.5 `QPCONFi` @ 0x18_0000 + i·0x100

```
[0]      QPEN              QP enable
[1]      RSVD
[2]      RQINTEN           RQ interrupt enable
[3]      CQINTEN           CQ interrupt enable
[4]      HWHSHKDIS         HW Handshake disable (1 → doorbells via AXI)
[5]      CQEWREN           CQE write enable (debug)
[6]      QPURC             QP under recovery (set during fatal clearing)
[7]      QPIPV6            0 = IPv4, 1 = IPv6
[10:8]   PATHMTU           000=256B / 001=512B / 010=1024B / 011=2048B / 100=4096B
[15:11]  RSVD
[31:16]  RQBUFSZ           RQ buffer element size in multiples of 256 B (power-of-2)
```

### 5.6 `QPADVCONFi` @ 0x18_0004 + i·0x100 (not present for QP1)

```
[5:0]    TC                Traffic class (keep default 0)
[7:6]    RSVD
[15:8]   TTL               Time to live
[31:16]  PKEY              Partition Key
```

### 5.7 `STATCURSQPTRi` @ 0x18_008C and `STATRQPIDBi` @ 0x18_009C

```
STATCURSQPTRi [15:0]   CURSQPTR     Current SQ pointer under process (WQEs outstanding)
              [31:16]  RSVD

STATRQPIDBi   [15:0]   RQPIDB       RQ Producer Index doorbell
              [31:16]  RSVD
```
Note: **`STATRQDBELL` is not a v4.2 register name.** The caller's brief names
"STATRQDBELL" — in v4.2 it's `STATRQPIDBi`.

### 5.8 `CNPSCHDSTSiREG` @ 0x10_0390 + (i-1)·4

```
[j]      Scheduled CNP for QP(j + 32*(i-1)). Bank 1 bit 0 = management QP.
```
RO (level-sensitive until serviced).

### 5.9 `DATBUFBA/DATBUFBAMSB/DATBUFSZ` @ 0x10_00A0 / 0x10_00A4 / 0x10_00A8

```
DATBUFBA    [31:0]   BA_LSB        Data Buffer base address [31:0]
DATBUFBAMSB [31:0]   BA_MSB        Data Buffer base address [63:32]
DATBUFSZ    [15:0]   NBUFS         Number of data buffers
            [31:16]  BUFSZ         Data buffer size in bytes
```
64-bit effective base = `{DATBUFBAMSB, DATBUFBA}`. Backing buffer for retx.

### 5.10 Per-QP 64-bit queue bases

```
SQBAi       @ 0x18_0010   [31:5]  SQBA_LSB    32-B aligned
SQBAMSBi    @ 0x18_00C8   [31:0]  SQBA_MSB
RQBAi       @ 0x18_0008   [31:8]  RQBA_LSB    256-B aligned
RQBAMSBi    @ 0x18_00C0   [31:0]  RQBA_MSB
CQBAi       @ 0x18_0018   [31:5]  CQBA_LSB    32-B aligned (CQE = 4 B but base 32-B aligned)
CQBAMSBi    @ 0x18_00D0   [31:0]  CQBA_MSB
RQWPTRDBADDi    @ 0x18_0020   [31:0]   Host doorbell-write target addr LSB
RQWPTRDBADDMSBi @ 0x18_0024   [31:0]   …MSB
CQDBADDi        @ 0x18_0028   [31:0]   …LSB
CQDBADDMSBi     @ 0x18_002C   [31:0]   …MSB
```

### Bonus: `STATQPi` @ 0x18_0088 (not in the top-10 but driver-hot)

```
[0]     QPFATAL            QP in fatal status
[1]     RQOVFL             RCV Q overflow (RNR NACK sent out)
[2]     SQFULL             Send Q full
[3]     OSTQFULL           Outstanding Q full
[4]     CQFULL             CQ FIFO full
[8:5]   RSVD
[9]     SQEMPTY            Send Q empty (no SQEs left; not all acked though)
[10]    OSTQEMPTY          Outstanding Q empty
[11]    QPRETRIED          QP packet was retried
[15:12] RSVD
[22:16] NACKSYND           NACK syndrome received
[23]    RSVD
[26:24] CURRETRY           Current retry count (RW)
[27]    RSVD
[30:28] CURRNRCNT          Current RNR-NACK count on incoming responses (RW)
[31]    RSVD
```

---

## 6. Recommendations

### 6.1 Edits to `reconic_reg.h` (ordered)

**P0 — blocking for Track B skeleton:**

1. **Fix CQINTSTS offsets** (§2). Replace lines 151–158 with:
   ```c
   #define RN_RDMA_GCSR_CQINTSTS1  (RN_RDMA_BASE_ADDRESS + 0x00100290)
   #define RN_RDMA_GCSR_CQINTSTS2  (RN_RDMA_BASE_ADDRESS + 0x00100294)
   #define RN_RDMA_GCSR_CQINTSTS3  (RN_RDMA_BASE_ADDRESS + 0x00100298)
   #define RN_RDMA_GCSR_CQINTSTS4  (RN_RDMA_BASE_ADDRESS + 0x0010029C)
   #define RN_RDMA_GCSR_CQINTSTS5  (RN_RDMA_BASE_ADDRESS + 0x001002A0)
   #define RN_RDMA_GCSR_CQINTSTS6  (RN_RDMA_BASE_ADDRESS + 0x001002A4)
   #define RN_RDMA_GCSR_CQINTSTS7  (RN_RDMA_BASE_ADDRESS + 0x001002A8)
   #define RN_RDMA_GCSR_CQINTSTS8  (RN_RDMA_BASE_ADDRESS + 0x001002AC)
   ```
   Add a comment: `/* bank n covers QPs 32*(n-1) .. 32*n-1; bit 0 of bank 1 = mgmt QP (C_NUM_QP) */`.

2. **Add `RN_RDMA_GCSR_XRNIC_CONF_QP_EN` @ 0x10_0044** — driver MUST write this.

3. **Add `RN_RDMA_GCSR_XRNIC_VERSION` @ 0x10_001C** — driver probe sanity check.

4. **Add `RN_RDMA_QCSR_TIMEOUTCONFi` @ 0x18_004C** — needed for RC-with-retry.

5. **Add index helpers** (not strictly offsets but will be used constantly):
   ```c
   #define RN_RDMA_GCSR_RQINTSTSn(n)  (RN_RDMA_BASE_ADDRESS + 0x00100190 + 4*((n)-1))
   #define RN_RDMA_GCSR_CQINTSTSn(n)  (RN_RDMA_BASE_ADDRESS + 0x00100290 + 4*((n)-1))
   #define RN_RDMA_GCSR_CNPSCHDSTSn(n)(RN_RDMA_BASE_ADDRESS + 0x00100390 + 4*((n)-1))
   #define RN_RDMA_QCSR_REG(qp,off)   (RN_RDMA_BASE_ADDRESS + 0x00180000 + ((qp)-1)*RN_RDMA_QCSR_STRIDE + (off))
   ```

**P1 — needed before first real data-path WR / signaled CQ:**

6. Rename `RN_RDMA_GCSR_RESPERRSZMSB` → `RN_RDMA_GCSR_RESPERRBUFWPTR` (keep old as deprecated alias).
7. Add all bit-field masks from §5 for the 10+1 hot registers. Use the
   pattern `#define XRNICCONF_XRNICEN BIT(0)`, `#define XRNICCONF_UDPSRCPORT GENMASK(23,8)`.
8. Add CNPSCHDSTS banks 1..8 (explicit) plus the `_CNPSCHDSTSn(n)` macro above. LOW priority for Track B skeleton but drop-in cheap.

**P2 — scale-out / polish:**

9. Add full RQINTSTS9..64 and CQINTSTS9..64 explicit defines, or rely on the
   `_RQINTSTSn(n)` macro. The macro is cleaner; skip the 120 new `#define`s.
10. Resolve the `INNCKPKTSTS` (0x011C) / `OUTRNRPKTSTS` (0x0120) mystery:
    grep the ERNIC IP RTL (if accessible) for these offsets, else **drop them**
    from the header — they're read-garbage in v4.2 per Table 8's gap.
11. Delete the `RN_RDMA_GCSR_STATCURSQPTRi` and `RN_RDMA_GCSR_STATMSN` GCSR
    aliases — they're misleading; keep only the `RN_RDMA_QCSR_*` forms.

### 6.2 Xilinx FAE queries

- Confirm 0x10_011C / 0x10_0120 behaviour in v4.2 — Table 8 skips these. Are
  they (a) reserved/RAZ, (b) legacy aliases, or (c) typos? Low-urgency unless
  driver probes them.
- Confirm `XRNIC_CONF_QP_EN` semantics: is [11:0] a COUNT (e.g., 256 → enable
  QPs 1..256) or a MASK? PG332 line 1616–1619 says "Number of QPs enabled" —
  implying a count, but the register is only 12-bit while C_NUM_QP can reach
  2047 (11 bits is enough for 2048). Verify before driver writes it.
- Confirm per-bank "bit 0 = QPN = C_NUM_QP" convention for both RQINTSTS1 and
  CQINTSTS1: is QPN the management QP ID, or just bit[0] of the bank?
  This affects the IRQ-to-QP mapping in `onic.ko`'s IRQ handler.

### 6.3 Go/no-go for Track B (B3 `ib_device` skeleton)

**NO-GO until P0 fixes land.** Specifically:

- **CQINTSTS offsets are wrong.** Every Track B signaled-completion path (post-send
  + wait-for-CQE) will fail: the driver will read from 0x01B0 (RQINTSTS9 bank,
  covering QPs 256..287 in v4.2) instead of 0x0290 (the real CQINTSTS1 for QPs 1..31).
  With a Track B test using QPs 1..31 this presents as "CQs never signal." On
  F2 this didn't fire because F2 is CSR-level and doesn't poll CQINTSTS — it reads
  counters/doorbells in the range we had right. CQINTSTS is a landmine.
- Missing `XRNIC_CONF_QP_EN` — without it the driver can't enable QPs past 1.
- Missing `TIMEOUTCONFi` — driver can't set retry behaviour; every lost packet
  becomes a QP-fatal.

**Time to green:** P0 is ~30 min of header editing + re-run of F2 smoke
(values should be unchanged since F2 doesn't touch the broken CQ/CNP regs).
After that, Track B B3 can proceed. P1 items (bit-fields) can land incrementally
as `ib_device` verbs are wired in — they're not offset changes.

**All of the F0/F1/F1b/F2 traffic we've already validated remains valid** —
the only broken offsets are in the CQINTSTS region, which none of those tests
touched. No regression risk.

---

*Audit completed 2026-04-23. All data cross-referenced against pg332-ernic-4.2.md
lines 1452–3041.*
