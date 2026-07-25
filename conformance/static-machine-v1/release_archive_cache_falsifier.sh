#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
    printf '%s\n' \
        'usage: release_archive_cache_falsifier.sh <zig-exe> <repository-root> <reviewed-archive> <global-cache>' >&2
    exit 2
fi

zig_exe=$1
repository_root=$2
reviewed_archive=$3
global_cache=$4
case "$reviewed_archive" in
    -*) reviewed_archive="./$reviewed_archive" ;;
esac
proof_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-release-archive-cache.XXXXXX")
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
        */boundary-release-archive-cache.*) rm -rf "$proof_root" ;;
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

proof_archive="$proof_root/boundary-v0.7.0.tar.gz"
mtime_reference="$proof_root/mtime-reference.tar.gz"
proof_output="$proof_root/rejected-output.txt"
local_cache="$proof_root/local-cache"
process_group_exe="$proof_root/boundary-release-process-group"
process_group_ready="$proof_root/process-group-ready"
mkdir -p "$local_cache"

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
    printf '%s\n' 'archive cache falsifier process-group helper build failed' >&2
    exit 2
fi

run_build() {
    rm -f "$process_group_ready"
    "$process_group_exe" \
        "$process_group_ready" \
        "$zig_exe" build \
        --build-file "$repository_root/build.zig" \
        --cache-dir "$local_cache" \
        --global-cache-dir "$global_cache" \
        check-boundary-static-machine-release-archive-once \
        -Dboundary-release-archive="$proof_archive" &
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
        printf '%s\n' 'archive cache falsifier process-group helper did not become ready' >&2
        return 2
    fi
    if wait "$child_pid"; then
        child_status=0
    else
        child_status=$?
    fi
    child_pid=
    return "$child_status"
}

cp "$reviewed_archive" "$proof_archive"
chmod u+w "$proof_archive"
touch -t 202001010000 "$proof_archive"
cp -p "$proof_archive" "$mtime_reference"

run_build

printf 'X' | dd of="$proof_archive" bs=1 count=1 conv=notrunc 2>/dev/null
touch -r "$mtime_reference" "$proof_archive"

if run_build >"$proof_output" 2>&1; then
    printf '%s\n' \
        'archive cache falsifier failed: substituted current bytes were accepted' >&2
    exit 1
fi

if ! grep -Fq 'archive SHA-256 mismatch' "$proof_output"; then
    printf '%s\n' \
        'archive cache falsifier failed without the expected current-byte rejection' >&2
    sed -n '1,160p' "$proof_output" >&2
    exit 1
fi
