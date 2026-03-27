# PTP IEEE 1588 Test Suite -- OpenNIC Shell

## Directory Contents

```
tests/
  test_plan.md                 Comprehensive test plan document
  README.md                    This file
  test_env.sh                  (user-created) Environment variable overrides
  test_phc_basic.sh            Category A: PHC clock read/set/adjust tests
  test_hwtstamp.sh             Category C: Hardware timestamping enable/verify
  test_ptp_sync.sh             Category B: ptp4l master/slave synchronization
  test_latency_two_shell.sh    Category D: Two-shell latency measurement
```

## Prerequisites

1. Two OpenNIC FPGA NICs with PTP-enabled bitstream, connected back-to-back.

2. The `onic` kernel module loaded on both NICs:
   ```
   lsmod | grep onic
   ```

3. Required userspace tools:
   ```
   sudo apt install linuxptp ethtool iproute2 bc
   ```
   This provides: `ptp4l`, `phc2sys`, `phc_ctl`, `hwstamp_ctl`.

4. Interfaces must be up with IP addresses assigned:
   ```
   sudo ip addr add 10.0.0.1/24 dev onic0s0f0
   sudo ip addr add 10.0.0.2/24 dev onic1s0f0
   sudo ip link set onic0s0f0 up
   sudo ip link set onic1s0f0 up
   ```

5. Root privileges (or appropriate capabilities for PTP device access).

## Configuration

Create a `test_env.sh` file in this directory to override defaults:

```bash
# test_env.sh -- environment overrides for PTP tests
IF_MASTER="onic0s0f0"
IF_SLAVE="onic1s0f0"
PTP_MASTER="/dev/ptp0"
PTP_SLAVE="/dev/ptp1"
IP_MASTER="10.0.0.1"
IP_SLAVE="10.0.0.2"
```

If `test_env.sh` does not exist, the scripts will auto-detect interfaces and
PTP devices from the first two onic interfaces found.

## Running Tests

All scripts must be run as root (or with sudo).

### Run individual test suites:

```bash
sudo ./test_phc_basic.sh           # PHC operations (single shell OK)
sudo ./test_hwtstamp.sh            # HW timestamping capabilities
sudo ./test_ptp_sync.sh            # PTP synchronization (needs two shells)
sudo ./test_latency_two_shell.sh   # Latency measurement (needs two shells)
```

### Run all tests:

```bash
for t in test_phc_basic.sh test_hwtstamp.sh test_ptp_sync.sh test_latency_two_shell.sh; do
    echo "========== Running $t =========="
    sudo ./$t
    echo ""
done
```

### Selective test execution:

Each script accepts optional test IDs to run specific tests:

```bash
sudo ./test_phc_basic.sh A.1 A.2        # Run only tests A.1 and A.2
sudo ./test_ptp_sync.sh B.3             # Run only offset convergence test
```

## Output

- Test results are printed to stdout with colored PASS/FAIL indicators.
- Detailed logs are written to `/tmp/ptp_test_<script>_<timestamp>/`.
- A summary line at the end shows total pass/fail counts.

## Troubleshooting

- **"phc_index is -1"**: PTP hardware not detected. Check `dmesg | grep -i ptp`
  for initialization messages. Verify the bitstream includes PTP IP.

- **"ptp4l: failed to create a clock"**: The PTP device may not be accessible.
  Check permissions on `/dev/ptpN`.

- **"hwstamp_ctl: SIOCSHWTSTAMP failed"**: Driver does not support the
  requested timestamping mode. Check `ethtool -T <interface>`.

- **"Offset not converging"**: Check that the cable is connected and link is up
  on both sides. Run `ethtool <interface>` to verify link status.

- **Large offsets (>10us)**: May indicate the FPGA clock domain crossing is not
  working correctly. Check `dmesg` for PTP-related warnings.
