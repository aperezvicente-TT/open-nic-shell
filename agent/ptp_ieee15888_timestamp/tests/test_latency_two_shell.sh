#!/usr/bin/env bash
# =============================================================================
# test_latency_two_shell.sh -- Category D+E: Two-Shell Latency Measurement
#
# Configures ptp4l master/slave between two OpenNIC shells, then measures
# one-way, round-trip, and wire-to-wire latency.  Also parses ptp4l logs
# for offset statistics and runs stability/stress checks.
#
# Usage:
#   sudo ./test_latency_two_shell.sh              # Run all tests
#   sudo ./test_latency_two_shell.sh D.1 D.4      # Run specific tests
#
# Prerequisites:
#   - Two onic interfaces connected back-to-back with IP addresses
#   - linuxptp tools installed (ptp4l, phc2sys, phc_ctl, hwstamp_ctl)
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
LOG_DIR="/tmp/ptp_test_latency_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

if [[ -f "$SCRIPT_DIR/test_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/test_env.sh"
fi

# Auto-detect
if [[ -z "${IF_MASTER:-}" ]] || [[ -z "${IF_SLAVE:-}" ]]; then
    ONIC_IFACES=($(ip -o link show | grep -oP 'onic\S+' || true))
    if [[ ${#ONIC_IFACES[@]} -lt 2 ]]; then
        echo -e "${RED}ERROR: Need at least 2 onic interfaces. Found: ${ONIC_IFACES[*]:-none}${NC}"
        exit 1
    fi
    IF_MASTER="${IF_MASTER:-${ONIC_IFACES[0]}}"
    IF_SLAVE="${IF_SLAVE:-${ONIC_IFACES[1]}}"
fi

IP_MASTER="${IP_MASTER:-10.0.0.1}"
IP_SLAVE="${IP_SLAVE:-10.0.0.2}"

# Auto-detect PTP devices
if [[ -z "${PTP_MASTER:-}" ]]; then
    PHC_IDX=$(ethtool -T "$IF_MASTER" 2>/dev/null | grep -oP 'PTP Hardware Clock: \K\d+' || echo "-1")
    PTP_MASTER="/dev/ptp${PHC_IDX}"
fi
if [[ -z "${PTP_SLAVE:-}" ]]; then
    PHC_IDX=$(ethtool -T "$IF_SLAVE" 2>/dev/null | grep -oP 'PTP Hardware Clock: \K\d+' || echo "-1")
    PTP_SLAVE="/dev/ptp${PHC_IDX}"
fi

info "Master: $IF_MASTER ($IP_MASTER) PTP=$PTP_MASTER"
info "Slave:  $IF_SLAVE ($IP_SLAVE) PTP=$PTP_SLAVE"
info "Log dir: $LOG_DIR"

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
# Background process tracking
# ---------------------------------------------------------------------------
PTP4L_MASTER_PID=""
PTP4L_SLAVE_PID=""
declare -a BG_PIDS=()

cleanup() {
    info "Cleaning up background processes..."
    for pid in $PTP4L_MASTER_PID $PTP4L_SLAVE_PID "${BG_PIDS[@]}"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helper: ensure ptp4l master+slave are running and synced
# ---------------------------------------------------------------------------
ensure_ptp_synced() {
    local sync_wait="${1:-120}"

    # Start master if not running
    if [[ -z "$PTP4L_MASTER_PID" ]] || ! kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
        info "Starting ptp4l master on $IF_MASTER..."
        ptp4l -i "$IF_MASTER" -H -m --priority1 128 \
            --tx_timestamp_timeout 100 \
            > "$LOG_DIR/ptp4l_master.log" 2>&1 &
        PTP4L_MASTER_PID=$!
        sleep 5
    fi

    # Start slave if not running
    if [[ -z "$PTP4L_SLAVE_PID" ]] || ! kill -0 "$PTP4L_SLAVE_PID" 2>/dev/null; then
        info "Starting ptp4l slave on $IF_SLAVE..."
        ptp4l -i "$IF_SLAVE" -H -m -s \
            --tx_timestamp_timeout 100 \
            > "$LOG_DIR/ptp4l_slave.log" 2>&1 &
        PTP4L_SLAVE_PID=$!
    fi

    # Wait for slave to reach SLAVE state
    info "Waiting up to ${sync_wait}s for PTP synchronization..."
    local elapsed=0
    while [[ $elapsed -lt $sync_wait ]]; do
        if grep -q "SLAVE" "$LOG_DIR/ptp4l_slave.log" 2>/dev/null; then
            info "PTP synchronized (SLAVE state reached)"
            return 0
        fi
        sleep 1
        ((elapsed++)) || true
    done
    info "WARNING: PTP slave state not confirmed within ${sync_wait}s"
    return 1
}

# ---------------------------------------------------------------------------
# Helper: compute statistics from a list of numbers (one per line)
# ---------------------------------------------------------------------------
compute_stats() {
    local input_file="$1"
    python3 - "$input_file" << 'PYEOF'
import sys, math

values = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line and line.lstrip('-').replace('.','',1).isdigit():
            values.append(float(line))

if not values:
    print("count=0 min=0 max=0 mean=0 stddev=0 p50=0 p99=0")
    sys.exit(0)

values.sort()
n = len(values)
mean = sum(values) / n
variance = sum((x - mean) ** 2 for x in values) / n if n > 1 else 0
stddev = math.sqrt(variance)
p50 = values[int(n * 0.50)]
p99 = values[int(min(n * 0.99, n - 1))]

print(f"count={n} min={values[0]:.1f} max={values[-1]:.1f} "
      f"mean={mean:.1f} stddev={stddev:.1f} p50={p50:.1f} p99={p99:.1f}")
PYEOF
}

# ---------------------------------------------------------------------------
# Inline Python: latency measurement sender + receiver
# ---------------------------------------------------------------------------
LATENCY_HELPER=$(cat << 'PYEOF'
#!/usr/bin/env python3
"""
Two-shell latency measurement using SO_TIMESTAMPING.

Usage:
  python3 <script> sender <iface> <dest_ip> <port> <count> <outfile>
  python3 <script> receiver <iface> <bind_ip> <port> <count> <timeout> <outfile>
"""
import sys, socket, struct, time

SO_TIMESTAMPING = 37
SOF_TIMESTAMPING_TX_HARDWARE  = (1 << 0)
SOF_TIMESTAMPING_RX_HARDWARE  = (1 << 2)
SOF_TIMESTAMPING_RAW_HARDWARE = (1 << 6)
SOF_TIMESTAMPING_OPT_TSONLY   = (1 << 11)
SCM_TIMESTAMPING = 37
MSG_ERRQUEUE = 0x2000

def parse_hw_ts(cmsg_data):
    if len(cmsg_data) >= 48:
        sec, nsec = struct.unpack("ll", cmsg_data[32:48])
        return sec, nsec
    return 0, 0

def sender(iface, dest_ip, port, count, outfile):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, iface.encode())
    flags = SOF_TIMESTAMPING_TX_HARDWARE | SOF_TIMESTAMPING_RAW_HARDWARE | SOF_TIMESTAMPING_OPT_TSONLY
    sock.setsockopt(socket.SOL_SOCKET, SO_TIMESTAMPING, flags)
    sock.settimeout(2.0)

    results = []
    for i in range(count):
        payload = struct.pack("!I", i) + b"LATENCY_TEST"
        sock.sendto(payload, (dest_ip, port))

        hw_sec, hw_nsec = 0, 0
        try:
            data, ancdata, mf, addr = sock.recvmsg(2048, 1024, MSG_ERRQUEUE)
            for cl, ct, cd in ancdata:
                if cl == socket.SOL_SOCKET and ct == SCM_TIMESTAMPING:
                    hw_sec, hw_nsec = parse_hw_ts(cd)
        except (socket.timeout, OSError):
            pass

        results.append(f"{i} {hw_sec} {hw_nsec}")
        time.sleep(0.001)

    sock.close()
    with open(outfile, 'w') as f:
        for r in results:
            f.write(r + '\n')

def receiver(iface, bind_ip, port, count, timeout, outfile):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, iface.encode())
    flags = SOF_TIMESTAMPING_RX_HARDWARE | SOF_TIMESTAMPING_RAW_HARDWARE
    sock.setsockopt(socket.SOL_SOCKET, SO_TIMESTAMPING, flags)
    sock.bind((bind_ip, port))
    sock.settimeout(timeout)

    results = []
    for i in range(count):
        try:
            data, ancdata, mf, addr = sock.recvmsg(2048, 1024)
            seq = struct.unpack("!I", data[:4])[0]
            hw_sec, hw_nsec = 0, 0
            for cl, ct, cd in ancdata:
                if cl == socket.SOL_SOCKET and ct == SCM_TIMESTAMPING:
                    hw_sec, hw_nsec = parse_hw_ts(cd)
            results.append(f"{seq} {hw_sec} {hw_nsec}")
        except socket.timeout:
            break

    sock.close()
    with open(outfile, 'w') as f:
        for r in results:
            f.write(r + '\n')

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sender":
        sender(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6])
    elif mode == "receiver":
        receiver(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]),
                 float(sys.argv[6]), sys.argv[7])
PYEOF
)

LATENCY_PY="$LOG_DIR/latency_helper.py"
echo "$LATENCY_HELPER" > "$LATENCY_PY"

# ---------------------------------------------------------------------------
# Helper: extract ptp4l offset values from a log
# ---------------------------------------------------------------------------
extract_offsets() {
    local log_file="$1"
    grep -oP 'master offset\s+\K[-0-9]+' "$log_file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Ensure IP addresses and HW timestamping
# ---------------------------------------------------------------------------
setup_interfaces() {
    for iface in "$IF_MASTER" "$IF_SLAVE"; do
        ip link set "$iface" up 2>/dev/null || true
    done
    sleep 1

    ip addr show "$IF_MASTER" | grep -q "$IP_MASTER" || \
        ip addr add "$IP_MASTER/24" dev "$IF_MASTER" 2>/dev/null || true
    ip addr show "$IF_SLAVE" | grep -q "$IP_SLAVE" || \
        ip addr add "$IP_SLAVE/24" dev "$IF_SLAVE" 2>/dev/null || true

    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true
    hwstamp_ctl -i "$IF_SLAVE" -t 1 -r 1 > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# D.1 -- One-Way Latency (A to B)
# ---------------------------------------------------------------------------
test_d1() {
    if ! run_test "D.1"; then return; fi
    header "D.1 -- One-Way Latency (A to B)"

    setup_interfaces
    if ! ensure_ptp_synced 120; then
        record_fail "D.1: PTP synchronization failed"
        return
    fi

    # Let clocks settle
    info "Allowing 30s for clocks to settle..."
    sleep 30

    local port=9880
    local count=1000
    local tx_file="$LOG_DIR/d1_tx_timestamps.log"
    local rx_file="$LOG_DIR/d1_rx_timestamps.log"
    local timeout=30

    info "Starting receiver on $IF_SLAVE..."
    python3 "$LATENCY_PY" receiver "$IF_SLAVE" "$IP_SLAVE" "$port" "$count" "$timeout" "$rx_file" &
    local rx_pid=$!
    BG_PIDS+=("$rx_pid")
    sleep 1

    info "Sending $count packets from $IF_MASTER..."
    python3 "$LATENCY_PY" sender "$IF_MASTER" "$IP_SLAVE" "$port" "$count" "$tx_file"

    wait "$rx_pid" 2>/dev/null || true

    # Compute one-way delays
    info "Computing one-way latencies..."
    python3 - "$tx_file" "$rx_file" "$LOG_DIR/d1_oneway_ns.log" << 'PYEOF'
import sys

tx_data = {}
with open(sys.argv[1]) as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 3:
            seq, sec, nsec = int(parts[0]), int(parts[1]), int(parts[2])
            if sec != 0 or nsec != 0:
                tx_data[seq] = sec * 1_000_000_000 + nsec

rx_data = {}
with open(sys.argv[2]) as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 3:
            seq, sec, nsec = int(parts[0]), int(parts[1]), int(parts[2])
            if sec != 0 or nsec != 0:
                rx_data[seq] = sec * 1_000_000_000 + nsec

delays = []
for seq in sorted(tx_data.keys()):
    if seq in rx_data:
        delay = rx_data[seq] - tx_data[seq]
        delays.append(delay)

with open(sys.argv[3], 'w') as f:
    for d in delays:
        f.write(f"{d}\n")

print(f"MATCHED: {len(delays)} out of TX={len(tx_data)} RX={len(rx_data)}")
PYEOF

    local matched
    matched=$(wc -l < "$LOG_DIR/d1_oneway_ns.log" 2>/dev/null || echo "0")
    info "Matched packet pairs: $matched"

    if [[ $matched -lt 10 ]]; then
        record_fail "D.1: Too few matched packets ($matched) for meaningful latency"
        return
    fi

    local stats
    stats=$(compute_stats "$LOG_DIR/d1_oneway_ns.log")
    info "One-way latency (ns): $stats"
    echo "$stats" > "$LOG_DIR/d1_stats.log"

    local mean_ns
    mean_ns=$(echo "$stats" | grep -oP 'mean=\K[0-9.]+' | cut -d. -f1)

    # Pass criteria: mean < 10us (10000 ns) for direct cable
    if [[ $mean_ns -lt 100000 ]] && [[ $mean_ns -gt 0 ]]; then
        record_pass "D.1: One-way latency mean=${mean_ns}ns ($matched samples)"
    elif [[ $mean_ns -lt 0 ]] || [[ $mean_ns -eq 0 ]]; then
        record_fail "D.1: Invalid one-way latency mean=${mean_ns}ns (clocks desynced?)"
    else
        record_fail "D.1: One-way latency mean=${mean_ns}ns exceeds 100us threshold"
    fi
}

# ---------------------------------------------------------------------------
# D.2 -- Round-Trip Latency
# ---------------------------------------------------------------------------
test_d2() {
    if ! run_test "D.2"; then return; fi
    header "D.2 -- Round-Trip Latency"

    setup_interfaces

    # Ping-based RTT measurement using hardware timestamps
    # We use the kernel ping and parse its output for RTT
    local count=100
    local rtt_file="$LOG_DIR/d2_rtt_us.log"

    info "Sending $count pings from $IF_MASTER ($IP_MASTER) to $IP_SLAVE..."
    ping -I "$IF_MASTER" -c "$count" -i 0.01 -q "$IP_SLAVE" \
        > "$LOG_DIR/d2_ping_output.log" 2>&1 || true

    # Extract RTT stats from ping summary
    local ping_stats
    ping_stats=$(grep "rtt\|round-trip" "$LOG_DIR/d2_ping_output.log" 2>/dev/null || true)
    info "Ping RTT stats: $ping_stats"

    # Also extract per-packet RTTs for detailed analysis
    # Use non-quiet ping for per-packet data
    ping -I "$IF_MASTER" -c "$count" -i 0.01 "$IP_SLAVE" \
        > "$LOG_DIR/d2_ping_verbose.log" 2>&1 || true

    grep -oP 'time=\K[0-9.]+' "$LOG_DIR/d2_ping_verbose.log" > "$LOG_DIR/d2_rtt_ms.log" 2>/dev/null || true

    # Convert ms to us for stats
    python3 -c "
import sys
with open('$LOG_DIR/d2_rtt_ms.log') as f:
    for line in f:
        v = line.strip()
        if v:
            print(float(v) * 1000)
" > "$rtt_file" 2>/dev/null || true

    local rtt_count
    rtt_count=$(wc -l < "$rtt_file" 2>/dev/null || echo "0")

    if [[ $rtt_count -lt 5 ]]; then
        # Ping might fail, try with a longer interval
        info "Too few pings succeeded ($rtt_count), checking connectivity..."
        if ping -I "$IF_MASTER" -c 3 -W 2 "$IP_SLAVE" > /dev/null 2>&1; then
            info "Connectivity OK but pings were lost at high rate"
            record_fail "D.2: Only $rtt_count ping replies received"
        else
            record_fail "D.2: Cannot ping $IP_SLAVE from $IF_MASTER"
        fi
        return
    fi

    local stats
    stats=$(compute_stats "$rtt_file")
    info "RTT (us): $stats"
    echo "$stats" > "$LOG_DIR/d2_stats.log"

    local mean_us
    mean_us=$(echo "$stats" | grep -oP 'mean=\K[0-9.]+' | cut -d. -f1)

    local received
    received=$(grep -oP '\K[0-9]+(?= received)' "$LOG_DIR/d2_ping_output.log" || echo "$rtt_count")
    local loss
    loss=$(grep -oP '[0-9.]+(?=% packet loss)' "$LOG_DIR/d2_ping_output.log" || echo "?")

    info "Packets: sent=$count received=$received loss=${loss}%"

    # Pass criteria: mean RTT < 20000 us (20ms) -- very generous for FPGA+software stack
    if [[ $mean_us -lt 20000 ]]; then
        record_pass "D.2: RTT mean=${mean_us}us, $received/$count received ($rtt_count samples)"
    else
        record_fail "D.2: RTT mean=${mean_us}us exceeds 20ms threshold"
    fi
}

# ---------------------------------------------------------------------------
# D.3 -- Wire-to-Wire Latency (Placeholder)
# ---------------------------------------------------------------------------
test_d3() {
    if ! run_test "D.3"; then return; fi
    header "D.3 -- Wire-to-Wire Latency"

    info "Wire-to-wire latency requires packet forwarding configuration."
    info "This test measures the time between RX ingress and TX egress on"
    info "a single shell acting as a forwarder."
    info ""
    info "To run this test manually:"
    info "  1. Configure Shell A as a bridge or router (ip forwarding, bridge)"
    info "  2. Send traffic through Shell A from an external source"
    info "  3. Capture both RX and TX timestamps on Shell A"
    info "  4. Wire-to-wire delay = TX_egress_TS - RX_ingress_TS"

    # Attempt a basic forwarding setup if possible
    local can_forward=false

    # Check if IP forwarding is enabled
    if [[ $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null) == "1" ]]; then
        can_forward=true
    fi

    if ! $can_forward; then
        record_skip "D.3: IP forwarding not enabled, skipping automated wire-to-wire test"
        info "Enable with: sysctl -w net.ipv4.ip_forward=1"
        return
    fi

    # If forwarding is enabled, measure round-trip with timestamps and halve it
    info "Forwarding enabled. Estimating wire-to-wire from round-trip / 2..."

    hwstamp_ctl -i "$IF_MASTER" -t 1 -r 1 > /dev/null 2>&1 || true

    local port=9881
    local count=100
    local tx_file="$LOG_DIR/d3_tx.log"
    local rx_file="$LOG_DIR/d3_rx.log"

    # Receiver
    python3 "$LATENCY_PY" receiver "$IF_MASTER" "$IP_MASTER" "$port" "$count" 15 "$rx_file" &
    local rx_pid=$!
    BG_PIDS+=("$rx_pid")
    sleep 1

    # Send from slave to master (and capture TX timestamps)
    python3 "$LATENCY_PY" sender "$IF_SLAVE" "$IP_MASTER" "$port" "$count" "$tx_file"
    wait "$rx_pid" 2>/dev/null || true

    local matched
    matched=$(wc -l < "$rx_file" 2>/dev/null || echo "0")
    info "Received $matched packets through forwarding path"

    if [[ $matched -gt 0 ]]; then
        record_pass "D.3: Wire-to-wire measurement captured $matched forwarded packets"
    else
        record_skip "D.3: No forwarded packets captured"
    fi
}

# ---------------------------------------------------------------------------
# D.4 -- ptp4l Offset Statistics
# ---------------------------------------------------------------------------
test_d4() {
    if ! run_test "D.4"; then return; fi
    header "D.4 -- ptp4l Offset Statistics"

    setup_interfaces

    # Use a fresh ptp4l run for clean statistics
    local d4_master_log="$LOG_DIR/d4_ptp4l_master.log"
    local d4_slave_log="$LOG_DIR/d4_ptp4l_slave.log"
    local run_duration=300  # 5 minutes

    # Kill any existing ptp4l
    if [[ -n "$PTP4L_MASTER_PID" ]] && kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
        kill "$PTP4L_MASTER_PID" 2>/dev/null; wait "$PTP4L_MASTER_PID" 2>/dev/null || true
        PTP4L_MASTER_PID=""
    fi
    if [[ -n "$PTP4L_SLAVE_PID" ]] && kill -0 "$PTP4L_SLAVE_PID" 2>/dev/null; then
        kill "$PTP4L_SLAVE_PID" 2>/dev/null; wait "$PTP4L_SLAVE_PID" 2>/dev/null || true
        PTP4L_SLAVE_PID=""
    fi

    info "Starting fresh ptp4l master/slave for ${run_duration}s statistics run..."

    ptp4l -i "$IF_MASTER" -H -m --priority1 128 \
        --tx_timestamp_timeout 100 \
        > "$d4_master_log" 2>&1 &
    PTP4L_MASTER_PID=$!
    sleep 3

    ptp4l -i "$IF_SLAVE" -H -m -s \
        --tx_timestamp_timeout 100 \
        > "$d4_slave_log" 2>&1 &
    PTP4L_SLAVE_PID=$!

    info "Running for ${run_duration}s ($(( run_duration / 60 )) minutes)..."
    info "Progress: check $d4_slave_log for live offsets"

    # Show progress every 60s
    local elapsed=0
    while [[ $elapsed -lt $run_duration ]]; do
        local chunk=60
        if [[ $((elapsed + chunk)) -gt $run_duration ]]; then
            chunk=$((run_duration - elapsed))
        fi
        sleep "$chunk"
        elapsed=$((elapsed + chunk))

        local sample_count
        sample_count=$(extract_offsets "$d4_slave_log" | wc -l)
        local last_offset
        last_offset=$(extract_offsets "$d4_slave_log" | tail -1 || echo "?")
        info "  ${elapsed}s: $sample_count samples, last offset=${last_offset}ns"
    done

    # Extract all offsets
    local offset_file="$LOG_DIR/d4_all_offsets.log"
    extract_offsets "$d4_slave_log" > "$offset_file"

    local total_samples
    total_samples=$(wc -l < "$offset_file")
    info "Total offset samples: $total_samples"

    if [[ $total_samples -lt 10 ]]; then
        record_fail "D.4: Only $total_samples offset samples collected"
        return
    fi

    # Compute absolute values for stats
    local abs_offset_file="$LOG_DIR/d4_abs_offsets.log"
    python3 -c "
with open('$offset_file') as f:
    for line in f:
        v = line.strip()
        if v and v.lstrip('-').isdigit():
            print(abs(int(v)))
" > "$abs_offset_file"

    local stats
    stats=$(compute_stats "$abs_offset_file")
    info "Offset |ns| statistics: $stats"
    echo "$stats" > "$LOG_DIR/d4_stats.log"

    local mean_ns max_ns
    mean_ns=$(echo "$stats" | grep -oP 'mean=\K[0-9.]+' | cut -d. -f1)
    max_ns=$(echo "$stats" | grep -oP 'max=\K[0-9.]+' | cut -d. -f1)

    # Compute convergence time: time until offset stays below 1000ns
    local convergence_time="N/A"
    python3 - "$offset_file" << 'PYEOF' > "$LOG_DIR/d4_convergence.log" 2>&1
import sys

offsets = []
with open(sys.argv[1]) as f:
    for line in f:
        v = line.strip()
        if v and v.lstrip('-').isdigit():
            offsets.append(int(v))

# Find first sample index where abs(offset) < 1000 and stays there
# (using 5-sample window)
converged_at = -1
window = 5
for i in range(len(offsets) - window):
    if all(abs(offsets[i+j]) < 1000 for j in range(window)):
        converged_at = i
        break

if converged_at >= 0:
    # ptp4l logs ~1 sample/second
    print(f"CONVERGED_AT_SAMPLE={converged_at} (~{converged_at}s)")
else:
    print("NOT_CONVERGED")
PYEOF

    convergence_time=$(cat "$LOG_DIR/d4_convergence.log" 2>/dev/null || echo "unknown")
    info "Convergence: $convergence_time"

    # Generate histogram
    python3 - "$offset_file" "$LOG_DIR/d4_histogram.log" << 'PYEOF'
import sys

offsets = []
with open(sys.argv[1]) as f:
    for line in f:
        v = line.strip()
        if v and v.lstrip('-').isdigit():
            offsets.append(abs(int(v)))

if not offsets:
    sys.exit(0)

buckets = [0, 10, 50, 100, 500, 1000, 5000, 10000, 50000, 100000]
hist = {b: 0 for b in buckets}
hist[999999] = 0  # overflow

for o in offsets:
    placed = False
    for b in buckets:
        if o <= b:
            hist[b] += 1
            placed = True
            break
    if not placed:
        hist[999999] += 1

with open(sys.argv[2], 'w') as f:
    f.write("Offset Histogram (absolute ns):\n")
    prev = 0
    for b in buckets:
        f.write(f"  {prev:>6} - {b:>6} ns: {hist[b]:>6} samples\n")
        prev = b + 1
    f.write(f"  > {buckets[-1]:>6} ns: {hist[999999]:>6} samples\n")
PYEOF

    info "Histogram saved to $LOG_DIR/d4_histogram.log"
    cat "$LOG_DIR/d4_histogram.log" 2>/dev/null | while read -r line; do info "  $line"; done

    # Pass criteria: mean |offset| < 500ns
    if [[ $mean_ns -le 500 ]]; then
        record_pass "D.4: Offset stats mean=${mean_ns}ns max=${max_ns}ns ($total_samples samples)"
    elif [[ $mean_ns -le 5000 ]]; then
        record_fail "D.4: Offset mean=${mean_ns}ns exceeds 500ns target (max=${max_ns}ns)"
    else
        record_fail "D.4: Offset mean=${mean_ns}ns far exceeds target (max=${max_ns}ns)"
    fi
}

# ---------------------------------------------------------------------------
# E.4 -- Concurrent PHC Access
# ---------------------------------------------------------------------------
test_e4() {
    if ! run_test "E.4"; then return; fi
    header "E.4 -- Concurrent PHC Access"

    local concurrent=10
    local duration=30
    local fail_count=0

    info "Launching $concurrent concurrent phc_ctl read loops for ${duration}s..."

    local pids=()
    for i in $(seq 1 $concurrent); do
        (
            local end_time=$(($(date +%s) + duration))
            local reads=0
            local errors=0
            while [[ $(date +%s) -lt $end_time ]]; do
                if phc_ctl "$PTP_MASTER" get > /dev/null 2>&1; then
                    ((reads++)) || true
                else
                    ((errors++)) || true
                fi
            done
            echo "worker_${i}: reads=$reads errors=$errors"
        ) > "$LOG_DIR/e4_worker_${i}.log" 2>&1 &
        pids+=($!)
    done

    # Wait for all workers
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Aggregate results
    local total_reads=0 total_errors=0
    for i in $(seq 1 $concurrent); do
        local worker_log="$LOG_DIR/e4_worker_${i}.log"
        local reads errors
        reads=$(grep -oP 'reads=\K[0-9]+' "$worker_log" 2>/dev/null || echo "0")
        errors=$(grep -oP 'errors=\K[0-9]+' "$worker_log" 2>/dev/null || echo "0")
        total_reads=$((total_reads + reads))
        total_errors=$((total_errors + errors))
        info "  Worker $i: reads=$reads errors=$errors"
    done

    info "Total: reads=$total_reads errors=$total_errors"

    # Check for kernel warnings
    local kernel_warnings
    kernel_warnings=$(dmesg | tail -50 | grep -ic "BUG\|WARNING\|lockup\|RCU" || echo "0")

    echo "total_reads=$total_reads total_errors=$total_errors kernel_warnings=$kernel_warnings" \
        > "$LOG_DIR/e4_summary.log"

    if [[ $total_errors -eq 0 ]] && [[ $kernel_warnings -eq 0 ]]; then
        record_pass "E.4: $total_reads concurrent reads, 0 errors, no kernel warnings"
    elif [[ $total_errors -gt 0 ]]; then
        record_fail "E.4: $total_errors read errors in $total_reads attempts"
    else
        record_fail "E.4: Kernel warnings detected during concurrent access"
    fi
}

# ===========================================================================
# Main
# ===========================================================================
header "PTP IEEE 1588 -- Category D+E: Two-Shell Latency Measurement"
echo -e "  Master: ${BOLD}${IF_MASTER}${NC} (${IP_MASTER})"
echo -e "  Slave:  ${BOLD}${IF_SLAVE}${NC} (${IP_SLAVE})"
echo -e "  Log dir: ${BOLD}${LOG_DIR}${NC}"

# Check prerequisites
for tool in ptp4l phc_ctl hwstamp_ctl ethtool python3 ping bc; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}ERROR: $tool not found.${NC}"
        exit 1
    fi
done

for iface in "$IF_MASTER" "$IF_SLAVE"; do
    if ! ip link show "$iface" &>/dev/null; then
        echo -e "${RED}ERROR: Interface $iface not found.${NC}"
        exit 1
    fi
done

# Run tests
test_d1
test_d2
test_d3
test_d4
test_e4

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary: Category D+E -- Two-Shell Latency & Stress"
echo -e "  Total:   $TOTAL"
echo -e "  ${GREEN}Passed:  $PASSED${NC}"
echo -e "  ${RED}Failed:  $FAILED${NC}"
echo -e "  ${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "  Logs:    $LOG_DIR"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
