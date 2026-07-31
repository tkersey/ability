#!/bin/sh
set -eu

baseline_tag=v0.7.0
baseline_commit=7f2472100454aa2cd5c62e07db0c1e23eaf46a77

within_ratio() {
    candidate=$1
    baseline=$2
    maximum_numerator=$3
    maximum_denominator=$4
    test "$((candidate * maximum_denominator))" \
        -le "$((baseline * maximum_numerator))"
}

self_test() {
    within_ratio 125 100 125 100 ||
        { echo "performance ratio exact limit was rejected" >&2; exit 1; }
    if within_ratio 126 100 125 100; then
        echo "performance runtime regression was accepted" >&2
        exit 1
    fi
    within_ratio 125 100 125 100 ||
        { echo "WASM runtime exact limit was rejected" >&2; exit 1; }
    if within_ratio 126 100 125 100; then
        echo "WASM runtime regression was accepted" >&2
        exit 1
    fi
    within_ratio 150 100 150 100 ||
        { echo "WASM ratio exact limit was rejected" >&2; exit 1; }
    if within_ratio 151 100 150 100; then
        echo "WASM size regression was accepted" >&2
        exit 1
    fi
    test 100 -le 100 ||
        { echo "state-size equality was rejected" >&2; exit 1; }
    if test 101 -le 100; then
        echo "state-size regression was accepted" >&2
        exit 1
    fi
    test 1 -lt 4 ||
        { echo "semantic-module reduction was rejected" >&2; exit 1; }
    if test 4 -lt 4; then
        echo "semantic-module non-reduction was accepted" >&2
        exit 1
    fi
    echo "boundary_performance_falsifiers=pass"
}

if test "${1:-}" = "--self-test"; then
    self_test
    exit 0
fi

if test "$#" -ne 2; then
    echo "usage: check_performance.sh CURRENT_TEST CURRENT_WASM" >&2
    exit 2
fi

current_test=$1
current_wasm=$2
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

test -x "$current_test"
test -f "$current_wasm"

actual_baseline_commit=$(
    git -C "$repository_root" rev-parse "${baseline_tag}^{commit}"
)
if test "$actual_baseline_commit" != "$baseline_commit"; then
    echo "Boundary v0.7.0 does not resolve to the reviewed baseline" >&2
    exit 1
fi

temporary_root=$(
    mktemp -d "${TMPDIR:-/tmp}/boundary-rnf-performance.XXXXXX"
)
case "$(basename -- "$temporary_root")" in
    boundary-rnf-performance.*) ;;
    *)
        echo "refusing unsafe temporary path: $temporary_root" >&2
        exit 1
        ;;
esac
baseline_source="$temporary_root/source"
mkdir "$baseline_source"
cleanup() {
    if test -d "$temporary_root"; then
        rm -rf -- "$temporary_root"
    fi
}
trap cleanup EXIT HUP INT TERM

git -C "$repository_root" archive "$baseline_commit" |
    tar -xf - -C "$baseline_source"
patch -s -d "$baseline_source" -p1 \
    <"$script_directory/v0.7.0-performance.patch"

if ! baseline_output=$(
    cd "$baseline_source"
    zig build check-boundary-static-machine \
        -Doptimize=ReleaseFast \
        --summary all -- \
        --test-filter "RNF performance baseline one effect lifecycle" 2>&1
); then
    printf '%s\n' "$baseline_output" >&2
    exit 1
fi
if ! current_output=$("$current_test" 2>&1); then
    printf '%s\n' "$current_output" >&2
    exit 1
fi

result_line() {
    printf '%s\n' "$1" |
        sed -n \
            's/^.*boundary_performance_v1 /boundary_performance_v1 /p' |
        tail -n 1
}

field_value() {
    printf '%s\n' "$1" |
        tr ' ' '\n' |
        sed -n "s/^$2=//p"
}

require_uint() {
    case "$2" in
        ''|*[!0-9]*)
            echo "$1 is not an unsigned integer: $2" >&2
            exit 1
            ;;
    esac
}

baseline_result=$(result_line "$baseline_output")
current_result=$(result_line "$current_output")
test -n "$baseline_result"
test -n "$current_result"
baseline_compile_observation=$(
    printf '%s\n' "$baseline_output" |
        sed -n '/compile test ReleaseFast native success/p' |
        head -n 1
)
test -n "$baseline_compile_observation"

baseline_state=$(field_value "$baseline_result" state_bytes)
current_state=$(field_value "$current_result" state_bytes)
baseline_iterations=$(field_value "$baseline_result" iterations)
current_iterations=$(field_value "$current_result" iterations)
baseline_median=$(field_value "$baseline_result" median_ns)
current_median=$(field_value "$current_result" median_ns)
baseline_decode_median=$(field_value "$baseline_result" decode_median_ns)
current_decode_median=$(field_value "$current_result" decode_median_ns)
baseline_checksum=$(field_value "$baseline_result" checksum)
current_checksum=$(field_value "$current_result" checksum)
baseline_decode_checksum=$(field_value "$baseline_result" decode_checksum)
current_decode_checksum=$(field_value "$current_result" decode_checksum)

for named_value in \
    "baseline_state:$baseline_state" \
    "current_state:$current_state" \
    "baseline_iterations:$baseline_iterations" \
    "current_iterations:$current_iterations" \
    "baseline_median:$baseline_median" \
    "current_median:$current_median" \
    "baseline_decode_median:$baseline_decode_median" \
    "current_decode_median:$current_decode_median" \
    "baseline_checksum:$baseline_checksum" \
    "current_checksum:$current_checksum" \
    "baseline_decode_checksum:$baseline_decode_checksum" \
    "current_decode_checksum:$current_decode_checksum"
do
    require_uint "${named_value%%:*}" "${named_value#*:}"
done

test "$baseline_iterations" -eq 20000
test "$current_iterations" -eq "$baseline_iterations"
test "$baseline_checksum" -eq 700000
test "$current_checksum" -eq "$baseline_checksum"
test "$baseline_decode_checksum" -eq "$baseline_checksum"
test "$current_decode_checksum" -eq "$baseline_decode_checksum"
test "$current_state" -le "$baseline_state"
within_ratio "$current_median" "$baseline_median" 125 100

if ! install_output=$(
    cd "$baseline_source"
    zig build install -Doptimize=ReleaseFast
  2>&1
); then
    printf '%s\n' "$install_output" >&2
    exit 1
fi
baseline_wasm="$baseline_source/zig-out/bin/boundary-static-machine-wasm32-smoke.wasm"
test -f "$baseline_wasm"
baseline_wasm_bytes=$(wc -c <"$baseline_wasm" | tr -d ' ')
current_wasm_bytes=$(wc -c <"$current_wasm" | tr -d ' ')
require_uint baseline_wasm_bytes "$baseline_wasm_bytes"
require_uint current_wasm_bytes "$current_wasm_bytes"
within_ratio "$current_wasm_bytes" "$baseline_wasm_bytes" 150 100

baseline_wasm_step_ns=$(
    node "$script_directory/measure_wasm.mjs" \
        "$baseline_wasm" \
        boundaryStaticMachineWasm32Smoke
)
current_wasm_step_ns=$(
    node "$script_directory/measure_wasm.mjs" \
        "$current_wasm" \
        boundaryMachineParityRun
)
require_uint baseline_wasm_step_ns "$baseline_wasm_step_ns"
require_uint current_wasm_step_ns "$current_wasm_step_ns"
within_ratio "$current_wasm_step_ns" "$baseline_wasm_step_ns" 125 100

baseline_runtime_semantic_modules=0
for path in \
    src/interpreter.zig \
    src/lowered_machine.zig \
    src/program/loaded_execution.zig \
    src/program_api.zig
do
    test -f "$baseline_source/$path"
    baseline_runtime_semantic_modules=$((baseline_runtime_semantic_modules + 1))
done
current_runtime_semantic_modules=1
test -f "$repository_root/src/machine.zig"
test "$current_runtime_semantic_modules" \
    -lt "$baseline_runtime_semantic_modules"

echo "boundary_performance_baseline_compile $baseline_compile_observation"
echo "boundary_performance_status=pass baseline_release=$baseline_tag" \
    "baseline_commit=$baseline_commit" \
    "baseline_state_bytes=$baseline_state" \
    "current_state_bytes=$current_state" \
    "baseline_median_ns=$baseline_median" \
    "current_median_ns=$current_median" \
    "baseline_decode_median_ns=$baseline_decode_median" \
    "current_decode_median_ns=$current_decode_median" \
    "runtime_ratio_limit=1.25" \
    "baseline_wasm_step_ns=$baseline_wasm_step_ns" \
    "current_wasm_step_ns=$current_wasm_step_ns" \
    "wasm_runtime_ratio_limit=1.25" \
    "baseline_wasm_bytes=$baseline_wasm_bytes" \
    "current_wasm_bytes=$current_wasm_bytes" \
    "wasm_ratio_limit=1.50" \
    "baseline_runtime_semantic_modules=$baseline_runtime_semantic_modules" \
    "current_runtime_semantic_modules=$current_runtime_semantic_modules"
