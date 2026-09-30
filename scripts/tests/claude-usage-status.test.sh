#!/bin/bash

# Test script for claude-usage-status.sh
# Run with: ./claude-usage-status.test.sh

IMPL_SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/claude-usage-status.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

tests_passed=0
tests_failed=0

TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/claude-usage-status-test.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.claude"
USAGE_FILE="$TEST_HOME/.claude/rate-limit-usage.json"

check() {
    local test_name="$1" expected="$2" actual="$3" status="$4"

    echo -e "${BLUE}Running test:${NC} $test_name"
    if [[ "$actual" == "$expected" && "$status" == 0 ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((tests_passed++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  expected: $expected (exit 0)"
        echo "  actual:   $actual (exit $status)"
        ((tests_failed++))
    fi
}

assert_output() {
    local test_name="$1" expected="$2"
    local actual status
    actual=$(HOME="$TEST_HOME" bash "$IMPL_SCRIPT")
    status=$?
    check "$test_name" "$expected" "$actual" "$status"
}

# Offsets from now get 30s of slack so a slow run can't cross a minute boundary.
window() {
    local pct="$1" offset="$2"
    printf '{"used_percentage":%s,"resets_at":%s}' "$pct" "$(( $(date +%s) + offset ))"
}

write_usage() {
    local five="$1" seven="$2"
    printf '{"captured_at":%s,"five_hour":%s,"seven_day":%s}' "$(date +%s)" "$five" "$seven" > "$USAGE_FILE"
}

# 2h48m and 4d3h, each plus slack
FIVE_OFFSET=$(( 2*3600 + 48*60 + 30 ))
SEVEN_OFFSET=$(( 4*86400 + 3*3600 + 30 ))

bar_test() {
    local name="$1" pct="$2" expected_segment="$3"
    write_usage "$(window "$pct" "$FIVE_OFFSET")" null
    assert_output "$name" "$expected_segment 2h48m"
}

countdown_test() {
    local name="$1" offset="$2" expected="$3"
    write_usage "$(window 50 "$offset")" null
    assert_output "$name" "5H ████░░░░ 50% $expected"
}

echo "=========================================="
echo "Testing claude-usage-status.sh script"
echo "=========================================="
echo

# --- Full line ---
write_usage "$(window 4 "$FIVE_OFFSET")" "$(window 50 "$SEVEN_OFFSET")"
assert_output "both windows" "5H █░░░░░░░ 4% 2h48m · 7D ████░░░░ 50% 4d3h"

# --- Percent rounding ---
bar_test "percent: 41.4 rounds down"  41.4 "5H ████░░░░ 41%"
bar_test "percent: 11.6 rounds up"    11.6 "5H █░░░░░░░ 12%"

# --- Bar cells ---
bar_test "bar: 0 fills nothing"            0   "5H ░░░░░░░░ 0%"
bar_test "bar: 0.5 fills one cell"         0.5 "5H █░░░░░░░ 1%"
bar_test "bar: 41 rounds up to 4 cells"    41  "5H ████░░░░ 41%"
bar_test "bar: 100 fills all cells"        100 "5H ████████ 100%"
bar_test "bar: 130 clamps to 8 cells"      130 "5H ████████ 130%"

# --- Countdown ---
countdown_test "countdown: days and hours"    $(( 3*86400 + 4*3600 + 30 )) "3d4h"
countdown_test "countdown: whole days"        $(( 3*86400 + 30 ))          "3d"
countdown_test "countdown: hours and minutes" $(( 2*3600 + 13*60 + 30 ))   "2h13m"
countdown_test "countdown: whole hours"       $(( 2*3600 + 30 ))           "2h"
countdown_test "countdown: minutes"           $(( 13*60 + 30 ))            "13m"
countdown_test "countdown: under a minute"    30                           "<1m"
countdown_test "countdown: past reset"        -120                         "0m"

# --- Invalid input prints nothing ---
rm -f "$USAGE_FILE"
assert_output "missing file prints nothing" ""

printf 'not json' > "$USAGE_FILE"
assert_output "invalid JSON prints nothing" ""

write_usage null null
assert_output "no windows prints nothing" ""

write_usage '{"used_percentage":"4","resets_at":1}' "$(window 50 "$SEVEN_OFFSET")"
assert_output "non-numeric field drops only that window" "7D ████░░░░ 50% 4d3h"

printf '{"captured_at":1,"five_hour":%s}' "$(window 4 "$FIVE_OFFSET")" > "$USAGE_FILE"
assert_output "five_hour-only file" "5H █░░░░░░░ 4% 2h48m"

# --- Minimal environment, as herdr runs it ---
write_usage "$(window 4 "$FIVE_OFFSET")" "$(window 50 "$SEVEN_OFFSET")"
actual=$(env -i HOME="$TEST_HOME" /bin/sh -lc "bash '$IMPL_SCRIPT'")
check "runs under env -i login shell" "5H █░░░░░░░ 4% 2h48m · 7D ████░░░░ 50% 4d3h" "$actual" "$?"

echo
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed:${NC} $tests_passed"
echo -e "${RED}Failed:${NC} $tests_failed"

if [ "$tests_failed" -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
    exit 0
else
    exit 1
fi
