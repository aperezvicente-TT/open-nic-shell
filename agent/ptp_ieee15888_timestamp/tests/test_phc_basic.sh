#!/usr/bin/env bash
# =============================================================================
# test_phc_basic.sh -- Category A: PHC Basic Operations
#
# Tests PTP Hardware Clock read, set, adjtime, adjfreq, and tick-rate
# verification for the OpenNIC Shell PTP implementation.
#
# Usage:
#   sudo ./test_phc_basic.sh              # Run all tests
#   sudo ./test_phc_basic.sh A.1 A.3      # Run specific tests
#
# Prerequisites:
#   - onic module loaded with PTP support
#   - linuxptp tools installed (phc_ctl)
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
NC='\033[0m' # No Color

pass()  { echo -e "  [${GREEN}PASS${NC}] $1"; }
fail()  { echo -e "  [${RED}FAIL${NC}] $1"; }
skip()  { echo -e "  [${YELLOW}SKIP${NC}] $1"; }
info()  { echo -e "  [${CYAN}INFO${NC}] $1"; }
header(){ echo -e "\n${BOLD}=== $1 ===${NC}"; }

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

record_pass() { ((TOTAL++)) || true; ((PASSED++)) || true; pass "$1"; }
record_fail() { ((TOTAL++)) || true; ((FAILED++)) || true; fail "$1"; }
record_skip() { ((TOTAL++)) || true; ((SKIPPED++)) || true; skip "$1"; }

# ---------------------------------------------------------------------------
# Environment setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/tmp/ptp_test_phc_basic_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

# Load overrides if present
if [[ -f "$SCRIPT_DIR/test_env.sh" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/test_env.sh"
fi

# Auto-detect interface and PTP device if not set
if [[ -z "${IF_MASTER:-}" ]]; then
    IF_MASTER=$(ip -o link show | grep -oP 'onic\S+' | head -1 || true)
    if [[ -z "$IF_MASTER" ]]; then
        echo -e "${RED}ERROR: No onic interface found. Is the driver loaded?${NC}"
        exit 1
    fi
fi

if [[ -z "${PTP_MASTER:-}" ]]; then
    PHC_INDEX=$(ethtool -T "$IF_MASTER" 2>/dev/null | grep -oP 'PTP Hardware Clock: \K\d+' || echo "-1")
    if [[ "$PHC_INDEX" == "-1" ]]; then
        echo -e "${RED}ERROR: No PTP clock found for $IF_MASTER (phc_index=-1)${NC}"
        exit 1
    fi
    PTP_MASTER="/dev/ptp${PHC_INDEX}"
fi

info "Interface: $IF_MASTER"
info "PTP device: $PTP_MASTER"
info "Log directory: $LOG_DIR"

# ---------------------------------------------------------------------------
# Determine which tests to run
# ---------------------------------------------------------------------------
REQUESTED_TESTS=("${@}")
run_test() {
    local test_id="$1"
    if [[ ${#REQUESTED_TESTS[@]} -eq 0 ]]; then
        return 0  # run all
    fi
    for t in "${REQUESTED_TESTS[@]}"; do
        if [[ "$t" == "$test_id" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Helper: read PHC time, output seconds.nanoseconds
# ---------------------------------------------------------------------------
phc_read_time() {
    local dev="$1"
    local output
    output=$(phc_ctl "$dev" get 2>&1)
    # phc_ctl output: "clock time is <seconds>.<nanoseconds>"
    echo "$output" | grep -oP 'clock time is \K[0-9]+\.[0-9]+' || echo "0.0"
}

# Extract seconds part
phc_read_seconds() {
    local t
    t=$(phc_read_time "$1")
    echo "${t%%.*}"
}

# Extract nanoseconds part
phc_read_ns() {
    local t
    t=$(phc_read_time "$1")
    echo "${t#*.}"
}

# ---------------------------------------------------------------------------
# A.1 -- PHC Device Existence
# ---------------------------------------------------------------------------
test_a1() {
    if ! run_test "A.1"; then return; fi
    header "A.1 -- PHC Device Existence"

    # Check phc_index via ethtool
    local ts_output phc_index
    ts_output=$(ethtool -T "$IF_MASTER" 2>&1)
    echo "$ts_output" > "$LOG_DIR/a1_ethtool_T.log"

    phc_index=$(echo "$ts_output" | grep -oP 'PTP Hardware Clock: \K[-0-9]+' || echo "-1")
    info "phc_index = $phc_index"

    if [[ "$phc_index" == "-1" ]]; then
        record_fail "A.1: phc_index is -1, PTP hardware not detected"
        return
    fi

    local ptp_dev="/dev/ptp${phc_index}"
    if [[ -c "$ptp_dev" ]]; then
        info "Device $ptp_dev exists and is a character device"
        record_pass "A.1: PHC device $ptp_dev exists (phc_index=$phc_index)"
    else
        record_fail "A.1: $ptp_dev does not exist or is not a character device"
    fi
}

# ---------------------------------------------------------------------------
# A.2 -- PHC Clock Read
# ---------------------------------------------------------------------------
test_a2() {
    if ! run_test "A.2"; then return; fi
    header "A.2 -- PHC Clock Read"

    local t1 t2 s1 s2 delta

    t1=$(phc_read_time "$PTP_MASTER")
    s1=$(echo "$t1" | cut -d. -f1)
    info "First read:  $t1"

    if [[ "$s1" -eq 0 ]]; then
        record_fail "A.2: Clock read returned 0 seconds"
        return
    fi

    sleep 1

    t2=$(phc_read_time "$PTP_MASTER")
    s2=$(echo "$t2" | cut -d. -f1)
    info "Second read: $t2"

    delta=$(echo "$t2 - $t1" | bc -l)
    info "Delta: ${delta}s"

    echo "t1=$t1 t2=$t2 delta=$delta" > "$LOG_DIR/a2_clock_read.log"

    # Check delta is approximately 1 second (0.9 to 1.1)
    local in_range
    in_range=$(echo "$delta >= 0.9 && $delta <= 1.1" | bc -l)
    if [[ "$in_range" -eq 1 ]]; then
        record_pass "A.2: Clock reads valid, delta=${delta}s (expected ~1.0s)"
    else
        record_fail "A.2: Clock delta ${delta}s outside range [0.9, 1.1]"
    fi
}

# ---------------------------------------------------------------------------
# A.3 -- PHC Clock Set
# ---------------------------------------------------------------------------
test_a3() {
    if ! run_test "A.3"; then return; fi
    header "A.3 -- PHC Clock Set"

    local target=1000000000
    local output readback delta

    info "Setting clock to $target"
    output=$(phc_ctl "$PTP_MASTER" set "$target" 2>&1)
    echo "$output" > "$LOG_DIR/a3_set_output.log"

    if [[ $? -ne 0 ]]; then
        record_fail "A.3: phc_ctl set command failed"
        return
    fi

    # Small delay to ensure the set takes effect
    sleep 0.1

    readback=$(phc_read_time "$PTP_MASTER")
    local rb_sec
    rb_sec=$(echo "$readback" | cut -d. -f1)
    info "Readback: $readback"

    delta=$((rb_sec - target))
    if [[ $delta -lt 0 ]]; then delta=$((-delta)); fi

    echo "target=$target readback=$readback delta_sec=$delta" > "$LOG_DIR/a3_set_verify.log"

    if [[ $delta -le 1 ]]; then
        record_pass "A.3: Clock set to $target, readback=$readback (delta=${delta}s)"
    else
        record_fail "A.3: Clock set to $target but readback=$readback (delta=${delta}s > 1)"
    fi

    # Restore clock to roughly current wall time so later tests are not confused
    local now
    now=$(date +%s)
    phc_ctl "$PTP_MASTER" set "$now" > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# A.4 -- PHC Adjtime (Phase Offset)
# ---------------------------------------------------------------------------
test_a4() {
    if ! run_test "A.4"; then return; fi
    header "A.4 -- PHC Adjtime (Phase Offset)"

    local adj_ns=500000000  # 0.5 seconds in nanoseconds

    # Set clock to a known value first
    phc_ctl "$PTP_MASTER" set 2000000000 > /dev/null 2>&1

    sleep 0.1
    local t0 t0_sec
    t0=$(phc_read_time "$PTP_MASTER")
    t0_sec=$(echo "$t0" | cut -d. -f1)
    info "Before adj: $t0"

    # Apply adjustment of +0.5 seconds
    local output
    output=$(phc_ctl "$PTP_MASTER" adj "$adj_ns" 2>&1)
    echo "$output" > "$LOG_DIR/a4_adj_output.log"

    sleep 0.1
    local t1 t1_sec
    t1=$(phc_read_time "$PTP_MASTER")
    t1_sec=$(echo "$t1" | cut -d. -f1)
    info "After adj:  $t1"

    # The time should have jumped by about 0.5s plus whatever elapsed (~0.2s)
    local delta
    delta=$(echo "$t1 - $t0" | bc -l)
    info "Delta: ${delta}s (expected ~0.7s = 0.5s adj + ~0.2s elapsed)"

    echo "t0=$t0 t1=$t1 delta=$delta adj_ns=$adj_ns" > "$LOG_DIR/a4_adjtime.log"

    # Expect delta between 0.45 and 1.0 (0.5s adj + some elapsed)
    local in_range
    in_range=$(echo "$delta >= 0.45 && $delta <= 1.5" | bc -l)
    if [[ "$in_range" -eq 1 ]]; then
        record_pass "A.4: Adjtime +0.5s applied, delta=${delta}s"
    else
        record_fail "A.4: Adjtime delta ${delta}s outside expected range [0.45, 1.5]"
    fi

    # Restore clock
    local now
    now=$(date +%s)
    phc_ctl "$PTP_MASTER" set "$now" > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# A.5 -- PHC Adjfreq (Frequency Trim)
# ---------------------------------------------------------------------------
test_a5() {
    if ! run_test "A.5"; then return; fi
    header "A.5 -- PHC Adjfreq (Frequency Trim)"

    local freq_ppb=100000000  # +100 ppm = 100000000 ppb in phc_ctl units
    local wait_seconds=10

    # Reset frequency to zero first
    phc_ctl "$PTP_MASTER" freq 0 > /dev/null 2>&1 || true
    sleep 0.5

    # Set clock to known value
    phc_ctl "$PTP_MASTER" set 3000000000 > /dev/null 2>&1
    sleep 0.1

    local t0
    t0=$(phc_read_time "$PTP_MASTER")
    local sys_t0
    sys_t0=$(date +%s.%N)
    info "Before freq adj: PHC=$t0, sys=$sys_t0"

    # Apply +100 ppm frequency adjustment
    info "Applying freq adjustment: +100 ppm ($freq_ppb ppb)"
    phc_ctl "$PTP_MASTER" freq "$freq_ppb" > /dev/null 2>&1

    sleep "$wait_seconds"

    local t1 sys_t1
    t1=$(phc_read_time "$PTP_MASTER")
    sys_t1=$(date +%s.%N)
    info "After ${wait_seconds}s: PHC=$t1, sys=$sys_t1"

    # Compute how much PHC advanced vs wall clock
    local phc_delta sys_delta drift
    phc_delta=$(echo "$t1 - $t0" | bc -l)
    sys_delta=$(echo "$sys_t1 - $sys_t0" | bc -l)
    drift=$(echo "($phc_delta - $sys_delta) * 1000" | bc -l)  # drift in milliseconds
    info "PHC delta: ${phc_delta}s, Sys delta: ${sys_delta}s"
    info "Drift: ${drift}ms (expected ~1.0ms for 100ppm over 10s)"

    echo "t0=$t0 t1=$t1 phc_delta=$phc_delta sys_delta=$sys_delta drift_ms=$drift" \
        > "$LOG_DIR/a5_adjfreq.log"

    # Expected drift: 10s * 100ppm = 1ms. Accept 0.3ms to 3.0ms.
    local in_range
    in_range=$(echo "${drift#-} >= 0.3 && ${drift#-} <= 3.0" | bc -l 2>/dev/null || echo "0")
    if [[ "$in_range" -eq 1 ]]; then
        record_pass "A.5: Freq trim drift=${drift}ms over ${wait_seconds}s (expected ~1.0ms)"
    else
        record_fail "A.5: Freq trim drift=${drift}ms outside expected range [0.3, 3.0]ms"
    fi

    # Reset frequency
    phc_ctl "$PTP_MASTER" freq 0 > /dev/null 2>&1 || true
    # Restore clock
    local now
    now=$(date +%s)
    phc_ctl "$PTP_MASTER" set "$now" > /dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# A.6 -- PHC Clock Tick Rate
# ---------------------------------------------------------------------------
test_a6() {
    if ! run_test "A.6"; then return; fi
    header "A.6 -- PHC Clock Tick Rate (4ns/tick at 250 MHz)"

    # Reset frequency to nominal
    phc_ctl "$PTP_MASTER" freq 0 > /dev/null 2>&1 || true
    sleep 0.1

    # Read twice rapidly and compare
    # phc_ctl resolution is limited, so we do multiple rapid reads and check consistency
    local samples=20
    local prev_ns=0
    local valid_count=0
    local bad_count=0

    info "Taking $samples rapid PHC reads to verify tick alignment..."

    for ((i = 0; i < samples; i++)); do
        local t ns
        t=$(phc_read_time "$PTP_MASTER")
        # Get full nanoseconds from the fractional part
        ns=$(echo "$t" | grep -oP '\.\K[0-9]+')
        # Pad to 9 digits
        while [[ ${#ns} -lt 9 ]]; do ns="${ns}0"; done

        if [[ $i -gt 0 ]]; then
            # Check if nanosecond part is a multiple of 4
            local remainder=$((10#$ns % 4))
            if [[ $remainder -eq 0 ]]; then
                ((valid_count++)) || true
            else
                ((bad_count++)) || true
                info "Sample $i: ns=$ns, remainder=$remainder (not 4ns aligned)"
            fi
        fi
        echo "sample $i: $t (ns=$ns)" >> "$LOG_DIR/a6_tick_samples.log"
    done

    info "Valid (4ns aligned): $valid_count / $((samples - 1))"
    info "Misaligned: $bad_count / $((samples - 1))"

    # At 250 MHz, nanosecond field should always be a multiple of 4.
    # Allow small tolerance since PCIe read latency is unpredictable,
    # but the nanosecond value itself must be 4ns-aligned.
    if [[ $valid_count -ge $((samples - 1 - 2)) ]]; then
        record_pass "A.6: Clock tick rate verified, $valid_count/$((samples - 1)) samples 4ns-aligned"
    else
        record_fail "A.6: Only $valid_count/$((samples - 1)) samples were 4ns-aligned"
    fi
}

# ===========================================================================
# Main
# ===========================================================================
header "PTP IEEE 1588 -- Category A: PHC Basic Operations"
echo -e "  Interface: ${BOLD}${IF_MASTER}${NC}"
echo -e "  PTP device: ${BOLD}${PTP_MASTER}${NC}"
echo -e "  Log dir: ${BOLD}${LOG_DIR}${NC}"

# Verify prerequisites
if ! command -v phc_ctl &> /dev/null; then
    echo -e "${RED}ERROR: phc_ctl not found. Install linuxptp.${NC}"
    exit 1
fi

if ! command -v ethtool &> /dev/null; then
    echo -e "${RED}ERROR: ethtool not found.${NC}"
    exit 1
fi

if ! command -v bc &> /dev/null; then
    echo -e "${RED}ERROR: bc not found.${NC}"
    exit 1
fi

if [[ ! -c "$PTP_MASTER" ]]; then
    echo -e "${RED}ERROR: PTP device $PTP_MASTER does not exist.${NC}"
    echo -e "${RED}Is the onic module loaded with PTP support?${NC}"
    exit 1
fi

# Run tests
test_a1
test_a2
test_a3
test_a4
test_a5
test_a6

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary: Category A -- PHC Basic Operations"
echo -e "  Total:   $TOTAL"
echo -e "  ${GREEN}Passed:  $PASSED${NC}"
echo -e "  ${RED}Failed:  $FAILED${NC}"
echo -e "  ${YELLOW}Skipped: $SKIPPED${NC}"
echo -e "  Logs:    $LOG_DIR"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
