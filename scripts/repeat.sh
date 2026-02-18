#!/bin/bash

# Usage:
# Runs the command 10 times, printing the output each time and printing
# a summary at the end including average and variance of the execution time.
# > ./repeat.sh 10 "echo 'Hello, world!'"
#
# Continue even if the command fails:
# > ./repeat.sh 10 --continue-on-error "sleep 1 && echo 'Hello, world!'"
#
# Suppress the summary at the end:
# > ./repeat.sh 10 --no-summary "sleep 1 && echo 'Hello, world!' && false"

set -eo pipefail

# Default values
continue_on_error=false
show_summary=true
iterations=""
command=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --continue-on-error)
            continue_on_error=true
            shift
            ;;
        --no-summary)
            show_summary=false
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [--continue-on-error] [--no-summary] <iterations> <command>"
            exit 1
            ;;
        *)
            if [[ -z "$iterations" ]]; then
                iterations="$1"
            elif [[ -z "$command" ]]; then
                command="$1"
            else
                command="$command $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$iterations" ]] || [[ -z "$command" ]]; then
    echo "Usage: $0 [--continue-on-error] [--no-summary] <iterations> <command>"
    echo "Example: $0 10 \"echo 'Hello, world!'\""
    exit 1
fi

# Validate iterations is a positive integer
if ! [[ "$iterations" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: iterations must be a positive integer"
    exit 1
fi

echo "Running command '$command' $iterations times..."
echo "=================================================="

# Arrays to store timing data
declare -a times
declare -a exit_codes
successful_runs=0
failed_runs=0

# Run the command specified number of times
for ((i=1; i<=iterations; i++)); do
    echo "Run $i/$iterations:"
    
    # Record start time
    start_time=$(date +%s.%N)
    
    # Run the command
    if eval "$command"; then
        exit_code=0
        ((successful_runs++)) || true
    else
        exit_code=$?
        ((failed_runs++)) || true
        if [[ "$continue_on_error" == false ]]; then
            echo "Command failed with exit code $exit_code. Stopping."
            exit $exit_code
        fi
    fi
    
    # Record end time and calculate duration
    end_time=$(date +%s.%N)
    duration=$(awk "BEGIN {printf \"%.9f\", $end_time - $start_time}")
    times+=($duration)
    exit_codes+=($exit_code)
    
    echo "Duration: ${duration}s"
    echo "Exit code: $exit_code"
    echo "---"
done

# Print summary if requested
if [[ "$show_summary" == true ]]; then
    echo "=================================================="
    echo "SUMMARY"
    echo "=================================================="
    echo "Total runs: $iterations"
    echo "Successful: $successful_runs"
    echo "Failed: $failed_runs"
    
    if [[ ${#times[@]} -gt 0 ]]; then
        # Calculate average
        total_time=0
        for time in "${times[@]}"; do
            total_time=$(awk "BEGIN {printf \"%.9f\", $total_time + $time}")
        done
        average=$(awk "BEGIN {printf \"%.9f\", $total_time / ${#times[@]}}")
        
        # Calculate variance
        variance=0
        for time in "${times[@]}"; do
            diff=$(awk "BEGIN {printf \"%.9f\", $time - $average}")
            squared_diff=$(awk "BEGIN {printf \"%.9f\", $diff * $diff}")
            variance=$(awk "BEGIN {printf \"%.9f\", $variance + $squared_diff}")
        done
        variance=$(awk "BEGIN {printf \"%.9f\", $variance / ${#times[@]}}")
        
        # Calculate min and max
        min_time=${times[0]}
        max_time=${times[0]}
        for time in "${times[@]}"; do
            if awk "BEGIN {exit !($time < $min_time)}"; then
                min_time=$time
            fi
            if awk "BEGIN {exit !($time > $max_time)}"; then
                max_time=$time
            fi
        done
        
        echo ""
        echo "TIMING STATISTICS"
        echo "Average time: ${average}s"
        echo "Variance: ${variance}s²"
        echo "Min time: ${min_time}s"
        echo "Max time: ${max_time}s"
        echo "Total time: ${total_time}s"
    fi
fi

# Exit with appropriate code
if [[ $failed_runs -gt 0 ]]; then
    exit 1
else
    exit 0
fi

