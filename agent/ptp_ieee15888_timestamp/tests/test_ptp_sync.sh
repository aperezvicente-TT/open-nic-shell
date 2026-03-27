#!/usr/bin/env bash
# =============================================================================
# test_ptp_sync.sh -- Category B: PTP Synchronization
#
# Tests ptp4l master/slave synchronization between two OpenNIC shells,
# offset convergence, phc2sys tracking, and failover recovery.
#
# Usage:
#   sudo ./test_ptp_sync.sh              # Run all tests
#   sudo ./test_ptp_sync.sh B.3          # Run specific test
#
# Prerequisites:
#   - Two onic interfaces connected back-to-back
#   - linuxptp tools installed (ptp4l, phc2sys)
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
LOG_DIR="/tmp/ptp_test_sync_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

if [[ -f "$SCRIPT_DIR/test_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/test_env.sh"
fi

# Auto-detect interfaces
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

info "Master interface: $IF_MASTER"
info "Slave interface:  $IF_SLAVE"
info "Log directory:    $LOG_DIR"

# ---------------------------------------------------------------------------
# Test selection
# ---------------------------------------------------------------------------
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
# Cleanup helper -- kill background ptp4l/phc2sys on exit
# ---------------------------------------------------------------------------
PTP4L_MASTER_PID=""
PTP4L_SLAVE_PID=""
PHC2SYS_PID=""

cleanup() {
    info "Cleaning up background processes..."
    for pid in $PTP4L_MASTER_PID $PTP4L_SLAVE_PID $PHC2SYS_PID; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helper: start ptp4l master
# ---------------------------------------------------------------------------
start_ptp4l_master() {
    local log="$LOG_DIR/ptp4l_master.log"
    info "Starting ptp4l master on $IF_MASTER ..."

    ptp4l -i "$IF_MASTER" -H -m --priority1 128 \
        --tx_timestamp_timeout 100 \
        --step_threshold 1.0 \
        > "$log" 2>&1 &
    PTP4L_MASTER_PID=$!
    info "ptp4l master PID: $PTP4L_MASTER_PID (log: $log)"
}

# ---------------------------------------------------------------------------
# Helper: start ptp4l slave
# ---------------------------------------------------------------------------
start_ptp4l_slave() {
    local log="$LOG_DIR/ptp4l_slave.log"
    info "Starting ptp4l slave on $IF_SLAVE ..."

    ptp4l -i "$IF_SLAVE" -H -m -s \
        --tx_timestamp_timeout 100 \
        --step_threshold 1.0 \
        > "$log" 2>&1 &
    PTP4L_SLAVE_PID=$!
    info "ptp4l slave PID: $PTP4L_SLAVE_PID (log: $log)"
}

# ---------------------------------------------------------------------------
# Helper: wait for a pattern in a log file with timeout
# ---------------------------------------------------------------------------
wait_for_log() {
    local log_file="$1"
    local pattern="$2"
    local timeout_sec="${3:-60}"
    local elapsed=0

    while [[ $elapsed -lt $timeout_sec ]]; do
        if grep -q "$pattern" "$log_file" 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((elapsed++)) || true
    done
    return 1
}

# ---------------------------------------------------------------------------
# Helper: extract offset values from ptp4l log
#   ptp4l logs: "master offset   -123 s2 freq  +456 path delay   789"
# ---------------------------------------------------------------------------
extract_offsets() {
    local log_file="$1"
    grep -oP 'master offset\s+\K[-0-9]+' "$log_file" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# B.1 -- ptp4l Startup (Master)
# ---------------------------------------------------------------------------
test_b1() {
    if ! run_test "B.1"; then return; fi
    header "B.1 -- ptp4l Startup (Master)"

    start_ptp4l_master

    info "Waiting up to 15s for master initialization..."
    if wait_for_log "$LOG_DIR/ptp4l_master.log" "selected best master clock" 15 || \
       wait_for_log "$LOG_DIR/ptp4l_master.log" "assuming the grand master role" 5; then
        record_pass "B.1: ptp4l master started and selected grandmaster"
    else
        # Check if process is still running at least
        if kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
            info "ptp4l still running but grandmaster message not found"
            info "Last 5 lines of log:"
            tail -5 "$LOG_DIR/ptp4l_master.log" 2>/dev/null | while read -r line; do
                info "  $line"
            done
            record_fail "B.1: ptp4l running but did not select grandmaster within 15s"
        else
            info "ptp4l exited unexpectedly"
            tail -10 "$LOG_DIR/ptp4l_master.log" 2>/dev/null | while read -r line; do
                info "  $line"
            done
            record_fail "B.1: ptp4l master exited with error"
        fi
    fi
}

# ---------------------------------------------------------------------------
# B.2 -- ptp4l Startup (Slave)
# ---------------------------------------------------------------------------
test_b2() {
    if ! run_test "B.2"; then return; fi
    header "B.2 -- ptp4l Startup (Slave)"

    # Ensure master is running
    if [[ -z "$PTP4L_MASTER_PID" ]] || ! kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
        info "Master not running, starting it first..."
        start_ptp4l_master
        sleep 5
    fi

    start_ptp4l_slave

    info "Waiting up to 60s for slave to reach SLAVE state..."
    if wait_for_log "$LOG_DIR/ptp4l_slave.log" "UNCALIBRATED to SLAVE" 60; then
        record_pass "B.2: ptp4l slave reached SLAVE state"
    elif wait_for_log "$LOG_DIR/ptp4l_slave.log" "SLAVE" 10; then
        record_pass "B.2: ptp4l slave reached SLAVE state"
    else
        info "Last 10 lines of slave log:"
        tail -10 "$LOG_DIR/ptp4l_slave.log" 2>/dev/null | while read -r line; do
            info "  $line"
        done
        record_fail "B.2: ptp4l slave did not reach SLAVE state within 60s"
    fi
}

# ---------------------------------------------------------------------------
# B.3 -- Offset Convergence
# ---------------------------------------------------------------------------
test_b3() {
    if ! run_test "B.3"; then return; fi
    header "B.3 -- Offset Convergence"

    # Ensure master and slave are running
    if [[ -z "$PTP4L_MASTER_PID" ]] || ! kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
        start_ptp4l_master
        sleep 5
    fi
    if [[ -z "$PTP4L_SLAVE_PID" ]] || ! kill -0 "$PTP4L_SLAVE_PID" 2>/dev/null; then
        start_ptp4l_slave
    fi

    info "Waiting 120s for offset to converge..."
    sleep 120

    # Extract last 30 offset samples
    local offsets
    offsets=$(extract_offsets "$LOG_DIR/ptp4l_slave.log" | tail -30)
    local count
    count=$(echo "$offsets" | grep -c '[0-9]' || echo "0")

    if [[ $count -lt 5 ]]; then
        record_fail "B.3: Only $count offset samples found (need at least 5)"
        return
    fi

    echo "$offsets" > "$LOG_DIR/b3_offsets.log"
    info "Collected $count offset samples"

    # Compute mean and max absolute offset
    local sum=0 max_abs=0
    while read -r val; do
        [[ -z "$val" ]] && continue
        local abs_val=${val#-}
        sum=$((sum + abs_val))
        if [[ $abs_val -gt $max_abs ]]; then
            max_abs=$abs_val
        fi
    done <<< "$offsets"

    local mean=$((sum / count))
    info "Mean |offset|: ${mean} ns"
    info "Max  |offset|: ${max_abs} ns"

    echo "count=$count mean_abs=$mean max_abs=$max_abs" >> "$LOG_DIR/b3_offsets.log"

    local pass_mean=1000   # ns
    local pass_max=5000    # ns

    if [[ $mean -le $pass_mean && $max_abs -le $pass_max ]]; then
        record_pass "B.3: Offset converged (mean=${mean}ns <= ${pass_mean}ns, max=${max_abs}ns <= ${pass_max}ns)"
    elif [[ $mean -le $pass_mean ]]; then
        record_fail "B.3: Mean OK (${mean}ns) but max offset ${max_abs}ns > ${pass_max}ns"
    else
        record_fail "B.3: Mean offset ${mean}ns > ${pass_mean}ns threshold"
    fi
}

# ---------------------------------------------------------------------------
# B.4 -- phc2sys Tracking
# ---------------------------------------------------------------------------
test_b4() {
    if ! run_test "B.4"; then return; fi
    header "B.4 -- phc2sys Tracking"

    local phc2sys_log="$LOG_DIR/phc2sys.log"

    info "Starting phc2sys (PHC -> CLOCK_REALTIME)..."
    phc2sys -s "$IF_SLAVE" -c CLOCK_REALTIME -O 0 -m \
        > "$phc2sys_log" 2>&1 &
    PHC2SYS_PID=$!
    info "phc2sys PID: $PHC2SYS_PID"

    sleep 30

    if ! kill -0 "$PHC2SYS_PID" 2>/dev/null; then
        info "phc2sys exited unexpectedly"
        tail -5 "$phc2sys_log" 2>/dev/null | while read -r line; do
            info "  $line"
        done
        record_fail "B.4: phc2sys exited prematurely"
        PHC2SYS_PID=""
        return
    fi

    # Check for offset reports
    local offset_count
    offset_count=$(grep -c 'offset' "$phc2sys_log" 2>/dev/null || echo "0")
    info "phc2sys reported $offset_count offset samples"

    if [[ $offset_count -ge 5 ]]; then
        # Get last few offsets
        local last_offsets
        last_offsets=$(grep -oP 'offset\s+\K[-0-9]+' "$phc2sys_log" | tail -5)
        info "Last 5 offsets: $(echo $last_offsets | tr '\n' ' ')"
        record_pass "B.4: phc2sys running and reporting offsets ($offset_count samples)"
    else
        record_fail "B.4: phc2sys produced too few offset samples ($offset_count)"
    fi

    # Stop phc2sys
    kill "$PHC2SYS_PID" 2>/dev/null || true
    wait "$PHC2SYS_PID" 2>/dev/null || true
    PHC2SYS_PID=""
}

# ---------------------------------------------------------------------------
# B.5 -- Master Failover Recovery
# ---------------------------------------------------------------------------
test_b5() {
    if ! run_test "B.5"; then return; fi
    header "B.5 -- Master Failover Recovery"

    # Ensure both are running
    if [[ -z "$PTP4L_SLAVE_PID" ]] || ! kill -0 "$PTP4L_SLAVE_PID" 2>/dev/null; then
        info "Slave not running, skipping failover test"
        record_skip "B.5: Requires running slave (B.2 must pass first)"
        return
    fi
    if [[ -z "$PTP4L_MASTER_PID" ]] || ! kill -0 "$PTP4L_MASTER_PID" 2>/dev/null; then
        info "Master not running, starting fresh pair..."
        start_ptp4l_master
        sleep 30
    fi

    # Record slave log position before kill
    local pre_kill_lines
    pre_kill_lines=$(wc -l < "$LOG_DIR/ptp4l_slave.log" 2>/dev/null || echo "0")

    info "Killing master ptp4l (PID $PTP4L_MASTER_PID)..."
    kill "$PTP4L_MASTER_PID" 2>/dev/null || true
    wait "$PTP4L_MASTER_PID" 2>/dev/null || true
    PTP4L_MASTER_PID=""

    info "Waiting 10s for slave to detect master loss..."
    sleep 10

    # Check if slave went to LISTENING
    local post_kill_log
    post_kill_log=$(tail -n +"$((pre_kill_lines + 1))" "$LOG_DIR/ptp4l_slave.log" 2>/dev/null || true)
    if echo "$post_kill_log" | grep -q "LISTENING\|MASTER"; then
        info "Slave detected master loss (entered LISTENING or MASTER)"
    else
        info "Slave may still be in SLAVE state (announcement timeout pending)"
    fi

    # Restart master
    info "Restarting master ptp4l..."
    start_ptp4l_master

    info "Waiting up to 60s for slave to re-acquire SLAVE state..."
    local recovered=false
    for i in $(seq 1 60); do
        local new_lines
        new_lines=$(tail -n +"$((pre_kill_lines + 1))" "$LOG_DIR/ptp4l_slave.log" 2>/dev/null || true)
        if echo "$new_lines" | grep -q "to SLAVE"; then
            recovered=true
            break
        fi
        sleep 1
    done

    if $recovered; then
        record_pass "B.5: Slave re-acquired SLAVE state after master restart"
    else
        info "Last 5 slave log lines:"
        tail -5 "$LOG_DIR/ptp4l_slave.log" 2>/dev/null | while read -r line; do
            info "  $line"
        done
        record_fail "B.5: Slave did not re-acquire SLAVE state within 60s"
    fi
}

# ===========================================================================
# Main
# ===========================================================================
header "PTP IEEE 1588 -- Category B: PTP Synchronization"
echo -e "  Master: ${BOLD}${IF_MASTER}${NC}"
echo -e "  Slave:  ${BOLD}${IF_SLAVE}${NC}"
echo -e "  Log dir: ${BOLD}${LOG_DIR}${NC}"

# Check prerequisites
for tool in ptp4l phc2sys ethtool; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}ERROR: $tool not found. Install linuxptp and ethtool.${NC}"
        exit 1
    fi
done

# Ensure interfaces are up
for iface in "$IF_MASTER" "$IF_SLAVE"; do
    if ! ip link show "$iface" &>/dev/null; then
        echo -e "${RED}ERROR: Interface $iface not found.${NC}"
        exit 1
    fi
    # Bring up if down
    local_state=$(ip -o link show "$iface" | grep -oP 'state \K\S+')
    if [[ "$local_state" != "UP" ]]; then
        info "Bringing up $iface..."
        ip link set "$iface" up || true
        sleep 2
    fi
done

# Run tests
test_b1
test_b2
test_b3
test_b4
test_b5

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary: Category B -- PTP Synchronization"
echo -e "  Total:   $TOTAL"
echo -e "  ${GREEN}Passed:  $PASSED${NC}"
echo -e "  ${RED}Failed:  $FAILED${NC}"
echo -e "  ${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "  Logs:    $LOG_DIR"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
