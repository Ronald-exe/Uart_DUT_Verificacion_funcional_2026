#!/usr/bin/env bash
set -euo pipefail

args_file=${1:?Usage: run_sim.sh PLUSARGS_FILE [SIMULATOR_ARGUMENTS...]}
shift
if [[ ! -f "$args_file" ]]; then
    printf 'Plusargs file not found: %s\n' "$args_file" >&2
    exit 2
fi

args=()
declare -A seen=()
line_number=0
while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number+1))
    line=${line%$'\r'}
    # Match the previous project file style -- also accept the existing // scenario comments
    # Read tokens as data, never source or eval the file -- alex
    line=${line%%#*}
    line=${line%%//*}
    words=()
    read -r -a words <<< "$line"
    for word in "${words[@]}"; do
        if [[ ! "$word" =~ ^\+[A-Za-z_][A-Za-z0-9_]*= ]]; then
            printf '%s:%s: expected +NAME=value, got %s\n' "$args_file" "$line_number" "$word" >&2
            exit 2
        fi
        key=${word%%=*}
        # Two uncommented entries for one knob are ambiguous -- do not silently let the simulator choose one
        # Keep an empty value intact because +UART_SCB_WAIVE_BUGS= is intentional strict mode -- alex
        if [[ -n "${seen[$key]+present}" ]]; then
            printf '%s:%s: duplicate plusarg %s\n' "$args_file" "$line_number" "$key" >&2
            exit 2
        fi
        seen[$key]=1
        args+=("$word")
    done
done < "$args_file"

# Make passes simulator controls separately -- reject duplicated knobs there too instead of relying on argument order -- alex
for word in "$@"; do
    if [[ "$word" =~ ^\+[A-Za-z_][A-Za-z0-9_]*= ]]; then
        key=${word%%=*}
        if [[ -n "${seen[$key]+present}" ]]; then
            printf 'Duplicate plusarg between file and command line: %s\n' "$key" >&2
            exit 2
        fi
        seen[$key]=1
    fi
done
exec ./simv "${args[@]}" "$@"
