#!/bin/sh
set -eu

baseline_tag=v0.7.0
baseline_commit=7f2472100454aa2cd5c62e07db0c1e23eaf46a77
release_checkout_error='Boundary release performance proof requires a tagged Boundary source checkout with local .git metadata'

require_release_checkout() {
    checkout_root=$1
    if ! test -e "$checkout_root/.git"; then
        echo "$release_checkout_error" >&2
        return 1
    fi
    if ! resolved_checkout_root=$(
        git -C "$checkout_root" rev-parse --show-toplevel 2>/dev/null
    ); then
        echo "$release_checkout_error" >&2
        return 1
    fi
    if test "$resolved_checkout_root" != "$checkout_root"; then
        echo "$release_checkout_error" >&2
        return 1
    fi
}

require_optimization_mode() {
    case "$1" in
        ReleaseFast|ReleaseSmall) ;;
        *)
            echo "unsupported performance optimization mode: $1" >&2
            return 1
            ;;
    esac
}

current_runtime_semantic_module_count() {
    source_root=$1
    topology_receipt=$2
    test -f "$topology_receipt" || return 1

    core_module_count=$(
        sed -n 's/^core_module_count=//p' "$topology_receipt"
    )
    reducer_count=$(
        sed -n 's/^reducer_count=//p' "$topology_receipt"
    )
    reducer_owner=$(
        sed -n 's/^reducer_owner=//p' "$topology_receipt"
    )
    case "$core_module_count" in
        ''|*[!0-9]*) return 1 ;;
    esac
    case "$reducer_count" in
        ''|*[!0-9]*) return 1 ;;
    esac
    test "$reducer_count" -eq 1 || return 1
    test "$reducer_owner" = machine || return 1

    expected_sources=$(
        sed -n 's/^source_module [^ ]* \([^ ]*\) [^ ]*$/\1/p' \
            "$topology_receipt" |
            sort
    )
    actual_sources=$(
        find "$source_root/src" -maxdepth 1 -type f -name '*.zig' |
            sed "s#^$source_root/##" |
            sort
    )
    test "$actual_sources" = "$expected_sources" || return 1
    source_module_count=$(printf '%s\n' "$expected_sources" | sed '/^$/d' | wc -l | tr -d ' ')
    test "$source_module_count" -eq "$((core_module_count + 1))" ||
        return 1

    reducer_sources=$(
        sed -n 's/^source_module [^ ]* \([^ ]*\) reducer$/\1/p' \
            "$topology_receipt"
    )
    test "$reducer_sources" = src/machine.zig || return 1
    printf '%s\n' "$reducer_count"
}

require_current_wasm_schema() {
    current_source=$1/test/machine_performance.zig
    rg -Fq 'const RequestPayload = portable_value.Text(16);' "$current_source"
    rg -Fq 'pub const Resume = i32;' "$current_source"
    rg -Fq 'pub const Result = i32;' "$current_source"
    rg -Fq 'RequestPayload.fromSlice("payload")' "$current_source"
    rg -Fq \
        'pub export fn boundaryMachinePerformanceOneEffect(response: i32) i32 {' \
        "$current_source"
    rg -Fq 'const payload_observation = std.math.add(' "$current_source"
    rg -Fq 'done.value().*,' "$current_source"
}

require_baseline_wasm_schema() {
    baseline_wasm_source=$1/test/static_machine_wasm32_compile.zig
    rg -Fq '.kind = .const_string' "$baseline_wasm_source"
    rg -Fq '.string_literal = "payload"' "$baseline_wasm_source"
    rg -Fq '.payload_codec = .string' "$baseline_wasm_source"
    rg -Fq '.resume_codec = .i32' "$baseline_wasm_source"
    rg -Fq '.result_codec = .i32' "$baseline_wasm_source"
}

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
        { echo "decode runtime exact limit was rejected" >&2; exit 1; }
    if within_ratio 126 100 125 100; then
        echo "decode runtime regression was accepted" >&2
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
    require_optimization_mode ReleaseSmall
    if require_optimization_mode Debug 2>/dev/null; then
        echo "unsupported optimization mode was accepted" >&2
        exit 1
    fi
    topology_test_root=$(
        mktemp -d "${TMPDIR:-/tmp}/boundary-rnf-topology.XXXXXX"
    )
    case "$(basename -- "$topology_test_root")" in
        boundary-rnf-topology.*) ;;
        *)
            echo "refusing unsafe topology test path: $topology_test_root" >&2
            exit 1
            ;;
    esac
    cleanup_topology_test() {
        if test -d "$topology_test_root"; then
            rm -rf -- "$topology_test_root"
        fi
    }
    trap cleanup_topology_test EXIT HUP INT TERM
    mkdir "$topology_test_root/src"
    touch "$topology_test_root/src/root.zig"
    touch "$topology_test_root/src/machine.zig"
    topology_test_receipt="$topology_test_root/topology.txt"
    printf '%s\n' \
        'core_module_count=1' \
        'reducer_count=1' \
        'reducer_owner=machine' \
        'source_module root src/root.zig public_root' \
        'source_module machine src/machine.zig reducer' \
        >"$topology_test_receipt"
    test "$(current_runtime_semantic_module_count \
        "$topology_test_root" "$topology_test_receipt")" -eq 1
    touch "$topology_test_root/src/alternate_reducer.zig"
    if current_runtime_semantic_module_count \
        "$topology_test_root" "$topology_test_receipt" >/dev/null 2>&1
    then
        echo "unclassified production reducer was accepted" >&2
        exit 1
    fi
    cleanup_topology_test
    trap - EXIT HUP INT TERM
    require_current_wasm_schema "$script_directory/../.."
    rg -Fq '+        .{ .kind = .const_string' \
        "$script_directory/v0.7.0-performance.patch"
    rg -Fq '+        .payload_codec = .string' \
        "$script_directory/v0.7.0-performance.patch"
    rg -Fq '+        .resume_codec = .i32' \
        "$script_directory/v0.7.0-performance.patch"
    rg -Fq '+        .result_codec = .i32' \
        "$script_directory/v0.7.0-performance.patch"
    node "$script_directory/measure_wasm.mjs" --self-test |
        grep -qx 'wasm_measurement_falsifier=pass'
    if missing_checkout_output=$(
        require_release_checkout "$script_directory" 2>&1
    ); then
        echo "package-only performance proof invocation was accepted" >&2
        exit 1
    fi
    printf '%s\n' "$missing_checkout_output" |
        grep -Fqx "$release_checkout_error"
    echo "boundary_performance_falsifiers=pass"
}

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if test "${1:-}" = "--self-test"; then
    self_test
    exit 0
fi

if test "$#" -ne 5; then
    echo "usage: check_performance.sh CURRENT_TEST CURRENT_WASM ZIG_EXE WASM_OPTIMIZATION TOPOLOGY_RECEIPT" >&2
    exit 2
fi

current_test=$1
current_wasm=$2
zig_exe=$3
wasm_optimization=$4
topology_receipt=$5
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

test -x "$current_test"
test -f "$current_wasm"
test -x "$zig_exe"
require_optimization_mode "$wasm_optimization"

require_release_checkout "$repository_root"
if ! actual_baseline_commit=$(
    git -C "$repository_root" rev-parse "${baseline_tag}^{commit}" 2>/dev/null
); then
    echo "Boundary release performance proof requires local tag $baseline_tag" >&2
    exit 1
fi
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
require_current_wasm_schema "$repository_root"
require_baseline_wasm_schema "$baseline_source"

if ! baseline_output=$(
    cd "$baseline_source"
    "$zig_exe" build check-boundary-static-machine \
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
within_ratio "$current_decode_median" "$baseline_decode_median" 125 100

if ! install_output=$(
    cd "$baseline_source"
    "$zig_exe" build install -Doptimize="$wasm_optimization" 2>&1
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
        boundaryMachinePerformanceOneEffect
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
current_runtime_semantic_modules=$(
    current_runtime_semantic_module_count "$repository_root" "$topology_receipt"
)
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
    "decode_runtime_ratio_limit=1.25" \
    "runtime_ratio_limit=1.25" \
    "baseline_wasm_step_ns=$baseline_wasm_step_ns" \
    "current_wasm_step_ns=$current_wasm_step_ns" \
    "wasm_runtime_ratio_limit=1.25" \
    "baseline_wasm_bytes=$baseline_wasm_bytes" \
    "current_wasm_bytes=$current_wasm_bytes" \
    "wasm_ratio_limit=1.50" \
    "wasm_optimization=$wasm_optimization" \
    "wasm_payload_schema=string" \
    "wasm_resume_schema=i32" \
    "wasm_result_schema=i32" \
    "current_wasm_witness=machine-performance-one-effect" \
    "baseline_runtime_semantic_modules=$baseline_runtime_semantic_modules" \
    "current_runtime_semantic_modules=$current_runtime_semantic_modules"
