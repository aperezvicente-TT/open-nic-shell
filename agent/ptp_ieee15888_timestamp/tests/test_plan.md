# PTP IEEE 1588 Test Plan -- OpenNIC Shell Two-Shell Setup

## 1. Overview

This test plan covers validation of the PTP IEEE 1588 hardware timestamping
implementation for the OpenNIC Shell FPGA NIC. The test setup uses **two
OpenNIC shells** (two FPGA NICs) connected back-to-back or through a direct
cable, each running the `onic` kernel module with PTP support.

### Scope

- PHC (PTP Hardware Clock) basic operations via `/dev/ptpN`
- PTP synchronization between two shells using `ptp4l`
- Hardware timestamping (RX and TX) delivery to userspace
- Two-shell latency measurement (one-way, round-trip, wire-to-wire)
- Stress and stability tests

### Out of Scope

- FPGA RTL simulation (covered by Vivado testbench)
- Software-only PTP (no hardware timestamps)
- Multi-hop PTP boundary/transparent clock configurations

---

## 2. Test Environment

### Hardware

| Item             | Description                                          |
|------------------|------------------------------------------------------|
| Shell A (Master) | OpenNIC FPGA NIC, PCIe slot, interface `$IF_MASTER`  |
| Shell B (Slave)  | OpenNIC FPGA NIC, PCIe slot, interface `$IF_SLAVE`   |
| Connection       | Direct QSFP28 cable between Shell A port 0 and Shell B port 0 |

### Software Prerequisites

| Tool          | Minimum Version | Purpose                            |
|---------------|----------------|------------------------------------|
| `linuxptp`    | 3.1            | `ptp4l`, `phc2sys`, `phc_ctl`, `hwstamp_ctl` |
| `ethtool`     | 5.0            | Query timestamping capabilities    |
| `iproute2`    | 5.0            | Interface configuration            |
| `onic` module | current        | OpenNIC kernel driver with PTP     |
| `bc`          | any            | Arithmetic in shell scripts        |

### Kernel Requirements

- `CONFIG_PTP_1588_CLOCK=y` or `=m`
- `CONFIG_NET_TIMESTAMPING=y`
- `/dev/ptpN` character devices accessible (may require root or `ptp` group)

### Environment Variables (used by all test scripts)

```bash
IF_MASTER="onic0s0f0"    # Shell A network interface
IF_SLAVE="onic1s0f0"     # Shell B network interface
PTP_MASTER="/dev/ptp0"   # Shell A PTP clock device
PTP_SLAVE="/dev/ptp1"    # Shell B PTP clock device
IP_MASTER="10.0.0.1"     # Shell A IP address
IP_SLAVE="10.0.0.2"      # Shell B IP address
```

These can be overridden via a `test_env.sh` file in the tests directory or
exported before running any script.

---

## 3. Test Categories

### Category A: PHC Basic Operations

Validates that the PTP hardware clock is accessible, readable, writable, and
adjustable through the standard Linux PTP subsystem.

### Category B: PTP Synchronization

Validates end-to-end PTP synchronization between two shells using the
linuxptp `ptp4l` daemon in hardware timestamping mode.

### Category C: Hardware Timestamping

Validates that the driver correctly exposes timestamping capabilities and
delivers hardware timestamps to userspace on both RX and TX paths.

### Category D: Two-Shell Latency Measurement

Uses synchronized PTP clocks to measure one-way, round-trip, and
wire-to-wire latency between the two shells.

### Category E: Stress and Stability

Long-duration and high-rate tests to verify the PTP subsystem remains
stable under load.

---

## 4. Test Cases

### Category A: PHC Basic Operations

#### A.1 -- PHC Device Existence

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.1                                                    |
| **Description** | Verify `/dev/ptpN` exists for each loaded onic interface |
| **Precondition**| onic module loaded, interface up                       |
| **Steps**       | 1. Run `ethtool -T $IF_MASTER` and extract `phc_index` |
|                 | 2. Verify `/dev/ptp<phc_index>` exists and is a character device |
| **Pass**        | Character device exists with major 247 (PTP)           |
| **Fail**        | Device missing or phc_index is -1                      |

#### A.2 -- PHC Clock Read

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.2                                                    |
| **Description** | Read the PHC clock and verify it returns valid time    |
| **Steps**       | 1. `phc_ctl $PTP_MASTER get`                           |
|                 | 2. Verify returned seconds > 0                         |
|                 | 3. Read twice with 1-second sleep, verify delta is ~1s |
| **Pass**        | Clock reads succeed; delta between reads is 0.9--1.1s  |
| **Fail**        | Read fails, returns 0, or delta is out of range        |

#### A.3 -- PHC Clock Set

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.3                                                    |
| **Description** | Set the PHC clock to a known epoch and read it back    |
| **Steps**       | 1. `phc_ctl $PTP_MASTER set 1000000000`                |
|                 | 2. `phc_ctl $PTP_MASTER get`                           |
|                 | 3. Verify returned time is within 1s of 1000000000     |
| **Pass**        | Readback time is 1000000000 +/- 1s                     |
| **Fail**        | Set fails or readback differs by more than 1s          |

#### A.4 -- PHC Adjtime (Phase Offset)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.4                                                    |
| **Description** | Apply a time adjustment and verify it takes effect     |
| **Steps**       | 1. Read current time T0                                |
|                 | 2. `phc_ctl $PTP_MASTER adj 500000000` (add 0.5s)     |
|                 | 3. Read time T1                                        |
|                 | 4. Verify T1 - T0 >= 0.5s (accounting for elapsed)    |
| **Pass**        | Observed offset matches expected adjustment +/- 50ms   |
| **Fail**        | Adjustment not reflected or exceeds tolerance          |

#### A.5 -- PHC Adjfreq (Frequency Trim)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.5                                                    |
| **Description** | Apply a frequency adjustment and measure drift         |
| **Steps**       | 1. Set clock to known time                             |
|                 | 2. `phc_ctl $PTP_MASTER freq 100000000` (+100 ppm)    |
|                 | 3. Wait 10 seconds                                    |
|                 | 4. Read clock; expect ~1ms extra drift (10s * 100ppm)  |
| **Pass**        | Measured drift is 0.5--2.0 ms over 10 seconds          |
| **Fail**        | No drift observed or drift wildly off expected range   |

#### A.6 -- PHC Clock Tick Rate

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | A.6                                                    |
| **Description** | Verify clock increments at 4ns per tick (250 MHz)      |
| **Steps**       | 1. Read clock twice in rapid succession                |
|                 | 2. Compute delta in nanoseconds                        |
|                 | 3. Verify delta is a multiple of 4ns (within PCIe read overhead) |
| **Pass**        | Delta is non-zero and consistent with 4ns tick period  |
| **Fail**        | Delta is 0, negative, or not 4ns-aligned               |

---

### Category B: PTP Synchronization

#### B.1 -- ptp4l Startup (Master)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | B.1                                                    |
| **Description** | Start ptp4l as grandmaster on Shell A                  |
| **Steps**       | 1. Start `ptp4l -i $IF_MASTER -H -m --priority1 128`  |
|                 | 2. Wait 10s for initialization                         |
|                 | 3. Check log for "selected best master clock"          |
| **Pass**        | ptp4l running, selected itself as grandmaster          |
| **Fail**        | ptp4l exits with error or cannot use HW timestamps     |

#### B.2 -- ptp4l Startup (Slave)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | B.2                                                    |
| **Description** | Start ptp4l as slave on Shell B, connect to master     |
| **Steps**       | 1. Start `ptp4l -i $IF_SLAVE -H -m -s`                |
|                 | 2. Wait 30s for synchronization                        |
|                 | 3. Check log for "UNCALIBRATED to SLAVE"               |
| **Pass**        | Slave state reached within 60s                         |
| **Fail**        | Stuck in LISTENING or UNCALIBRATED after timeout       |

#### B.3 -- Offset Convergence

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | B.3                                                    |
| **Description** | Verify PTP offset converges below threshold            |
| **Steps**       | 1. Run ptp4l slave for 120s                            |
|                 | 2. Parse last 30 offset samples from log               |
|                 | 3. Compute mean and max absolute offset                |
| **Pass**        | Mean |offset| < 1000 ns, Max |offset| < 5000 ns       |
| **Fail**        | Offset does not converge or exceeds thresholds         |

#### B.4 -- phc2sys Tracking

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | B.4                                                    |
| **Description** | Verify phc2sys can synchronize system clock to PHC     |
| **Steps**       | 1. Start `phc2sys -s $IF_SLAVE -c CLOCK_REALTIME -O 0 -m` |
|                 | 2. Wait 30s                                            |
|                 | 3. Parse offset from log                               |
| **Pass**        | phc2sys reports offset converging toward 0             |
| **Fail**        | phc2sys fails to start or offset diverges              |

#### B.5 -- Master Failover Recovery

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | B.5                                                    |
| **Description** | Restart master ptp4l, verify slave re-synchronizes     |
| **Steps**       | 1. With B.3 passing, kill master ptp4l                 |
|                 | 2. Verify slave enters LISTENING state                 |
|                 | 3. Restart master ptp4l                                |
|                 | 4. Verify slave returns to SLAVE state within 60s      |
| **Pass**        | Slave recovers to SLAVE state after master restart     |
| **Fail**        | Slave never returns to SLAVE state                     |

---

### Category C: Hardware Timestamping

#### C.1 -- Ethtool Capabilities

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.1                                                    |
| **Description** | Verify ethtool reports correct HW timestamping caps    |
| **Steps**       | 1. `ethtool -T $IF_MASTER`                             |
|                 | 2. Verify output contains:                             |
|                 |    - `hardware-transmit`                               |
|                 |    - `hardware-receive`                                |
|                 |    - `hardware-raw-clock`                              |
|                 |    - `HWTSTAMP_TX_ON`                                  |
|                 |    - `HWTSTAMP_FILTER_ALL`                             |
|                 | 3. Verify `phc_index` is not -1                        |
| **Pass**        | All expected capabilities present                      |
| **Fail**        | Any capability missing or phc_index is -1              |

#### C.2 -- Enable HW Timestamping

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.2                                                    |
| **Description** | Enable HW timestamping via hwstamp_ctl                 |
| **Steps**       | 1. `hwstamp_ctl -i $IF_MASTER -t 1 -r 1`              |
|                 | 2. Verify return code is 0                             |
|                 | 3. Verify `hwstamp_ctl -i $IF_MASTER` shows enabled    |
| **Pass**        | TX type = ON, RX filter = ALL after enable             |
| **Fail**        | hwstamp_ctl fails or config not reflected              |

#### C.3 -- Disable HW Timestamping

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.3                                                    |
| **Description** | Disable HW timestamping and verify                     |
| **Steps**       | 1. `hwstamp_ctl -i $IF_MASTER -t 0 -r 0`              |
|                 | 2. Verify TX type = OFF, RX filter = NONE              |
| **Pass**        | Timestamping disabled successfully                     |
| **Fail**        | Config not reverted to OFF/NONE                        |

#### C.4 -- RX Timestamp Delivery

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.4                                                    |
| **Description** | Verify RX packets carry hardware timestamps            |
| **Steps**       | 1. Enable HW timestamping on Shell B                   |
|                 | 2. Send 10 UDP packets from Shell A to Shell B         |
|                 | 3. On Shell B, capture with `SO_TIMESTAMPING` socket   |
|                 | 4. Verify each packet has non-zero hardware timestamp  |
| **Pass**        | All 10 packets have valid (non-zero) HW RX timestamps  |
| **Fail**        | Any packet missing HW timestamp or timestamp is 0      |

#### C.5 -- TX Timestamp Delivery

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.5                                                    |
| **Description** | Verify TX packets return hardware timestamps           |
| **Steps**       | 1. Enable HW timestamping on Shell A                   |
|                 | 2. Send 10 UDP packets from Shell A with TX TS request |
|                 | 3. Read TX timestamps from error queue (`MSG_ERRQUEUE`)|
|                 | 4. Verify each has non-zero hardware timestamp         |
| **Pass**        | All 10 TX timestamps received and valid                |
| **Fail**        | Missing TX timestamps or timeout on error queue        |

#### C.6 -- TX Timestamp Tag Matching

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.6                                                    |
| **Description** | Verify TX timestamps are matched to correct packets    |
| **Steps**       | 1. Send 100 packets with different sizes rapidly       |
|                 | 2. Collect TX timestamps                               |
|                 | 3. Verify timestamps are monotonically increasing      |
|                 | 4. Verify no TX TS FIFO overflow (dmesg check)         |
| **Pass**        | All timestamps monotonic, no FIFO overflow             |
| **Fail**        | Out-of-order timestamps or FIFO overflow in dmesg      |

#### C.7 -- Timestamp Sanity (RX vs TX Ordering)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | C.7                                                    |
| **Description** | Verify TX timestamp < RX timestamp for same packet     |
| **Steps**       | 1. Synchronize clocks (ptp4l running)                  |
|                 | 2. Send ping from A to B, capture both TX and RX TS    |
|                 | 3. Verify TX_TS < RX_TS (one-way delay is positive)    |
| **Pass**        | TX timestamp precedes RX timestamp on every packet     |
| **Fail**        | RX timestamp precedes TX (clocks inverted or wrong)    |

---

### Category D: Two-Shell Latency Measurement

#### D.1 -- One-Way Latency (A to B)

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | D.1                                                    |
| **Description** | Measure one-way latency from Shell A TX to Shell B RX  |
| **Steps**       | 1. Synchronize clocks via ptp4l                        |
|                 | 2. Send 1000 UDP packets A -> B                        |
|                 | 3. Record TX timestamp on A, RX timestamp on B         |
|                 | 4. Compute one-way = RX_TS - TX_TS for each packet    |
|                 | 5. Report min, max, mean, stddev, P99                  |
| **Pass**        | Mean one-way < 10 us for direct cable, stddev < 1 us  |
| **Fail**        | Negative one-way (clock desync) or mean > 100 us      |

#### D.2 -- Round-Trip Latency

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | D.2                                                    |
| **Description** | Measure round-trip latency using ICMP or UDP echo      |
| **Steps**       | 1. Send 1000 ICMP echo requests from A to B            |
|                 | 2. Record TX timestamp on send, RX timestamp on reply  |
|                 | 3. RTT = RX_reply_TS - TX_request_TS                   |
|                 | 4. Report min, max, mean, stddev, P99                  |
| **Pass**        | Mean RTT < 20 us for direct cable                      |
| **Fail**        | RTT > 200 us or high variance                          |

#### D.3 -- Wire-to-Wire Latency

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | D.3                                                    |
| **Description** | Measure packet forwarding latency through one shell    |
| **Steps**       | 1. Configure Shell A as forwarder (bridge or routing)  |
|                 | 2. Send from external source through Shell A           |
|                 | 3. Capture RX timestamp (ingress) and TX timestamp (egress) |
|                 | 4. Wire-to-wire = TX_egress_TS - RX_ingress_TS        |
| **Pass**        | Forwarding latency measurable and consistent           |
| **Fail**        | Timestamps not available or results inconsistent       |

#### D.4 -- ptp4l Offset Statistics

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | D.4                                                    |
| **Description** | Extract offset statistics from ptp4l logs              |
| **Steps**       | 1. Run ptp4l for 300s (5 minutes)                      |
|                 | 2. Parse all "offset" lines from slave log             |
|                 | 3. Compute: min, max, mean, stddev, histogram          |
|                 | 4. Report convergence time (time to |offset| < 1000ns)|
| **Pass**        | Steady-state mean |offset| < 500 ns                   |
| **Fail**        | Mean |offset| > 5000 ns or never converges             |

---

### Category E: Stress and Stability

#### E.1 -- Long-Duration Sync Stability

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | E.1                                                    |
| **Description** | Run PTP sync for 1 hour, verify offset remains bounded |
| **Steps**       | 1. Start ptp4l master/slave pair                       |
|                 | 2. Log offsets for 3600 seconds                        |
|                 | 3. Check no offset sample exceeds 10000 ns             |
| **Pass**        | All samples |offset| < 10000 ns after initial convergence |
| **Fail**        | Any sample exceeds threshold after convergence         |

#### E.2 -- High-Rate Timestamping

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | E.2                                                    |
| **Description** | Timestamp packets at line rate for 60 seconds          |
| **Steps**       | 1. Enable HW timestamping on both shells               |
|                 | 2. Send minimum-size packets at maximum rate for 60s   |
|                 | 3. Check for TX TS FIFO overflows in dmesg             |
|                 | 4. Verify no driver errors or kernel oops              |
| **Pass**        | No FIFO overflow, no kernel errors after 60s           |
| **Fail**        | FIFO overflow, driver crash, or kernel oops            |

#### E.3 -- PHC Set During Active Sync

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | E.3                                                    |
| **Description** | Set PHC time while ptp4l is running, verify recovery   |
| **Steps**       | 1. With ptp4l slave converged                          |
|                 | 2. `phc_ctl $PTP_SLAVE set 0` (reset to epoch)        |
|                 | 3. Wait 120s for ptp4l to re-converge                  |
|                 | 4. Verify offset < 5000 ns                             |
| **Pass**        | ptp4l recovers and re-converges                        |
| **Fail**        | ptp4l hangs, crashes, or offset stays large            |

#### E.4 -- Concurrent PHC Access

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | E.4                                                    |
| **Description** | Multiple processes reading PHC simultaneously          |
| **Steps**       | 1. Launch 10 concurrent `phc_ctl get` loops            |
|                 | 2. Run for 30 seconds                                  |
|                 | 3. Check all reads succeed, no kernel warnings         |
| **Pass**        | All reads return valid time, no lockups                |
| **Fail**        | Read failures, kernel BUG, or lockup detected          |

#### E.5 -- Link Flap During PTP Sync

| Field           | Value                                                  |
|-----------------|--------------------------------------------------------|
| **ID**          | E.5                                                    |
| **Description** | Bring link down/up while PTP is synced                 |
| **Steps**       | 1. With ptp4l converged, `ip link set $IF_SLAVE down`  |
|                 | 2. Wait 5s, `ip link set $IF_SLAVE up`                 |
|                 | 3. Verify ptp4l re-acquires SLAVE state                |
|                 | 4. Verify offset converges within 120s                 |
| **Pass**        | PTP re-synchronizes after link recovery                |
| **Fail**        | ptp4l does not recover or offset stays large           |

---

## 5. Test Execution Order

The recommended execution order is:

1. `test_phc_basic.sh` -- Category A (no second shell needed for most tests)
2. `test_hwtstamp.sh` -- Category C (needs both shells for some tests)
3. `test_ptp_sync.sh` -- Category B (needs both shells)
4. `test_latency_two_shell.sh` -- Category D + E (needs both shells, clocks synced)

---

## 6. Pass/Fail Summary Template

```
=== PTP IEEE 1588 Test Results ===
Date:       ____________________
Shell A:    ____________________  (PCIe BDF, interface, /dev/ptpN)
Shell B:    ____________________  (PCIe BDF, interface, /dev/ptpN)
Firmware:   ____________________  (bitstream build ID)
Driver:     ____________________  (onic module version)
Kernel:     ____________________  (uname -r)

Category A: PHC Basic Operations
  A.1 PHC Device Existence       [ PASS / FAIL ]
  A.2 PHC Clock Read             [ PASS / FAIL ]
  A.3 PHC Clock Set              [ PASS / FAIL ]
  A.4 PHC Adjtime                [ PASS / FAIL ]
  A.5 PHC Adjfreq                [ PASS / FAIL ]
  A.6 PHC Clock Tick Rate        [ PASS / FAIL ]

Category B: PTP Synchronization
  B.1 ptp4l Master Startup       [ PASS / FAIL ]
  B.2 ptp4l Slave Startup        [ PASS / FAIL ]
  B.3 Offset Convergence         [ PASS / FAIL ]
  B.4 phc2sys Tracking           [ PASS / FAIL ]
  B.5 Master Failover Recovery   [ PASS / FAIL ]

Category C: Hardware Timestamping
  C.1 Ethtool Capabilities       [ PASS / FAIL ]
  C.2 Enable HW Timestamping     [ PASS / FAIL ]
  C.3 Disable HW Timestamping    [ PASS / FAIL ]
  C.4 RX Timestamp Delivery      [ PASS / FAIL ]
  C.5 TX Timestamp Delivery      [ PASS / FAIL ]
  C.6 TX Timestamp Tag Matching  [ PASS / FAIL ]
  C.7 Timestamp Sanity           [ PASS / FAIL ]

Category D: Two-Shell Latency
  D.1 One-Way Latency            [ PASS / FAIL ]
  D.2 Round-Trip Latency         [ PASS / FAIL ]
  D.3 Wire-to-Wire Latency       [ PASS / FAIL ]
  D.4 ptp4l Offset Statistics    [ PASS / FAIL ]

Category E: Stress and Stability
  E.1 Long-Duration Stability    [ PASS / FAIL ]
  E.2 High-Rate Timestamping     [ PASS / FAIL ]
  E.3 PHC Set During Sync        [ PASS / FAIL ]
  E.4 Concurrent PHC Access      [ PASS / FAIL ]
  E.5 Link Flap Recovery         [ PASS / FAIL ]

Overall: ______ / 21 passed
```
