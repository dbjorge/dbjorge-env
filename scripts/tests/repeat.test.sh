#!/bin/bash

# Test script for repeat.sh
# Run with: ./repeat.test.sh

IMPL_SCRIPT="$(dirname "$0")/../repeat.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counter
tests_passed=0
tests_failed=0

# Function to print test results
print_result() {
    local test_name="$1"
    local exit_code="$2"
    local expected_exit="$3"
    
    if [[ "$exit_code" -eq "$expected_exit" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        ((tests_passed++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name (expected exit $expected_exit, got $exit_code)"
        ((tests_failed++))
    fi
}

# Function to run a test
run_test() {
    local test_name="$1"
    local expected_exit="$2"
    shift 2
    
    echo -e "${BLUE}Running test:${NC} $test_name"
    
    # Capture output and exit code
    local output
    local exit_code
    
    if output=$(eval "$@" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    print_result "$test_name" "$exit_code" "$expected_exit"
    
    # Show output for failed tests or when verbose
    if [[ "$exit_code" -ne "$expected_exit" ]] || [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "Output:"
        echo "$output" | sed 's/^/  /'
        echo
    fi
}

echo "=========================================="
echo "Testing repeat.sh script"
echo "=========================================="
echo

# Test 1: Basic usage with simple command
run_test "Basic usage - simple echo command" 0 \
    "$IMPL_SCRIPT 2 'echo hello'"

# Test 2: Basic usage with sleep command
run_test "Basic usage - sleep command" 0 \
    "$IMPL_SCRIPT 2 'sleep 0.1 && echo slept'"

# Test 3: Invalid number of iterations
run_test "Invalid iterations - zero" 1 \
    "$IMPL_SCRIPT 0 'echo hello'"

# Test 4: Invalid number of iterations (negative)
run_test "Invalid iterations - negative" 1 \
    "$IMPL_SCRIPT -1 'echo hello'"

# Test 5: Invalid number of iterations (non-numeric)
run_test "Invalid iterations - non-numeric" 1 \
    "$IMPL_SCRIPT abc 'echo hello'"

# Test 6: Missing command
run_test "Missing command" 1 \
    "$IMPL_SCRIPT 5"

# Test 7: Missing iterations
run_test "Missing iterations" 1 \
    "$IMPL_SCRIPT"

# Test 8: Unknown flag
run_test "Unknown flag" 1 \
    "$IMPL_SCRIPT --unknown-flag 5 'echo hello'"

# Test 9: Command that fails
run_test "Command that fails" 1 \
    "$IMPL_SCRIPT 2 'false'"

# Test 10: Continue on error flag
run_test "Continue on error flag" 1 \
    "$IMPL_SCRIPT --continue-on-error 3 'false'"

# Test 11: No summary flag
run_test "No summary flag" 0 \
    "$IMPL_SCRIPT --no-summary 2 'echo hello'"

# Test 12: Both flags together
run_test "Both flags together" 1 \
    "$IMPL_SCRIPT --continue-on-error --no-summary 3 'false'"

# Test 13: Command with spaces and special characters
run_test "Command with spaces and special chars" 0 \
    "$IMPL_SCRIPT 2 'echo \"Hello World\" && echo \"Test 123\"'"

# Test 14: Command that fails on iterations 2 and 3, succeeds on 1 and 4
run_test "Continue through failures with continue-on-error" 1 \
    "$IMPL_SCRIPT --continue-on-error 4 'count=\$(cat /tmp/repeat_test_counter.txt 2>/dev/null || echo 0); count=\$((count + 1)); echo \$count > /tmp/repeat_test_counter.txt; if [ \$count -eq 2 ] || [ \$count -eq 3 ]; then echo \"Iteration \$count: failing\"; false; else echo \"Iteration \$count: success\"; fi' && rm -f /tmp/repeat_test_counter.txt"

# Test 15: Very fast command (testing timing precision)
run_test "Very fast command" 0 \
    "$IMPL_SCRIPT 5 'echo fast'"

# Test 16: Command with output redirection
run_test "Command with output redirection" 0 \
    "$IMPL_SCRIPT 2 'echo redirected > /tmp/repeat_test_output.txt && cat /tmp/repeat_test_output.txt'"

# Test 17: Command that uses environment variables
run_test "Command with environment variables" 0 \
    "TEST_VAR=hello $IMPL_SCRIPT 2 'echo \$TEST_VAR'"

# Test 18: Command with pipes
run_test "Command with pipes" 0 \
    "$IMPL_SCRIPT 2 'echo hello world | wc -w'"

# Test 19: Command that creates files
run_test "Command that creates files" 0 \
    "$IMPL_SCRIPT 2 'echo run_\$RANDOM > /tmp/repeat_test_\$RANDOM.txt'"

# Test 20: Command with complex logic
run_test "Complex command logic" 0 \
    "$IMPL_SCRIPT 3 'for i in 1 2 3; do echo \"Iteration \$i\"; done'"

# Clean up any test files
rm -f /tmp/repeat_test_output.txt /tmp/repeat_test_*.txt

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
