#!/usr/bin/env bash
set -u -o pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

count=${1:-20}
args_file=${2:-plusargs.args}
bus_width=${BUS8:-0}
baud_output=${BAUD:-1}
if [[ ! "$count" =~ ^[1-9][0-9]*$ ]] || [[ ! -f "$args_file" ]]; then
    echo "Usage: ./run_regression.sh SEED_COUNT ARGS_FILE" >&2
    exit 2
fi
if [[ ! "$bus_width" =~ ^[01]$ ]] || [[ ! "$baud_output" =~ ^[01]$ ]]; then
    echo "BUS8 and BAUD must be 0 or 1" >&2
    exit 2
fi
# Use a fresh name even when restarting at seed one -- old logs and coverage must not satisfy checks for this batch -- alex
run_id="$(date +%Y%m%d_%H%M%S)_$$"
cov_dir="coverage/run_${run_id}_bus${bus_width}_baud${baud_output}.vdb"
summary="regression_${run_id}.txt"
mkdir -p coverage
printf 'run=%s count=%s args=%s BUS8=%s BAUD=%s coverage=%s\n' \
    "$run_id" "$count" "$args_file" "$bus_width" "$baud_output" "$cov_dir" > "$summary"
if ! make comp BUS8="$bus_width" BAUD="$baud_output" COV_DIR="$cov_dir"; then
    printf 'Compilation failed\n' >> "$summary"
    exit 1
fi
failed=0
for ((seed=1; seed<=count; seed++)); do
    label="${run_id}_${seed}"
    log="run_${label}.log"
    if ! make run TEST=uart_base_test SEED="$seed" PLUSARGS_FILE="$args_file" ARGS= \
        BUS8="$bus_width" BAUD="$baud_output" COV_DIR="$cov_dir" RUN_LABEL="$label"; then
        printf 'seed=%s FAILED process exit\n' "$seed" >> "$summary"
        failed=$((failed+1))
        continue
    fi
    # VCS can return zero after a reported failure -- inspect this run rather than trusting its exit code alone
    # Require a fresh pass marker, clean UVM counts and no native simulator errors before accepting the seed -- alex
    if [[ ! -f "$log" ]] || ! grep -Eq '\[UART_PASS(_WITH_KNOWN_BUGS)?\]' "$log" || \
       grep -Eq '^UVM_(ERROR|FATAL)[[:space:]].*(@|\[)|^(Error|Fatal)(:|-\[)' "$log"; then
        printf 'seed=%s FAILED UVM result -- %s\n' "$seed" "$log" >> "$summary"
        failed=$((failed+1))
    # Require both final severity counts -- a truncated log with no errors printed yet is not evidence of a completed clean run -- alex
    elif ! awk '/^UVM_ERROR[[:space:]]*:/ {e=1; errors=$NF+0} /^UVM_FATAL[[:space:]]*:/ {f=1; fatals=$NF+0} END {exit !(e && f && errors==0 && fatals==0)}' "$log"; then
        printf 'seed=%s FAILED missing or nonzero severity summary -- %s\n' "$seed" "$log" >> "$summary"
        failed=$((failed+1))
    else
        printf 'seed=%s PASS -- %s\n' "$seed" "$log" >> "$summary"
    fi
done
printf 'passed=%s failed=%s\n' "$((count-failed))" "$failed" >> "$summary"
cat -- "$summary"
if ((failed != 0)); then
    exit 1
fi
# Merge only after every seed passes -- a failed batch must not look like validated delivery evidence -- alex
make cov COV_DIR="$cov_dir"
