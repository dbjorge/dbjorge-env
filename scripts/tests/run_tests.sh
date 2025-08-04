#!/bin/bash

# Run all test scripts in the tests directory
total_tests=0
failed_tests=0
for test_script in $(dirname "$0")/*.test.sh; do
    echo "Running $test_script"
    "$test_script"
    if [ $? -ne 0 ]; then
        failed_tests=$((failed_tests + 1))
    fi
    total_tests=$((total_tests + 1))
done

# Print a summary and exit with the number of failed tests
echo ""
echo "=========================================="
echo "Final Summary"
echo "=========================================="
echo "Total test files: $total_tests"
echo "Failed test files: $failed_tests"
exit $failed_tests