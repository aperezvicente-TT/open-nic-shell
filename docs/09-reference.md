# Chapter 9 — Reference: Registers, Offsets & Bit-fields

A consolidated lookup for everything numeric in the design. All offsets are relative to
**PCIe BAR2** unless stated otherwise. Source citations point at the authoritative file.

## 9.1 Build parameters (this NIC)

| Parameter | Value | Set by |
|-----------|-------|--------|
| `NUM_PHYS_FUNC` | 1 | `-num_phys_func 1` |
| `NUM_QDMA` | 1 | (default) |
| `NUM_CMAC_PORT` | 2 | `-num_cmac_port 2` |
| `NUM_QUEUE` | 2048 | `-num_queue 2048` |
| `MAX_PKT_LEN` | 9600 | `-max_pkt_len 9600` |
| `PKT_CAP` | 16 | `-pkt_cap 16` |
| `EXT_QID` | 1 | hardcoded, `open_nic_shell.sv:745` |
| `PER_CMAC_QUEUES` | 64 | plugin localparam + driver `ONIC_PER_CMAC_QUEUES` |
| Board / part | au200 / `xcu200-fsgd2104-2-e` | `-board au200` |
| Validated build-stamp | `0x07010922` | `BUILD_STATUS` @ BAR2 `0x0` |

## 9.2 BAR2 top-level address map

Source: `src/system_config/system_config_address_map.sv:255–281`.

| Base | Range | Target |
|------|-------|--------|
| `0x00000` | 0x00FFF | System configuration |
| `0x01000` | 0x05FFF | QDMA subsystem #0 |
| `0x08000` | 0x0AFFF | CMAC subsystem #0 |
| `0x0B000` | 0x0BFFF | Packet adapter #0 |
| `0x0C000` | 0x0EFFF | CMAC subsystem #1 |
| `0x0F000` | 0x0FFFF | Packet adapter #1 |
| `0x10000` | 0x11FFF | Sysmon |
| `0x12000` | 0x16FFF | QDMA subsystem #1 (dummy when `NUM_QDMA==1`) |
| `0x18000` | 0x1AFFF | PTP subsystem |
| `0x100000` | 0x1FFFFF | **Box0 @ 250 MHz** (plugin + diag counters) |
| `0x200000` | 0x2FFFFF | Box1 @ 322 MHz |
| `0x300000` | 0x33FFFF | Card Management System |
| `0x340000` | 0x340FFF | QSPI |

**CMAC stride = `0x4000`** (CMAC *i* @ `0x8000 + i·0x4000`). The driver must reproduce
this exactly (Ch. 5 §5.4).

## 9.3 System-config registers

Source: `onic_register.h:43–50` (offsets from `0x0`).

| Register | Offset | Notes |
|----------|--------|-------|
| BUILD_STATUS | `0x00` | build stamp; validated = `0x07010922` |
| SYSTEM_RESET | `0x04` | |
| SYSTEM_STATUS | `0x08` | |
| SHELL_RESET | `0x0C` | bit0 = QDMA, bit4 = CMAC0, bit8 = CMAC1, bit12/13 = ERNIC0/1 |
| SHELL_STATUS | `0x10` | |
| USER_RESET | `0x14` | |
| USER_STATUS | `0x18` | |
| LINK_IRQ_STATUS | `0x1C` | |

## 9.4 QDMA per-function registers

Source: `onic_register.h:53–61`. `QDMA_FUNC_OFFSET(i) = 0x1000 + 0x1000·i`.

| Register | Offset | Fields |
|----------|--------|--------|
| `QCONF(i)` | `QDMA_FUNC_OFFSET(i) + 0x0` | `QBASE = [31:16]`, `NUMQ = [15:0]` |
| `INDIR_TABLE(i,k)` | `+0x400 + 4k` | RSS indirection (unused under `EXT_QID=1`) |
| `HASH_KEY(i,k)` | `+0x600 + 4k` | Toeplitz key |

## 9.5 Per-CMAC registers

Relative to `CMAC(i) = 0x8000 + i·0x4000`. Sub-blocks: `QSFP +0x2000`, `ADPT +0x3000`.
Source: `onic_register.h:78–276`.

| Register | Offset | Notes |
|----------|--------|-------|
| GT_RESET | `0x0000` | |
| RESET | `0x0004` | |
| CONF_TX_1 | `0x000C` | |
| CONF_RX_1 | `0x0014` | |
| CORE_VERSION | `0x0024` | must read `0x00000301` (num_cmacs detect) |
| CONF_RX_FC_CTRL_1/2 | `0x0084/0x0088` | flow control |
| GT_LOOPBACK | `0x0090` | |
| RSFEC_CONF_ENABLE | `0x107C` | |
| STAT_RX_STATUS | `0x0204` | **bit0 = RX aligned** |
| STAT_RSFEC_STATUS | `0x1004` | |
| ADPT recv/drop/error | `0x3000 + {0x0,0x10,0x20,0x30,0x40}` | packet counters |

## 9.6 Plugin diagnostic counters

Source: `eth_2cmac_1pf_250mhz.sv:508–577`. Absolute BAR2 = `0x100000 + offset`.
18 free-running 32-bit counters; clear only on datapath reset.

| Offset | Abs | idx | Counter | Counts |
|--------|-----|-----|---------|--------|
| `0x00` | `0x100000` | 0 | RX0_adap_in | CMAC0 wire RX into adapter |
| `0x04` | `0x100004` | 1 | (tied 0) | ex-classifier |
| `0x08` | `0x100008` | 2 | (tied 0) | ex-filter→rdma |
| `0x0C` | `0x10000C` | 3 | (tied 0) | ex-filter→host |
| `0x10` | `0x100010` | 4 | RX0_arb_in | CMAC0 FIFO → arbiter |
| `0x14` | `0x100014` | 5 | RX0_qdma_c2h | C2H out, source = CMAC0 |
| `0x18` | `0x100018` | 6 | RX1_adap_in | CMAC1 wire RX into adapter |
| `0x1C` | `0x10001C` | 7 | (tied 0) | |
| `0x20` | `0x100020` | 8 | (tied 0) | |
| `0x24` | `0x100024` | 9 | (tied 0) | |
| `0x28` | `0x100028` | 10 | RX1_arb_in | CMAC1 FIFO → arbiter |
| `0x2C` | `0x10002C` | 11 | RX1_qdma_c2h | C2H out, source = CMAC1 |
| `0x30` | `0x100030` | 12 | TX0_h2c_demux | H2C → CMAC0 (sel==0) |
| `0x34` | `0x100034` | 13 | TX1_h2c_demux | H2C → CMAC1 (sel==1) |
| `0x38` | `0x100038` | 14 | TX0_adap_out | out to CMAC0 TX adapter |
| `0x3C` | `0x10003C` | 15 | TX1_adap_out | out to CMAC1 TX adapter |
| `0x40` | `0x100040` | 16 | RX_MARK_MISMATCH | trip-wire (should be 0) |
| `0x44` | `0x100044` | 17 | TX_QID_CHANGED | trip-wire (should be 0) |

## 9.7 qid bit-field layout (the steering key)

Absolute qid is 11 bits. Split at `QID_LO_W = 6`:

```
 [10 .. 7] [ 6 ] [ 5 .. 0 ]
  unused    sel   intra-CMAC index (0..63)

 CMAC-select = qid[6 +: SEL_W]   (SEL_W = 1 for 2 CMACs)
 CMAC i owns absolute qid range [i·64, (i+1)·64)
```

| Abs qid | CMAC | Netdev |
|---------|------|--------|
| 0 … 63 | CMAC0 | `enp1s0` (dev_port 0) |
| 64 … 127 | CMAC1 | `enp1s0d1` (dev_port 1) |

## 9.8 AXI-Stream TUSER layouts

| Location | Width | Layout (MSB→LSB) | Source |
|----------|-------|------------------|--------|
| H2C function slice | 27 | `{qid[10:0], size[15:0]}` | `qdma_subsystem_function.sv:252` |
| H2C IP-side slice | 49 | `{mdata[31:16], mdata[15:0], mty[5:0], qid[10:0]}` | `qdma_subsystem_h2c.sv:67` |
| C2H function slice / clk-conv | 107 | `{qid[10:0], ptp_ts[79:0], size[15:0]}` | `qdma_subsystem_function.sv:379` |
| C2H buf_fifo | 27 | `{qid[10:0], size[15:0]}` | `qdma_subsystem_function.sv:581` |
| C2H completion slice | 107 | `{ptp_ts[79:0], size[15:0], qid[10:0]}` | `qdma_subsystem_c2h.sv:159` |
| Plugin RX FIFO | 123 | `{qid[10:0], ptp_ts[79:0], src[15:0], size[15:0]}` | `eth_2cmac_1pf_250mhz.sv:377` |
| C2H ECC qid field | — | `c2h_ecc_data[26:16] = qid[10:0]` | `qdma_subsystem_c2h.sv:215` |
| (dead) Option B qid | 11 | `{2'b0, port_id[2:0], qid[5:0]}` | `qdma_subsystem_function.sv:232` |

> Note the two 107-bit C2H slices differ in field *order* (`{qid,ptp_ts,size}` vs
> `{ptp_ts,size,qid}`) — each is internally self-consistent (pack matches unpack).

## 9.9 Bench topology (validated)

| | CMAC0 | CMAC1 |
|--|-------|-------|
| Netdev / dev_port | `enp1s0` / 0 | `enp1s0d1` / 1 |
| Local IP | `10.99.0.1/24` | `10.99.1.1/24` |
| Local MAC | `00:0a:35:b8:01:00` | `00:0a:35:b8:01:01` |
| Peer host | `10.140.64.221` | `10.140.64.223` |
| Peer IP | `10.99.0.2` | `10.99.1.2` |
| Peer MAC | `10:70:fd:d6:9d:58` | `10:70:fd:d6:9d:20` |
| Peer netdev | `enp2s0np0` | `enp2s0np0` |

PCIe BDF `0000:01:00.0`, device `10ee:903f`, single PF. **Netdev names/MACs/BDF change
with the PCIe slot** — re-verify after any card move (Ch. 7 §7.8, Ch. 8 §8.3).

## 9.10 Git provenance

| Repo | Branch | HEAD | Key commits |
|------|--------|------|-------------|
| open-nic-shell | `feature/eth-1pf-2cmac-qid` | `1781c4f` | `c116e90` graft, `32f89a4` byte-lock, `1781c4f` clamp fix (reverts Option B `9d4fd6a`) |
| open-nic-driver | `feature/eth-dual-netdev-1pf` | `274de0c` | `dda0ea7` RDMA strip, `274de0c` num_cmacs stride fix |

Both pushed to `github.com/aperezvicente-TT/open-nic-{shell,driver}`.
