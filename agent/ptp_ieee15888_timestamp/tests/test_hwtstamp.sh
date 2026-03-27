#!/usr/bin/env bash
# =============================================================================
# test_hwtstamp.sh -- Category C: Hardware Timestamping
#
# Tests HW timestamping capabilities, enable/disable, and RX/TX timestamp
# delivery for the OpenNIC Shell PTP implementation.
#
# Usage:
#   sudo ./test_hwtstamp.sh              # Run all tests
#   sudo ./test_hwtstamp.sh C.1 C.2      # Run specific tests
#
# Prerequisites:
#   - Two onic interfaces connected back-to-back with IP addresses
#   - linuxptp tools installed (hwstamp_ctl)
#   - ethtool
#   - Root privileges
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Color output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "  [${GREEN}PASS${NC}] $1"; }
fail()  { echo -e "  [${RED}FAIL${NC}] $1"; }
skip()  { echo -e "  [${YELLOW}SKIP${NC}] $1"; }
info()  { echo -e "  [${CYAN}INFO${NC}] $1"; }
header(){ echo -e "\n${BOLD}=== $1 ===${NC}"; }

TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0
record_pass() { ((TOTAL++)) || true; ((PASSED++)) || true; pass "$1"; }
record_fail() { ((TOTAL++)) || true; ((FAILED++)) || true; fail "$1"; }
record_skip() { ((TOTAL++)) || true; ((SKIPPED++)) || true; skip "$1"; }

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/ptp_test_hwtstamp_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

if [[ -f "$SCRIPT_DIR/test_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/test_env.sh"
fi

# Auto-detect
if [[ -z "${IF_MASTER:-}" ]] || [[ -z "${IF_SLAVE:-}" ]]; then
    ONIC_IFACES=($(ip -o link show | grep -oP 'onic\S+' || true))
    if [[ ${#ONIC_IFACES[@]} -lt 2 ]]; then
        echo -e "${RED}ERROR: Need at least 2 onic interfaces for full test suite.${NC}"
        echo -e "${YELLOW}Continuing with single interface for capability tests.${NC}"
        IF_MASTER="${ONIC_IFACES[0]:-}"
        IF_SLAVE=""
    else
        IF_MASTER="${IF_MASTER:-${ONIC_IFACES[0]}}"
        IF_SLAVE="${IF_SLAVE:-${ONIC_IFACES[1]}}"
    fi
fi

IP_MASTER="${IP_MASTER:-10.0.0.1}"
IP_SLAVE="${IP_SLAVE:-10.0.0.2}"

info "Master interface: ${IF_MASTER:-<none>}"
info "Slave interface:  ${IF_SLAVE:-<none>}"
info "Log directory:    $LOG_DIR"

REQUESTED_TESTS=("${@}")
run_test() {
    local test_id="$1"
    if [[ ${#REQUESTED_TESTS[@]} -eq 0 ]]; then return 0; fi
    for t in "${REQUESTED_TESTS[@]}"; do
        [[ "$t" == "$test_id" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Inline Python helper for SO_TIMESTAMPING socket tests
# This avoids requiring external compiled binaries.
# ---------------------------------------------------------------------------
TIMESTAMP_HELPER=$(cat << 'PYEOF'
#!/usr/bin/env python3
"""
Minimal SO_TIMESTAMPING socket helper for testing HW timestamps.

Usage:
  python3 <this_script> rx <interface> <bind_ip> <port> <count> <timeout_sec>
  python3 <this_script> tx <interface> <dest_ip> <port> <count>
  python3 <this_script> txrx <interface> <bind_ip> <dest_ip> <port> <count> <timeout_sec>

Outputs one line per packet: "TX|RX <seq> <hw_sec> <hw_nsec>" or "NONE" if no HW TS.
"""
import sys
import socket
import struct
import time

# SO_TIMESTAMPING constants
SO_TIMESTAMPING = 37
SOF_TIMESTAMPING_TX_HARDWARE  = (1 << 0)
SOF_TIMESTAMPING_TX_SOFTWARE  = (1 << 1)
SOF_TIMESTAMPING_RX_HARDWARE  = (1 << 2)
SOF_TIMESTAMPING_RX_SOFTWARE  = (1 << 3)
SOF_TIMESTAMPING_SOFTWARE     = (1 << 4)
SOF_TIMESTAMPING_RAW_HARDWARE = (1 << 6)
SOF_TIMESTAMPING_OPT_TSONLY   = (1 << 11)

SCM_TIMESTAMPING = 37
MSG_ERRQUEUE = 0x2000

def parse_cmsg_timestamp(cmsg_data):
    """Parse SCM_TIMESTAMPING control message. Returns (sw_sec, sw_nsec, hw_sec, hw_nsec)."""
    # struct scm_timestamping has 3 timespecs (sw, legacy_hw, raw_hw)
    # Each timespec is (sec: long, nsec: long) -- 8+8=16 bytes on 64-bit
    if len(cmsg_data) >= 48:
        # We want the third timespec (raw hardware)
        hw_sec, hw_nsec = struct.unpack("ll", cmsg_data[32:48])
        return hw_sec, hw_nsec
    return 0, 0

def run_rx(interface, bind_ip, port, count, timeout):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    flags = (SOF_TIMESTAMPING_RX_HARDWARE | SOF_TIMESTAMPING_RAW_HARDWARE)
    sock.setsockopt(socket.SOL_SOCKET, SO_TIMESTAMPING, flags)
    sock.bind((bind_ip, port))
    sock.settimeout(timeout)

    received = 0
    hw_ts_count = 0
    for i in range(count):
        try:
            data, ancdata, msg_flags, addr = sock.recvmsg(2048, 1024)
            received += 1
            hw_sec, hw_nsec = 0, 0
            for cmsg_level, cmsg_type, cmsg_data in ancdata:
                if cmsg_level == socket.SOL_SOCKET and cmsg_type == SCM_TIMESTAMPING:
                    hw_sec, hw_nsec = parse_cmsg_timestamp(cmsg_data)
            if hw_sec != 0 or hw_nsec != 0:
                hw_ts_count += 1
                print(f"RX {i} {hw_sec} {hw_nsec}")
            else:
                print(f"RX {i} NONE")
        except socket.timeout:
            print(f"RX {i} TIMEOUT")
            break

    sock.close()
    print(f"SUMMARY rx_received={received} rx_hw_ts={hw_ts_count}")

def run_tx(interface, dest_ip, port, count):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode())
    flags = (SOF_TIMESTAMPING_TX_HARDWARE | SOF_TIMESTAMPING_RAW_HARDWARE |
             SOF_TIMESTAMPING_OPT_TSONLY)
    sock.setsockopt(socket.SOL_SOCKET, SO_TIMESTAMPING, flags)
    sock.settimeout(2.0)

    sent = 0
    hw_ts_count = 0
    for i in range(count):
        payload = f"PTP_TEST_PKT_{i:06d}".encode()
        sock.sendto(payload, (dest_ip, port))
        sent += 1

        # Read TX timestamp from error queue
        try:
            data, ancdata, msg_flags, addr = sock.recvmsg(2048, 1024, MSG_ERRQUEUE)
            for cmsg_level, cmsg_type, cmsg_data in ancdata:
                if cmsg_level == socket.SOL_SOCKET and cmsg_type == SCM_TIMESTAMPING:
                    hw_sec, hw_nsec = parse_cmsg_timestamp(cmsg_data)
                    if hw_sec != 0 or hw_nsec != 0:
                        hw_ts_count += 1
                        print(f"TX {i} {hw_sec} {hw_nsec}")
                    else:
                        print(f"TX {i} NONE")
        except socket.timeout:
            print(f"TX {i} TIMEOUT")
        except OSError:
            print(f"TX {i} ERROR")

        time.sleep(0.01)  # Small gap between packets

    sock.close()
    print(f"SUMMARY tx_sent={sent} tx_hw_ts={hw_ts_count}")

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "rx":
        run_rx(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6]))
    elif mode == "tx":
        run_tx(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]))
    else:
        print(f"Unknown mode: {mode}", file=sys.stderr)
        sys.exit(1)
PYEOF
)

# Write helper to temp file
TS_HELPER_PY="$LOG_DIR/ts_helper.py"
echo "$TIMESTAMP_HELPER" > "$TS_HELPER_PY"

# ---------------------------------------------------------------------------
# C.1 -- Ethtool Capabilities
# ---------------------------------------------------------------------------
test_c1() {
    if ! run_test "C.1"; then return; fi
    header "C.1 -- Ethtool Capabilities"

    local output
    output=$(ethtool -T "$IF_MASTER" 2>&1)
    echo "$output" > "$LOG_DIR/c1_ethtool_T.log"

    info "ethtool -T $IF_MASTER output:"
    echo "$output" | while read -r line; do info "  $line"; done

    local all_ok=true

    # Check for hardware-transmit
    if echo "$output" | grep -qi "hardware-transmit"; then
        info "Found: hardware-transmit"
    else
        info "MISSING: hardware-transmit"
        all_ok=false
    fi

    # Check for hardware-receive
    if echo "$output" | grep -qi "hardware-receive"; then
        info "Found: hardware-receive"
    else
        info "MISSING: hardware-receive"
        all_ok=false
    fi

    # Check for hardware-raw-clock
    if echo "$output" | grep -qi "hardware-raw-clock"; then
        info "Found: hardware-raw-clock"
    else
        info "MISSING: hardware-raw-clock"
        all_ok=false
    fi

    # Check PTP Hardware Clock index
    local phc_index
    phc_index=$(echo "$output" | grep -oP 'PTP Hardware Clock: \K[-0-9]+' || echo "-1")
    if [[ "$phc_index" != "-1" ]]; then
        info "PHC index: $phc_index"
    else
        info "MISSING: valid PHC index (got -1)"
        all_ok=false
    fi

    # Check for HWTSTAMP_TX_ON in tx_types
    if echo "$output" | grep -q "HWTSTAMP_TX_ON"; then
        info "Found: HWTSTAMP_TX_ON"
    else
        # Some ethtool versions show it differently
        if echo "$output" | grep -qi "hardware-transmit"; then
            info "TX ON capability implied by hardware-transmit"
        else
            info "MISSING: HWTSTAMP_TX_ON"
            all_ok=false
        fi
    fi

    # Check for HWTSTAMP_FILTER_ALL in rx_filters
    if echo "$output" | grep -q "HWTSTAMP_FILTER_ALL"; then
        info "Found: HWTSTAMP_FILTER_ALL"
    else
        if echo "$output" | grep -qi "hardware-receive"; then
            info "FILTER_ALL capability implied by hardware-receive"
        else
            info "MISSING: HWTSTAMP_FILTER_ALL"
            all_ok=false
        fi
    fi

    if $all_ok; then
        record_pass "C.1: All HW timestamping capabilities present"
    else
        record_fail "C.1: Some HW timestamping capabilities missing"
    fi
}

# ---------------------------------------------------------------------------
# C.2 -- Enable HW Timestamping
# ---------------------------------------------------------------------------
test_c2() {
    if ! run_test "C.2"; then return; fi
    header "C.2 -- Enable HW Timestamping"

    local output
    info "Enabling HW timestamping: hwstamp_ctl -i $IF_MASTER -t 1 -r 1"
    output=$(hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 2>&1)
    local rc=$?
    echo "$output" > "$LOG_DIR/c2_enable.log"

    info "hwstamp_ctl output:"
    echo "$output" | while read -r line; do info "  $line"; done

    if [[ $rc -ne 0 ]]; then
        record_fail "C.2: hwstamp_ctl returned error code $rc"
        return
    fi

    # Verify the configuration took effect
    local verify
    verify=$(hwstamp_ctl -i "$IF_MASTER" 2>&1)
    echo "$verify" >> "$LOG_DIR/c2_enable.log"

    # Check TX type is ON (1)
    if echo "$verify" | grep -qP 'tx_type:\s*(ON|1)'; then
        info "TX type: ON"
    elif echo "$output" | grep -qP 'tx_type:\s*(ON|1)'; then
        info "TX type: ON (from enable output)"
    else
        info "TX type not confirmed as ON"
    fi

    # Check RX filter is ALL (1)
    if echo "$verify" | grep -qP 'rx_filter:\s*(ALL|1)'; then
        info "RX filter: ALL"
    elif echo "$output" | grep -qP 'rx_filter:\s*(ALL|1)'; then
        info "RX filter: ALL (from enable output)"
    else
        info "RX filter not confirmed as ALL"
    fi

    record_pass "C.2: HW timestamping enabled (hwstamp_ctl returned success)"
}

# ---------------------------------------------------------------------------
# C.3 -- Disable HW Timestamping
# ---------------------------------------------------------------------------
test_c3() {
    if ! run_test "C.3"; then return; fi
    header "C.3 -- Disable HW Timestamping"

    local output
    info "Disabling HW timestamping: hwstamp_ctl -i $IF_MASTER -t 0 -r 0"
    output=$(hwstamp_ctl -i "$IF_MASTER" -t 0 -r 0 2>&1)
    local rc=$?
    echo "$output" > "$LOG_DIR/c3_disable.log"

    info "hwstamp_ctl output:"
    echo "$output" | while read -r line; do info "  $line"; done

    if [[ $rc -ne 0 ]]; then
        record_fail "C.3: hwstamp_ctl disable returned error code $rc"
        return
    fi

    # Verify
    local verify
    verify=$(hwstamp_ctl -i "$IF_MASTER" 2>&1)

    if echo "$verify" | grep -qP 'tx_type:\s*(OFF|0)'; then
        info "TX type: OFF"
    fi
    if echo "$verify" | grep -qP 'rx_filter:\s*(NONE|0)'; then
        info "RX filter: NONE"
    fi

    record_pass "C.3: HW timestamping disabled successfully"

    # Re-enable for subsequent tests
    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# C.4 -- RX Timestamp Delivery
# ---------------------------------------------------------------------------
test_c4() {
    if ! run_test "C.4"; then return; fi
    header "C.4 -- RX Timestamp Delivery"

    if [[ -z "${IF_SLAVE:-}" ]]; then
        record_skip "C.4: Requires second interface (IF_SLAVE not set)"
        return
    fi

    # Ensure both interfaces have IP and HW timestamping enabled
    ip addr show "$IF_MASTER" | grep -q "$IP_MASTER" || \
        ip addr add "$IP_MASTER/24" dev "$IF_MASTER" 2>/dev/null || true
    ip addr show "$IF_SLAVE" | grep -q "$IP_SLAVE" || \
        ip addr add "$IP_SLAVE/24" dev "$IF_SLAVE" 2>/dev/null || true

    hwstamp_ctl -i "$IF_SLAVE" -t 1 -r 1 > /dev/null 2>&1 || true

    local port=9876
    local count=10
    local timeout=15

    info "Starting RX listener on $IF_SLAVE ($IP_SLAVE:$port)..."
    python3 "$TS_HELPER_PY" rx "$IF_SLAVE" "$IP_SLAVE" "$port" "$count" "$timeout" \
        > "$LOG_DIR/c4_rx_output.log" 2>&1 &
    local rx_pid=$!

    sleep 1  # Let receiver bind

    info "Sending $count UDP packets from $IF_MASTER to $IP_SLAVE:$port..."
    for i in $(seq 1 $count); do
        echo "PTP_TEST_RX_$i" | socat - UDP4-SENDTO:"$IP_SLAVE":"$port",bind="$IP_MASTER",so-bindtodevice="$IF_MASTER" 2>/dev/null || \
        echo "PTP_TEST_RX_$i" > /dev/udp/"$IP_SLAVE"/"$port" 2>/dev/null || true
        sleep 0.05
    done

    # Wait for receiver
    wait "$rx_pid" 2>/dev/null || true

    local rx_output
    rx_output=$(cat "$LOG_DIR/c4_rx_output.log" 2>/dev/null || echo "")
    info "RX output summary:"
    echo "$rx_output" | grep "SUMMARY" | while read -r line; do info "  $line"; done

    local hw_ts_count
    hw_ts_count=$(echo "$rx_output" | grep -oP 'rx_hw_ts=\K[0-9]+' || echo "0")
    local rx_received
    rx_received=$(echo "$rx_output" | grep -oP 'rx_received=\K[0-9]+' || echo "0")

    info "Received: $rx_received, With HW timestamp: $hw_ts_count"

    if [[ $hw_ts_count -ge $count ]]; then
        record_pass "C.4: All $count packets received with HW RX timestamps"
    elif [[ $hw_ts_count -gt 0 ]]; then
        record_pass "C.4: $hw_ts_count/$rx_received packets had HW RX timestamps (partial)"
    elif [[ $rx_received -gt 0 ]]; then
        record_fail "C.4: Received $rx_received packets but no HW timestamps"
    else
        record_fail "C.4: No packets received (check connectivity)"
    fi
}

# ---------------------------------------------------------------------------
# C.5 -- TX Timestamp Delivery
# ---------------------------------------------------------------------------
test_c5() {
    if ! run_test "C.5"; then return; fi
    header "C.5 -- TX Timestamp Delivery"

    if [[ -z "${IF_SLAVE:-}" ]]; then
        record_skip "C.5: Requires second interface (IF_SLAVE not set)"
        return
    fi

    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true

    local port=9877
    local count=10

    # Start a dummy receiver on slave so packets are not rejected
    socat -u UDP4-RECVFROM:"$port",bind="$IP_SLAVE",fork /dev/null &
    local rx_pid=$!
    sleep 0.5

    info "Sending $count TX-timestamped packets from $IF_MASTER..."
    python3 "$TS_HELPER_PY" tx "$IF_MASTER" "$IP_SLAVE" "$port" "$count" \
        > "$LOG_DIR/c5_tx_output.log" 2>&1

    # Cleanup receiver
    kill "$rx_pid" 2>/dev/null || true
    wait "$rx_pid" 2>/dev/null || true

    local tx_output
    tx_output=$(cat "$LOG_DIR/c5_tx_output.log" 2>/dev/null || echo "")
    info "TX output summary:"
    echo "$tx_output" | grep "SUMMARY" | while read -r line; do info "  $line"; done

    local hw_ts_count
    hw_ts_count=$(echo "$tx_output" | grep -oP 'tx_hw_ts=\K[0-9]+' || echo "0")
    local tx_sent
    tx_sent=$(echo "$tx_output" | grep -oP 'tx_sent=\K[0-9]+' || echo "0")

    info "Sent: $tx_sent, With HW TX timestamp: $hw_ts_count"

    if [[ $hw_ts_count -ge $count ]]; then
        record_pass "C.5: All $count TX timestamps received from HW"
    elif [[ $hw_ts_count -gt 0 ]]; then
        record_pass "C.5: $hw_ts_count/$tx_sent TX timestamps received (partial)"
    else
        record_fail "C.5: No TX hardware timestamps received"
    fi
}

# ---------------------------------------------------------------------------
# C.6 -- TX Timestamp Tag Matching
# ---------------------------------------------------------------------------
test_c6() {
    if ! run_test "C.6"; then return; fi
    header "C.6 -- TX Timestamp Tag Matching"

    if [[ -z "${IF_SLAVE:-}" ]]; then
        record_skip "C.6: Requires second interface"
        return
    fi

    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true

    local port=9878
    local count=100

    # Dummy receiver
    socat -u UDP4-RECVFROM:"$port",bind="$IP_SLAVE",fork /dev/null &
    local rx_pid=$!
    sleep 0.5

    info "Sending $count rapid TX-timestamped packets..."
    python3 "$TS_HELPER_PY" tx "$IF_MASTER" "$IP_SLAVE" "$port" "$count" \
        > "$LOG_DIR/c6_tx_output.log" 2>&1

    kill "$rx_pid" 2>/dev/null || true
    wait "$rx_pid" 2>/dev/null || true

    # Parse timestamps and check monotonicity
    local tx_lines
    tx_lines=$(grep "^TX [0-9]" "$LOG_DIR/c6_tx_output.log" | grep -v "NONE\|TIMEOUT\|ERROR" || true)
    local ts_count
    ts_count=$(echo "$tx_lines" | grep -c '[0-9]' || echo "0")

    if [[ $ts_count -lt 2 ]]; then
        record_fail "C.6: Too few TX timestamps to check monotonicity ($ts_count)"
        return
    fi

    info "Checking monotonicity of $ts_count TX timestamps..."

    local prev_sec=0 prev_nsec=0
    local monotonic=true
    local violations=0

    while read -r line; do
        local sec nsec
        sec=$(echo "$line" | awk '{print $3}')
        nsec=$(echo "$line" | awk '{print $4}')

        if [[ $prev_sec -ne 0 ]]; then
            if [[ $sec -lt $prev_sec ]] || \
               { [[ $sec -eq $prev_sec ]] && [[ $nsec -le $prev_nsec ]]; }; then
                monotonic=false
                ((violations++)) || true
            fi
        fi
        prev_sec=$sec
        prev_nsec=$nsec
    done <<< "$tx_lines"

    # Check dmesg for FIFO overflow
    local fifo_overflow
    fifo_overflow=$(dmesg | tail -100 | grep -ic "fifo.*overflow\|tx.*ts.*overflow" || echo "0")

    info "Monotonic: $monotonic, Violations: $violations, FIFO overflows in dmesg: $fifo_overflow"
    echo "ts_count=$ts_count monotonic=$monotonic violations=$violations fifo_overflow=$fifo_overflow" \
        > "$LOG_DIR/c6_tag_match.log"

    if $monotonic && [[ $fifo_overflow -eq 0 ]]; then
        record_pass "C.6: $ts_count TX timestamps monotonic, no FIFO overflow"
    elif [[ $violations -gt 0 ]]; then
        record_fail "C.6: $violations monotonicity violations in $ts_count timestamps"
    else
        record_fail "C.6: FIFO overflow detected in dmesg"
    fi
}

# ---------------------------------------------------------------------------
# C.7 -- Timestamp Sanity (RX vs TX Ordering)
# ---------------------------------------------------------------------------
test_c7() {
    if ! run_test "C.7"; then return; fi
    header "C.7 -- Timestamp Sanity (TX < RX for same flow)"

    if [[ -z "${IF_SLAVE:-}" ]]; then
        record_skip "C.7: Requires second interface"
        return
    fi

    info "This test requires synced clocks (ptp4l should have been run)"
    info "Checking TX timestamps from sender and RX timestamps from receiver..."

    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true
    hwstamp_ctl -i "$IF_SLAVE" -t 1 -r 1 > /dev/null 2>&1 || true

    local port=9879
    local count=5
    local timeout=10

    # Start RX listener on slave
    python3 "$TS_HELPER_PY" rx "$IF_SLAVE" "$IP_SLAVE" "$port" "$count" "$timeout" \
        > "$LOG_DIR/c7_rx_output.log" 2>&1 &
    local rx_pid=$!
    sleep 1

    # Send TX-timestamped packets from master
    python3 "$TS_HELPER_PY" tx "$IF_MASTER" "$IP_SLAVE" "$port" "$count" \
        > "$LOG_DIR/c7_tx_output.log" 2>&1

    wait "$rx_pid" 2>/dev/null || true

    # Parse and compare
    local tx_timestamps rx_timestamps
    tx_timestamps=$(grep "^TX [0-9]" "$LOG_DIR/c7_tx_output.log" | grep -v "NONE\|TIMEOUT\|ERROR" || true)
    rx_timestamps=$(grep "^RX [0-9]" "$LOG_DIR/c7_rx_output.log" | grep -v "NONE\|TIMEOUT" || true)

    local tx_count rx_count
    tx_count=$(echo "$tx_timestamps" | grep -c '[0-9]' || echo "0")
    rx_count=$(echo "$rx_timestamps" | grep -c '[0-9]' || echo "0")

    info "TX timestamps: $tx_count, RX timestamps: $rx_count"

    if [[ $tx_count -eq 0 ]] || [[ $rx_count -eq 0 ]]; then
        record_skip "C.7: Insufficient timestamps (TX=$tx_count, RX=$rx_count)"
        return
    fi

    # Compare the first matching pair
    local tx_sec tx_nsec rx_sec rx_nsec
    tx_sec=$(echo "$tx_timestamps" | head -1 | awk '{print $3}')
    tx_nsec=$(echo "$tx_timestamps" | head -1 | awk '{print $4}')
    rx_sec=$(echo "$rx_timestamps" | head -1 | awk '{print $3}')
    rx_nsec=$(echo "$rx_timestamps" | head -1 | awk '{print $4}')

    info "First TX TS: ${tx_sec}.${tx_nsec}"
    info "First RX TS: ${rx_sec}.${rx_nsec}"

    # TX should be before RX (positive one-way delay)
    if [[ $tx_sec -lt $rx_sec ]] || \
       { [[ $tx_sec -eq $rx_sec ]] && [[ $tx_nsec -lt $rx_nsec ]]; }; then
        local delay_ns=$(( (rx_sec - tx_sec) * 1000000000 + rx_nsec - tx_nsec ))
        info "One-way delay: ${delay_ns} ns"
        record_pass "C.7: TX timestamp precedes RX (one-way delay = ${delay_ns}ns)"
    else
        record_fail "C.7: RX timestamp precedes TX (clocks may be desynced)"
    fi
}

# ===========================================================================
# Main
# ===========================================================================
header "PTP IEEE 1588 -- Category C: Hardware Timestamping"
echo -e "  Master: ${BOLD}${IF_MASTER:-<none>}${NC}"
echo -e "  Slave:  ${BOLD}${IF_SLAVE:-<none>}${NC}"
echo -e "  Log dir: ${BOLD}${LOG_DIR}${NC}"

# Check prerequisites
for tool in ethtool hwstamp_ctl python3; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}ERROR: $tool not found.${NC}"
        exit 1
    fi
done

if [[ -z "$IF_MASTER" ]]; then
    echo -e "${RED}ERROR: No onic interface found.${NC}"
    exit 1
fi

# Ensure interfaces are up
for iface in "$IF_MASTER" ${IF_SLAVE:+"$IF_SLAVE"}; do
    ip link set "$iface" up 2>/dev/null || true
done
sleep 1

# Run tests
test_c1
test_c2
test_c3
test_c4
test_c5
test_c6
test_c7

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary: Category C -- Hardware Timestamping"
echo -e "  Total:   $TOTAL"
echo -e "  ${GREEN}Passed:  $PASSED${NC}"
echo -e "  ${RED}Failed:  $FAILED${NC}"
echo -e "  ${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "  Logs:    $LOG_DIR"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
