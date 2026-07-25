#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' \
        'usage: release_archive_check_offline.sh <zig-exe> <reviewed-archive>' >&2
    exit 2
fi

zig_exe=$1
reviewed_archive=$2

absolute_path() {
    path_input=$1
    case "$path_input" in
        /*) printf '%s\n' "$path_input" ;;
        */*)
            path_leaf=${path_input##*/}
            path_directory=${path_input%/*}
            path_directory=$(
                CDPATH= cd -- "$path_directory" &&
                    pwd
            ) || return
            printf '%s/%s\n' "$path_directory" "$path_leaf"
            ;;
        *) printf '%s/%s\n' "$PWD" "$path_input" ;;
    esac
}

case "$zig_exe" in
    */*) ;;
    *)
        zig_exe=$(command -v "$zig_exe") || {
            printf 'zig executable not found: %s\n' "$zig_exe" >&2
            exit 2
        }
        ;;
esac
zig_exe=$(absolute_path "$zig_exe")
case "$reviewed_archive" in
    -*) reviewed_archive="./$reviewed_archive" ;;
esac
reviewed_archive=$(absolute_path "$reviewed_archive")
script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
proof_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-release-archive-offline.XXXXXX")
proof_root=$(CDPATH= cd -- "$proof_root" && pwd)
child_pid=
cleanup_allowed=yes

cleanup() {
    if [ "$cleanup_allowed" != yes ]; then
        printf 'retaining proof root after incomplete process-group shutdown: %s\n' \
            "$proof_root" >&2
        return
    fi
    case "$proof_root" in
        */boundary-release-archive-offline.*) rm -rf "$proof_root" ;;
        *) printf 'refusing to remove unexpected proof root: %s\n' "$proof_root" >&2 ;;
    esac
}
terminate_child() {
    if [ -n "$child_pid" ]; then
        terminating_pid=$child_pid
        # Direct-first covers pre-setpgid cancellation; group-second closes
        # the spawn race after the helper owns its process group.
        kill -TERM "$terminating_pid" 2>/dev/null || :
        kill -TERM -"$terminating_pid" 2>/dev/null || :
        wait "$child_pid" 2>/dev/null || :
        shutdown_attempt=0
        while kill -0 -"$terminating_pid" 2>/dev/null; do
            shutdown_attempt=$((shutdown_attempt + 1))
            if [ "$shutdown_attempt" -eq 4 ]; then
                kill -KILL -"$terminating_pid" 2>/dev/null || :
            fi
            if [ "$shutdown_attempt" -ge 8 ]; then
                cleanup_allowed=no
                child_pid=
                return 1
            fi
            sleep 1
        done
        child_pid=
    fi
}
on_signal() {
    signal_status=$1
    terminate_child || :
    exit "$signal_status"
}
trap cleanup EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
if ! sh -c 'trap "exit 0" INT; kill -INT "$$"; exit 1'; then
    printf '%s\n' 'release archive check signal handler unavailable: INT' >&2
    exit 2
fi

local_cache="$proof_root/local-cache"
global_cache="$proof_root/global-cache"
mkdir -p "$local_cache" "$global_cache"
process_group_exe="$proof_root/boundary-release-process-group"
process_group_ready="$proof_root/process-group-ready"
completion_receipt="$proof_root/archive-check-complete"

"$zig_exe" build-exe \
    --cache-dir "$local_cache" \
    --global-cache-dir "$global_cache" \
    -OReleaseSafe \
    -femit-bin="$process_group_exe" \
    "$repository_root/conformance/static-machine-v1/release_process_group.zig" &
child_pid=$!
if wait "$child_pid"; then
    child_status=0
else
    child_status=$?
fi
child_pid=
if [ "$child_status" -ne 0 ] || [ ! -x "$process_group_exe" ]; then
    printf '%s\n' 'release archive check process-group helper build failed' >&2
    exit 2
fi

"$process_group_exe" \
    "$process_group_ready" \
    "$zig_exe" run \
    --cache-dir "$local_cache" \
    --global-cache-dir "$global_cache" \
    --dep boundary_static_machine_release_metadata \
    -Mroot="$repository_root/conformance/static-machine-v1/release_archive_check.zig" \
    -Mboundary_static_machine_release_metadata="$repository_root/conformance/static-machine-v1/release_metadata.zig" \
    -- \
    "$zig_exe" \
    "$reviewed_archive" \
    "$global_cache" \
    "$proof_root" \
    "$completion_receipt" &
child_pid=$!
while [ ! -f "$process_group_ready" ]; do
    if ! kill -0 "$child_pid" 2>/dev/null; then
        break
    fi
    sleep 1
done
ready_line=
if [ -f "$process_group_ready" ]; then
    IFS= read -r ready_line <"$process_group_ready" || :
fi
if [ "$ready_line" != "boundary-release-process-group/v1 $child_pid" ]; then
    terminate_child || :
    printf '%s\n' 'release archive check process-group helper did not become ready' >&2
    exit 2
fi
if wait "$child_pid"; then
    child_status=0
else
    child_status=$?
fi
child_pid=
if [ "$child_status" -ne 0 ]; then
    exit "$child_status"
fi
if [ ! -f "$completion_receipt" ]; then
    printf '%s\n' 'release archive checker did not write its completion receipt' >&2
    exit 2
fi
exec 3<"$completion_receipt"
completion_line=
completion_valid=yes
if ! IFS= read -r completion_line <&3 ||
    [ "$completion_line" != 'boundary-release-archive-check/v1' ]
then
    completion_valid=no
else
    completion_extra=
    if IFS= read -r completion_extra <&3 || [ -n "$completion_extra" ]; then
        completion_valid=no
    fi
fi
exec 3<&-
if [ "$completion_valid" != yes ]; then
    printf '%s\n' 'release archive checker wrote an invalid completion receipt' >&2
    exit 2
fi
