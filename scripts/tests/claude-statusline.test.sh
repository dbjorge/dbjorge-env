#!/bin/bash

# Test script for claude-statusline.sh
# Run with: ./claude-statusline.test.sh

IMPL_SCRIPT="$(dirname "$0")/../claude-statusline.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

tests_passed=0
tests_failed=0

assert_output() {
    local test_name="$1"
    local input="$2"
    local expected="$3"

    echo -e "${BLUE}Running test:${NC} $test_name"

    local actual
    actual=$(printf '%s' "$input" | bash "$IMPL_SCRIPT")

    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((tests_passed++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        ((tests_failed++))
    fi
}

# Helper to build a payload with given used token components and total
mk_payload() {
    local cwd="$1" model="$2" total="$3" input_tokens="$4" cache_creation="$5" cache_read="$6"
    if [ -z "$input_tokens" ] && [ -z "$cache_creation" ] && [ -z "$cache_read" ]; then
        printf '{"model":{"display_name":"%s"},"cwd":"%s","context_window":{"context_window_size":%s,"current_usage":null}}' \
            "$model" "$cwd" "$total"
    else
        printf '{"model":{"display_name":"%s"},"cwd":"%s","context_window":{"context_window_size":%s,"current_usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}' \
            "$model" "$cwd" "$total" "${input_tokens:-0}" "${cache_creation:-0}" "${cache_read:-0}"
    fi
}

# Helper for token-formatting tests: same N for used and total, fixed model + cwd
# used==total is always in the dumb zone, so used is wrapped in coral.
fmt_test() {
    local name="$1" n="$2" expected_fmt="$3"
    assert_output "$name" \
        "$(mk_payload "/Users/danbjorge" "X" "$n" "$n" 0 0)" \
        "$(printf '\033[38;5;167m')${expected_fmt}$(printf '\033[0m')/${expected_fmt}  ~  X"
}

echo "=========================================="
echo "Testing claude-statusline.sh script"
echo "=========================================="
echo

# --- Token formatting boundaries ---
fmt_test "format: small (10)"           10        "10"
fmt_test "format: small (100)"          100       "100"
fmt_test "format: small (999)"          999       "999"
fmt_test "format: 1k exact"             1000      "1k"
fmt_test "format: 1.1k"                 1100      "1.1k"
fmt_test "format: 1.5k"                 1500      "1.5k"
fmt_test "format: 9k exact"             9000      "9k"
fmt_test "format: 9.9k"                 9900      "9.9k"
fmt_test "format: 9.9k (round down)"    9949      "9.9k"
fmt_test "format: 10k (round up from 9.95k)" 9950 "10k"
fmt_test "format: 10k from 9999"        9999      "10k"
fmt_test "format: 10k exact"            10000     "10k"
fmt_test "format: 11k"                  11000     "11k"
fmt_test "format: 12k (round from 11.5k)" 11500   "12k"
fmt_test "format: 53k (typical session)" 52507    "53k"
fmt_test "format: 111k"                 111000    "111k"
fmt_test "format: 1M (round from 999.5k)" 999500  "1M"
fmt_test "format: 1M exact"             1000000   "1M"
fmt_test "format: 1.1M"                 1100000   "1.1M"
fmt_test "format: 1.2M"                 1234567   "1.2M"
fmt_test "format: 1.9M"                 1900000   "1.9M"
fmt_test "format: 2M (no .0)"           2000000   "2M"
fmt_test "format: 9.9M"                 9900000   "9.9M"
fmt_test "format: 9.9M (round down)"    9949000   "9.9M"
fmt_test "format: 10M (round from 9.95M)" 9950000 "10M"
fmt_test "format: 11M"                  11000000  "11M"
fmt_test "format: 12M (round from 11.5M)" 11500000 "12M"

# --- current_usage sums all three input fields ---
# used=52512, total=1000000: smart_threshold=min(100k,400k)=100k; 52512<100k → smart (sage 108)
assert_output "sums input + cache_creation + cache_read" \
    "$(mk_payload "/Users/danbjorge" "X" 1000000 12 4500 48000)" \
    "$(printf '\033[38;5;108m')53k$(printf '\033[0m')/1M  ~  X"

# used=50000, total=200000: smart_threshold=min(100k,80k)=80k; 50000<80k → smart (sage 108)
assert_output "uses only cache_read when other fields zero" \
    "$(mk_payload "/Users/danbjorge" "X" 200000 0 0 50000)" \
    "$(printf '\033[38;5;108m')50k$(printf '\033[0m')/200k  ~  X"

# used=1000, total=200000: smart_threshold=80k; 1000<80k → smart (sage 108)
assert_output "does not include output_tokens" \
    "$(printf '{"model":{"display_name":"X"},"cwd":"/Users/danbjorge","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":99999}}}')" \
    "$(printf '\033[38;5;108m')1k$(printf '\033[0m')/200k  ~  X"

# --- Pre-first-call: current_usage is null, no token segment ---
assert_output "null current_usage: omits token segment" \
    "$(mk_payload "/Users/danbjorge" "Claude Sonnet 4.6" 200000)" \
    "~  Claude Sonnet 4.6"

# --- Model name display ---
# used=50000, total=1000000: smart_threshold=min(100k,400k)=100k; 50000<100k → smart (sage 108)
assert_output "strips '(1M context)' from Opus model name" \
    "$(mk_payload "/Users/danbjorge" "Claude Opus 4.7 (1M context)" 1000000 0 0 50000)" \
    "$(printf '\033[38;5;108m')50k$(printf '\033[0m')/1M  ~  Claude Opus 4.7"

# used=25000, total=200000: smart_threshold=min(100k,80k)=80k; 25000<80k → smart (sage 108)
assert_output "leaves non-Opus model names untouched" \
    "$(mk_payload "/Users/danbjorge" "Claude Sonnet 4.6" 200000 0 0 25000)" \
    "$(printf '\033[38;5;108m')25k$(printf '\033[0m')/200k  ~  Claude Sonnet 4.6"

# used=1000, total=200000: smart_threshold=80k; 1000<80k → smart (sage 108)
assert_output "falls back to model.id when display_name absent" \
    "$(printf '{"model":{"id":"claude-haiku-4-5"},"cwd":"/Users/danbjorge","context_window":{"context_window_size":200000,"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}')" \
    "$(printf '\033[38;5;108m')1k$(printf '\033[0m')/200k  ~  claude-haiku-4-5"

# --- Working directory display ---
# used=1000, total=200000: smart (sage 108) for all three below
assert_output "tilde substitution for home dir" \
    "$(mk_payload "/Users/danbjorge/repos/dbjorge-env" "X" 200000 0 0 1000)" \
    "$(printf '\033[38;5;108m')1k$(printf '\033[0m')/200k  ~/repos/dbjorge-env  X"

assert_output "non-home cwd left untouched" \
    "$(mk_payload "/tmp/somewhere" "X" 200000 0 0 1000)" \
    "$(printf '\033[38;5;108m')1k$(printf '\033[0m')/200k  /tmp/somewhere  X"

assert_output "falls back to workspace.current_dir when cwd absent" \
    "$(printf '{"model":{"display_name":"X"},"workspace":{"current_dir":"/Users/danbjorge/repos/dbjorge-env"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":1000}}}')" \
    "$(printf '\033[38;5;108m')1k$(printf '\033[0m')/200k  ~/repos/dbjorge-env  X"

# --- Zone boundary tests ---
# total=200000: smart_threshold=min(100k,80k)=80k, warning_threshold=min(200k,120k)=120k

# used=79999 → 80k display, 79999<80000 → smart (sage 108)
assert_output "zone: total=200k used=79999 → smart (sage)" \
    "$(mk_payload "/Users/danbjorge" "X" 200000 0 0 79999)" \
    "$(printf '\033[38;5;108m')80k$(printf '\033[0m')/200k  ~  X"

# used=80000 → 80k display, 80000>=80000 and 80000<120000 → warning (amber 179)
assert_output "zone: total=200k used=80000 → warning (amber)" \
    "$(mk_payload "/Users/danbjorge" "X" 200000 0 0 80000)" \
    "$(printf '\033[38;5;179m')80k$(printf '\033[0m')/200k  ~  X"

# used=119999 → 120k display, 119999<120000 → warning (amber 179)
assert_output "zone: total=200k used=119999 → warning (amber)" \
    "$(mk_payload "/Users/danbjorge" "X" 200000 0 0 119999)" \
    "$(printf '\033[38;5;179m')120k$(printf '\033[0m')/200k  ~  X"

# used=120000 → 120k display, 120000>=120000 → dumb (coral 167)
assert_output "zone: total=200k used=120000 → dumb (coral)" \
    "$(mk_payload "/Users/danbjorge" "X" 200000 0 0 120000)" \
    "$(printf '\033[38;5;167m')120k$(printf '\033[0m')/200k  ~  X"

# total=1000000: smart_threshold=min(100k,400k)=100k, warning_threshold=min(200k,600k)=200k

# used=99999 → 100k display, 99999<100000 → smart (sage 108)
assert_output "zone: total=1000k used=99999 → smart (sage)" \
    "$(mk_payload "/Users/danbjorge" "X" 1000000 0 0 99999)" \
    "$(printf '\033[38;5;108m')100k$(printf '\033[0m')/1M  ~  X"

# used=100000 → 100k display, 100000>=100000 and 100000<200000 → warning (amber 179)
assert_output "zone: total=1000k used=100000 → warning (amber)" \
    "$(mk_payload "/Users/danbjorge" "X" 1000000 0 0 100000)" \
    "$(printf '\033[38;5;179m')100k$(printf '\033[0m')/1M  ~  X"

# used=199999 → 200k display, 199999<200000 → warning (amber 179)
assert_output "zone: total=1000k used=199999 → warning (amber)" \
    "$(mk_payload "/Users/danbjorge" "X" 1000000 0 0 199999)" \
    "$(printf '\033[38;5;179m')200k$(printf '\033[0m')/1M  ~  X"

# used=200000 → 200k display, 200000>=200000 → dumb (coral 167)
assert_output "zone: total=1000k used=200000 → dumb (coral)" \
    "$(mk_payload "/Users/danbjorge" "X" 1000000 0 0 200000)" \
    "$(printf '\033[38;5;167m')200k$(printf '\033[0m')/1M  ~  X"

# total=500000: smart_threshold=min(100k,200k)=100k, warning_threshold=min(200k,300k)=200k

# used=199999 → 200k display, 199999<200000 → warning (amber 179)
assert_output "zone: total=500k used=199999 → warning (amber)" \
    "$(mk_payload "/Users/danbjorge" "X" 500000 0 0 199999)" \
    "$(printf '\033[38;5;179m')200k$(printf '\033[0m')/500k  ~  X"

# used=200000 → 200k display, 200000>=200000 → dumb (coral 167)
assert_output "zone: total=500k used=200000 → dumb (coral)" \
    "$(mk_payload "/Users/danbjorge" "X" 500000 0 0 200000)" \
    "$(printf '\033[38;5;167m')200k$(printf '\033[0m')/500k  ~  X"

echo
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Tests passed: ${GREEN}$tests_passed${NC}"
echo -e "Tests failed: ${RED}$tests_failed${NC}"
echo "Total tests: $((tests_passed + tests_failed))"

if [[ $tests_failed -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
