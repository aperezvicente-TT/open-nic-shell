# tt_link_udp_bridge Architecture

## 1. Overview

The `tt_link_udp_bridge` plugin is an open-nic-shell plugin that implements a
bidirectional gateway between a Tenstorrent TT-link Ethernet fabric and a
standard 100G UDP/IP network.  A Tenstorrent Blackhole (BH) chip attached to
CMAC0 sends and receives frames with EtherType 0x1AF4 (the TT-link protocol).
The plugin translates those frames to and from standard IPv4/UDP frames
(EtherType 0x0800) that travel on CMAC1, the network-facing 100G port.  This
lets a BH chip communicate with any UDP/IP endpoint over a commodity network
without any modification to the BH chip's Ethernet MAC.  The plugin is
implemented entirely in the 250 MHz AXI-Stream clock domain and exposes a
32-bit AXI-Lite register interface for configuration and statistics.

---

## 2. Data-Path Diagram

All AXI-Stream buses are 512 bits wide (64 bytes/beat) running at 250 MHz.
`tuser_size` carries the total byte length of the frame on each bus.

```
                              TT -> NET  (TX direction)
  +-----------+  512b/250MHz  +--------------------+  512b/250MHz  +--------------------+  512b/250MHz
  |  CMAC0 RX |-------------->| tt_link_classifier |-------------->|   udp_encap_tx     |-------------->  CMAC1 TX
  |  (BH-facing)|             | EtherType 0x1AF4   |  (TT frames) | prepend Eth+IPv4+  |
  +-----------+               | filter / drop       |              | UDP (42B), +28B    |
                              +--------------------+              | per frame, cksum   |
                                                                   +--------------------+
                                                                   cfg: local_mac, peer_mac,
                                                                        local_ip, peer_ip,
                                                                        udp_port, mtu

                              NET -> TT  (RX direction)
  +-----------+  512b/250MHz  +--------------------+  512b/250MHz  +--------------------+  512b/250MHz  +---------------------+  512b/250MHz
  |  CMAC1 RX |-------------->|    pkt_demux       |-------------->|   udp_decap_rx     |-------------->| tt_link_framer_stub |-------------->  CMAC0 TX
  | (net-facing)|             | EtherType 0x0800   |  (UDP frames) | strip Eth+IPv4+UDP | (TT payload) | prepend 14B TT eth  |              (BH-facing)
  +-----------+               | IP proto=UDP       |               | (42B), -42B/frame  |              | hdr (EtherType      |
                              | dst port=cfg_udp   |               | validate IP cksum  |              | 0x1AF4)             |
                              +--------------------+              | + port + MTU       |              +---------------------+
                                                                   +--------------------+              cfg: local_mac,
                                                                   cfg: local_ip,                          tt_chip_mac
                                                                        udp_port, mtu

                              AXI-Lite (axil_aclk)
  +------------------+
  |   tt_link_regs   |  cfg_* signals --> all pipeline modules above
  |  (config + stats)|  stat_* signals <-- udp_encap_tx, udp_decap_rx,
  +------------------+                     tt_link_classifier, pkt_demux
```

---

## 3. Module Descriptions

### 3.1 tt_link_udp_bridge_250mhz (top-level)

**Purpose:** Wires the four pipeline modules together, instantiates reset
synchronization (`generic_reset`, 100-cycle hold), and routes AXI-Lite to
`tt_link_regs`.

**Key parameter:**

| Parameter       | Value | Description                                    |
|-----------------|-------|------------------------------------------------|
| `NUM_CMAC_PORT` | 2     | Fixed; index 0 = TT-facing, 1 = net-facing    |

**Clocks:**

| Signal      | Domain          | Used for                          |
|-------------|-----------------|-----------------------------------|
| `axis_aclk` | 250 MHz         | All AXI-Stream pipeline logic     |
| `axil_aclk` | AXI-Lite clock  | `tt_link_regs` register accesses |

Both `axis_aclk` and `axil_aclk` are assumed to be the same clock in the F0
implementation (no CDC crossing).

---

### 3.2 tt_link_classifier

**Purpose:** Inspects beat 0 of every CMAC0 RX frame and forwards only frames
whose EtherType (bytes 12-13) equals 0x1AF4.  All other frames are silently
dropped.  Operates at line rate: the drop decision is made in the same cycle
as beat 0.

**EtherType extraction (little-endian AXI-Stream bus):**

```
byte 12 = tdata[103:96]
byte 13 = tdata[111:104]
EtherType (network byte order) = {byte12, byte13}
```

**State machine:**

| State    | Description                                              |
|----------|----------------------------------------------------------|
| `S_BEAT0`| Inspect EtherType; forward or drop beat 0               |
| `S_PASS` | Forward remaining beats of an accepted TT-link frame    |
| `S_DROP` | Drain remaining beats of a non-TT-link frame            |

**Statistics outputs:** `stat_frames_passed [31:0]`, `stat_frames_dropped [31:0]`

---

### 3.3 udp_encap_tx

**Purpose:** Prepends a 42-byte header `[Eth 14B][IPv4 20B][UDP 8B]` to each
incoming TT-link frame (which already contains a 14B TT Ethernet header).  The
original TT Ethernet header is preserved as the UDP payload — no bytes are
stripped on TX.  The net size change per frame is +28 bytes (42B added, but
14B of the TT Ethernet header is already counted in the original `tuser_size`,
so `ip_total_length = tuser_size + 14`).

**Beat alignment:** The 42-byte header fills bytes 0..41 of output beat 0.
Bytes 42..63 of output beat 0 are taken from bytes 14..35 of the input (a
28-byte right-shift of the payload).  The upper 28 bytes of each input beat
are held in a 224-bit carry register and emitted as the leading portion of the
following output beat.  A final `S_TAIL` beat emits any residual carry bytes.

**IPv4 header:** Generated combinatorially.

| Field          | Value                                |
|----------------|--------------------------------------|
| Version / IHL  | 0x45 (IPv4, no options)             |
| DSCP / ECN     | 0x00                                 |
| Flags          | 0x40 (DF set, no fragment)          |
| TTL            | 64                                   |
| Protocol       | 17 (UDP)                             |
| Header checksum| Computed per-frame (ones complement) |
| IP ID          | Incrementing 16-bit counter         |

**UDP header:** src port == dst port == `cfg_udp_port`.  UDP checksum is forced
to 0x0000 (legal for IPv4 per RFC 768).

**Oversize drop:** Frames where `tuser_size > cfg_mtu - 14` are dropped
without emitting any output beats; `stat_oversize_drops` is incremented.

**State machine:**

| State    | Description                                                |
|----------|------------------------------------------------------------|
| `S_IDLE` | Wait for SOP; check oversize; emit output beat 0          |
| `S_BODY` | Forward middle beats applying 28-byte carry shift         |
| `S_TAIL` | Emit residual carry bytes as final beat                   |
| `S_DROP` | Drain oversize frame beats without emitting output        |

**Key ports:**

| Port                  | Width  | Direction | Description                         |
|-----------------------|--------|-----------|-------------------------------------|
| `cfg_local_mac`       | 48     | in        | FPGA MAC address for CMAC1 TX src   |
| `cfg_peer_mac`        | 48     | in        | Destination MAC on CMAC1 TX         |
| `cfg_local_ip`        | 32     | in        | FPGA IPv4 source address            |
| `cfg_peer_ip`         | 32     | in        | IPv4 destination address            |
| `cfg_udp_port`        | 16     | in        | UDP src/dst port                    |
| `cfg_mtu`             | 16     | in        | MTU limit (default 1500); drop threshold = mtu-14 |
| `stat_frames_out`     | 32     | out       | Frames successfully emitted         |
| `stat_oversize_drops` | 32     | out       | Frames dropped due to oversize      |

---

### 3.4 pkt_demux

**Purpose:** Inspects beat 0 of every CMAC1 RX frame and forwards only frames
that match all three criteria simultaneously.  Because all fields are within
the first 64 bytes, the decision is made entirely on beat 0 at line rate.

**Filter criteria (all must match):**

| Field          | Bus bits         | Required value  |
|----------------|------------------|-----------------|
| EtherType      | tdata[111:96]    | 0x0800 (IPv4)   |
| IP protocol    | tdata[191:184]   | 0x11 (UDP=17)   |
| UDP dst port   | tdata[287:272]   | `cfg_udp_port`  |

**State machine:** Identical structure to `tt_link_classifier` (S_BEAT0,
S_PASS, S_DROP).

**Statistics outputs:** `stat_frames_passed [31:0]`, `stat_frames_dropped [31:0]`

---

### 3.5 udp_decap_rx

**Purpose:** Strips the 42-byte `[Eth 14B][IPv4 20B][UDP 8B]` header from
CMAC1 RX frames that have passed `pkt_demux`.  The remaining stream (starting
with the TT-link payload, e.g. a 96B HybridMeshPacketHeader) is forwarded
downstream.  Net size change per frame is -42 bytes.

**Beat alignment:** Output beat 0 is assembled from bytes 42..63 of input beat
0 (22 bytes held in a 176-bit carry) concatenated with bytes 0..41 of input
beat 1 (42 bytes).  The upper 22 bytes of each subsequent input beat become the
lower 22 bytes of the next output beat.

**Validation (drops frame on any failure):**

| Check                    | Failure counter          |
|--------------------------|--------------------------|
| IP version/IHL == 0x45   | `stat_drops_bad_cksum`   |
| IP protocol == 17 (UDP)  | `stat_drops_bad_cksum`   |
| UDP dst port == cfg       | `stat_drops_bad_port`    |
| IP total_length <= cfg_mtu| `stat_drops_oversize`   |
| IPv4 header checksum valid| `stat_drops_bad_cksum`  |
| Frame ended before beat 1 | `stat_drops_bad_cksum`  |

The IPv4 checksum is verified as the ones-complement sum of the 10 16-bit words
of the IP header (latched during S_BEAT0); the result must equal 0xFFFF.
Port and length checks are evaluated on beat 0 before the checksum is known;
the checksum result is applied in S_BEAT1.

**State machine:**

| State    | Description                                                        |
|----------|--------------------------------------------------------------------|
| `S_BEAT0`| Latch IP header; run early-drop checks; do not emit output        |
| `S_BEAT1`| Verify checksum; emit output beat 0 if valid; update carry        |
| `S_BODY` | Emit subsequent output beats with 22-byte carry shift             |
| `S_TAIL` | Emit residual carry bytes as final beat                           |
| `S_DROP` | Drain remaining input beats of a dropped frame                    |

**Key ports:**

| Port                   | Width | Direction | Description                        |
|------------------------|-------|-----------|------------------------------------|
| `cfg_local_ip`         | 32    | in        | Expected IPv4 dst (informational)  |
| `cfg_udp_port`         | 16    | in        | Expected UDP dst port              |
| `cfg_mtu`              | 16    | in        | Maximum accepted IP total_length   |
| `stat_frames_out`      | 32    | out       | Frames forwarded to framer         |
| `stat_drops_bad_cksum` | 32    | out       | Drops: bad IP cksum or version     |
| `stat_drops_bad_port`  | 32    | out       | Drops: UDP port mismatch           |
| `stat_drops_oversize`  | 32    | out       | Drops: IP length exceeds MTU       |

---

### 3.6 tt_link_framer_stub

**Purpose:** Prepends a 14-byte TT Ethernet header to the decapped payload
before forwarding to CMAC0 TX (the BH-facing port).  The header format is:

```
[dst_mac 6B = cfg_tt_chip_mac][src_mac 6B = cfg_local_mac][EtherType 2B = 0x1AF4]
```

**Beat alignment:** +14-byte shift.  Output bytes 0..13 = TT header;
output bytes 14..63 = input bytes 0..49 (50 bytes from input beat 0).
The upper 14 bytes (112 bits) of each input beat are held in carry and become
the lower 14 bytes of the following output beat.

**State machine:** S_IDLE, S_BODY, S_TAIL, S_DROP (same pattern as
`udp_encap_tx`).

**Note:** This module is a placeholder for F0/F1.  It will be replaced by
`tt_link_framer.sv` in a later milestone that handles HybridMeshPacketHeader
sideband extraction and other protocol details.

---

### 3.7 tt_link_regs

**Purpose:** AXI-Lite register file that provides configuration outputs and
accepts statistics inputs from the pipeline modules.  The register interface
is 32-bit wide.  All stats registers are read-only; config registers are
read-write with reset defaults as shown in the register map below.

The AXI-Lite handshake is simplified: `awready` and `wready` are always 1.
Write address and data are captured on separate cycles; the write is committed
when both have arrived.  Read data is returned in a single registered cycle.

---

## 4. Frame Format

### 4.1 TT-link frame on CMAC0 (EtherType 0x1AF4)

| Bytes   | Field                  | Notes                              |
|---------|------------------------|------------------------------------|
| 0 - 5   | Destination MAC        | TT-chip MAC or FPGA local MAC      |
| 6 - 11  | Source MAC             | Sender MAC                         |
| 12 - 13 | EtherType = 0x1AF4     | TT-link identifier                 |
| 14+     | TT-link payload        | HybridMeshPacketHeader (96B) + data|

### 4.2 Encapsulated frame on CMAC1 (EtherType 0x0800)

| Bytes   | Field                  | Notes                                  |
|---------|------------------------|----------------------------------------|
| 0 - 5   | Destination MAC        | cfg_peer_mac                           |
| 6 - 11  | Source MAC             | cfg_local_mac                          |
| 12 - 13 | EtherType = 0x0800     | IPv4                                   |
| 14      | Version / IHL = 0x45   | IPv4, 20B header, no options          |
| 15      | DSCP / ECN = 0x00      |                                        |
| 16 - 17 | IP total length        | TT-link frame size + 14 (big-endian)  |
| 18 - 19 | IP identification      | Per-frame counter                      |
| 20 - 21 | Flags / frag offset    | 0x4000 (DF=1, MF=0, offset=0)        |
| 22      | TTL = 64               |                                        |
| 23      | Protocol = 0x11        | UDP                                    |
| 24 - 25 | Header checksum        | Ones complement, computed per frame    |
| 26 - 29 | Source IP              | cfg_local_ip (big-endian)             |
| 30 - 33 | Destination IP         | cfg_peer_ip (big-endian)              |
| 34 - 35 | UDP source port        | cfg_udp_port                           |
| 36 - 37 | UDP destination port   | cfg_udp_port                           |
| 38 - 39 | UDP length             | TT-link frame size - 6                |
| 40 - 41 | UDP checksum = 0x0000  | Disabled per RFC 768                   |
| 42+     | UDP payload            | Original TT-link frame (incl. 14B hdr)|

The 28-byte overhead of `[IPv4 20B][UDP 8B]` is added by `udp_encap_tx`; the
14-byte Ethernet header is replaced (not added) because the TT Ethernet header
at bytes 0..13 of the original frame becomes the first 14 bytes of the UDP
payload.  The total on-wire frame size grows by 28 bytes relative to the
original TT-link frame.

---

## 5. Register Map

All offsets are relative to the plugin's AXI-Lite base address assigned by
`system_config`.  Registers are 32 bits wide.  RW = read/write; RO = read-only.

| Offset  | Name              | Access | Reset             | Description                                        |
|---------|-------------------|--------|-------------------|----------------------------------------------------|
| 0x000   | VERSION           | RO     | 0x0002_0001       | Plugin version (major.minor = 2.1)                |
| 0x010   | LOCAL_MAC_HI      | RW     | 0x0000_AABB       | cfg_local_mac[47:32] in bits [15:0]               |
| 0x014   | LOCAL_MAC_LO      | RW     | 0xCCDD_EE00       | cfg_local_mac[31:0]                               |
| 0x018   | LOCAL_IP          | RW     | 0xC0A8_0001       | FPGA IPv4 address (192.168.0.1)                   |
| 0x01C   | LOCAL_UDP_PORT    | RW     | 0x0000_1AF4       | UDP src/dst port for encap/decap in bits [15:0]   |
| 0x020   | PEER_IP           | RW     | 0xC0A8_0002       | Peer IPv4 address (192.168.0.2)                   |
| 0x024   | PEER_MAC_HI       | RW     | 0x0000_0000       | cfg_peer_mac[47:32] in bits [15:0]                |
| 0x028   | PEER_MAC_LO       | RW     | 0x0000_0000       | cfg_peer_mac[31:0]                                |
| 0x02C   | TT_CHIP_MAC_HI    | RW     | 0x0000_0000       | cfg_tt_chip_mac[47:32] in bits [15:0]             |
| 0x030   | TT_CHIP_MAC_LO    | RW     | 0x0000_0000       | cfg_tt_chip_mac[31:0]                             |
| 0x034   | MTU_EXTERNAL      | RW     | 0x0000_05DC (1500)| Max IP total_length; drop threshold = mtu-14      |
| 0x400   | STAT_TX_FRAMES    | RO     | 0                 | Frames emitted by udp_encap_tx                    |
| 0x404   | STAT_TX_OVERSIZE  | RO     | 0                 | Frames dropped by udp_encap_tx (oversize)         |
| 0x41C   | STAT_RX_FRAMES    | RO     | 0                 | Frames forwarded by udp_decap_rx                  |
| 0x424   | STAT_RX_BAD_PORT  | RO     | 0                 | Drops: UDP port mismatch in udp_decap_rx          |
| 0x428   | STAT_RX_BAD_CKSUM | RO     | 0                 | Drops: bad IPv4 cksum / version in udp_decap_rx  |
| 0x42C   | STAT_RX_OVERSIZE  | RO     | 0                 | Drops: IP length > MTU in udp_decap_rx            |
| 0x430   | STAT_CLS_PASSED   | RO     | 0                 | TT-link frames forwarded by tt_link_classifier    |
| 0x434   | STAT_CLS_DROPPED  | RO     | 0                 | Frames dropped by tt_link_classifier              |
| 0x438   | STAT_DMX_PASSED   | RO     | 0                 | UDP frames forwarded by pkt_demux                 |
| 0x43C   | STAT_DMX_DROPPED  | RO     | 0                 | Frames dropped by pkt_demux                       |

Reads to undefined offsets return 0xDEAD_BEEF.  Writes to stat registers or
undefined offsets are silently ignored.

---

## 6. Known Constants and Limits

| Constant / Limit              | Value          | Source                           |
|-------------------------------|----------------|----------------------------------|
| AXI-Stream bus width          | 512 bits       | All pipeline buses               |
| Beat size                     | 64 bytes       | 512 / 8                         |
| Clock frequency               | 250 MHz        | axis_aclk                       |
| TT-link EtherType             | 0x1AF4         | tt_link_classifier filter        |
| UDP/IP EtherType              | 0x0800         | pkt_demux filter                 |
| Default UDP port              | 0x1AF4 (6900) | tt_link_regs reset value         |
| Default MTU                   | 1500 bytes     | cfg_mtu reset value              |
| TX header overhead            | 28 bytes       | IPv4 (20B) + UDP (8B)           |
| Max TT-link payload on TX     | 1472 bytes     | 1500 - 28 = 1472                |
| Max TT-link payload (with HMH)| 1376 bytes     | 1472 - 96B HMH = 1376           |
| Encap carry register width    | 224 bits       | 28-byte shift in udp_encap_tx   |
| Decap carry register width    | 176 bits       | 22-byte shift in udp_decap_rx   |
| Framer carry register width   | 112 bits       | 14-byte shift in framer_stub    |
| IP ID counter                 | 16-bit wrap    | udp_encap_tx, resets to 0x0001  |
| IPv4 TTL                      | 64             | Fixed in udp_encap_tx            |
| UDP checksum                  | 0x0000         | Disabled; legal per RFC 768      |

---

## 7. Pending Work

The following items are deferred to future milestones (F2/F3):

- **tt_link_framer (F2):** Replace `tt_link_framer_stub` with a full framer
  that extracts the correct EtherType and other fields from the
  HybridMeshPacketHeader sideband, rather than always stamping 0x1AF4.

- **ARP responder on CMAC0 (F2):** `pkt_demux` currently discards all non-TT-
  link traffic from CMAC0.  An ARP responder is needed so that the BH chip can
  resolve the FPGA MAC before the first TT-link frame.

- **ARP/ICMP responder on CMAC1 (F3):** Answer ARP requests and ICMP echo
  requests from the network-facing peer so the FPGA appears as a proper IP
  endpoint without requiring a host CPU.

- **Clock-domain crossing (F3):** `axil_aclk` and `axis_aclk` are assumed to
  be the same clock in F0/F1.  A proper CDC stage should be added to the config
  registers if the two clocks are ever separated.

- **Multi-destination support (F3):** `udp_encap_tx` currently uses a single
  static `cfg_peer_ip` / `cfg_peer_mac`.  A future version should support
  routing based on the HMH destination chip ID.

- **Stat counter saturation / clear (F3):** All stat counters free-run and wrap
  on overflow.  Adding a write-to-clear mechanism and overflow indication would
  improve observability.
