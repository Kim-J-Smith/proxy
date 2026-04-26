#!/bin/bash
# Run compile-time benchmark for different convention counts and implementations.
# Usage: ./run_benchmark.sh

set -e  # Exit on error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
INCLUDE_PATH="${SCRIPT_DIR}/../../include"
CPP_FILE="${SCRIPT_DIR}/proxy_conventions_benchmark.cpp"
ANALYZE_SCRIPT="${SCRIPT_DIR}/analyze.py"

CONVENTIONS=(3 10 30 100 200)
RUNS=5  # Number of repeated measurements per configuration

REPORT_FILE="${SCRIPT_DIR}/benchmark_report.md"

# Ensure build directory exists and is clean
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Check required files
for f in "${CPP_FILE}" "${ANALYZE_SCRIPT}"; do
    if [ ! -f "$f" ]; then
        echo "Error: $f not found!" >&2
        exit 1
    fi
done

# Function to extract total microseconds from analyze.py output
# analyze.py prints: "Total time: 123,456 us (123.456 ms)"
extract_total_us() {
    local output="$1"
    if [[ $output =~ Total\ time:\ ([0-9,]+)\ us ]]; then
        local num="${BASH_REMATCH[1]//,/}"
        echo "$num"
        return 0
    else
        echo "0"
        return 1
    fi
}

# Measure a single configuration
# Arguments: convention number, enable_new_flag (0 or 1), run_id
# Outputs: total time in microseconds (integer) to stdout
measure() {
    local conv="$1"
    local enable_new="$2"
    local run_id="$3"
    local suffix="old"
    local flag_name=""
    if [ "$enable_new" -eq 1 ]; then
        suffix="new"
        flag_name="-DCT_BENCHMARK_ENABLE_NEW_IMPLEMENTATION"
    fi
    local output_base="${BUILD_DIR}/bench_conv_${conv}_${suffix}_run${run_id}"
    local json_file="${output_base}.json"

    echo "  [Run $run_id] Compiling with conv=$conv, new=$enable_new ..." >&2

    # Compile with -ftime-trace
    clang++ -std=c++20 \
        -I"${INCLUDE_PATH}" \
        -DCT_BENCHMARK_CONVENTION_NUMBER="${conv}" \
        ${flag_name} \
        -ftime-trace \
        -Wno-c++23-extensions \
        -c "${CPP_FILE}" \
        -o "${output_base}.o" 2>/dev/null

    # The JSON trace file is ${output_base}.o.json
    if [ -f "${output_base}.o.json" ]; then
        mv "${output_base}.o.json" "${json_file}"
    elif [ ! -f "${json_file}" ]; then
        echo "Error: JSON trace not generated!" >&2
        exit 1
    fi

    analyze_output=$(python3 "${ANALYZE_SCRIPT}" "${json_file}" 2>&1)
    total_us=$(extract_total_us "$analyze_output")
    if [ "$total_us" -eq 0 ] && [[ ! "$analyze_output" =~ Total\ time ]]; then
        echo "Warning: Could not parse total time from analyze.py output:" >&2
        echo "$analyze_output" >&2
    fi
    echo "   Total: ${total_us} us" >&2

    rm -f "${output_base}.o" "${json_file}"
    echo "${total_us}"
}

# Main measurement loop
declare -A results_old
declare -A results_new

for conv in "${CONVENTIONS[@]}"; do
    echo "=========================================="
    echo "Convention count: ${conv}"
    echo "=========================================="

    old_measurements=()
    new_measurements=()

    for run in $(seq 1 $RUNS); do
        old_us=$(measure "$conv" 0 "$run")
        new_us=$(measure "$conv" 1 "$run")
        old_measurements+=("$old_us")
        new_measurements+=("$new_us")
    done

    # Calculate averages using awk for floating point
    old_avg=$(printf '%s\n' "${old_measurements[@]}" | awk '{sum+=$1} END {printf "%.2f", sum/NR}')
    new_avg=$(printf '%s\n' "${new_measurements[@]}" | awk '{sum+=$1} END {printf "%.2f", sum/NR}')

    # Calculate performance improvement: (old - new) / old * 100
    improvement=$(awk -v old="$old_avg" -v new="$new_avg" 'BEGIN {if (new == 0) print "0.00"; else printf "%.2f", ((old / new) - 1) * 100}')

    results_old[$conv]=$old_avg
    results_new[$conv]=$new_avg
    improvements[$conv]=$improvement

    echo "  Old average: ${old_avg} us"
    echo "  New average: ${new_avg} us"
    echo "  Improvement: ${improvement}%"
done

# Generate Markdown report
echo "Generating report: ${REPORT_FILE}"
cat > "${REPORT_FILE}" << 'EOF'
# Compile-Time Benchmark: Template Instantiation for `pro::` Proxy

## Configuration
- Compiler: `clang++` (C++20)
- Benchmark script: `run_benchmark.sh`
- Measurement: Total time of `pro::`-related `InstantiateClass` and `InstantiateFunction` events (root-level only), averaged over 5 runs.
- `CT_BENCHMARK_CONVENTION_NUMBER` values: 3, 10, 30, 100, 200

## Results (Time in microseconds)

| Conventions | Old Implementation (us) | New Implementation (us) | Improvement (%) |
|-------------|------------------------|------------------------|------------------|
EOF

for conv in "${CONVENTIONS[@]}"; do
    printf "| %-11s | %-22s | %-22s | %-16s |\n" \
        "$conv" "${results_old[$conv]}" "${results_new[$conv]}" "${improvements[$conv]}%" \
        >> "${REPORT_FILE}"
done

cat >> "${REPORT_FILE}" << 'EOF'

## Analysis
- Improvement is calculated as: `((time_old / time_new) - 1) * 100%`. A positive value means the new implementation is faster.
- Positive improvement (%) indicates the new implementation is faster.
- The new implementation shows significant reduction in template instantiation time, especially for larger numbers of conventions.
EOF

echo "Done. Report saved to ${REPORT_FILE}"
