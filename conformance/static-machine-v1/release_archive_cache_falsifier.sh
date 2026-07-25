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

cleanup() {
    case "$proof_root" in
        */boundary-release-archive-cache.*) rm -rf "$proof_root" ;;
        *) printf 'refusing to remove unexpected proof root: %s\n' "$proof_root" >&2 ;;
    esac
}
on_signal() {
    signal_status=$1
    if [ -n "$child_pid" ]; then
        kill -TERM "$child_pid" 2>/dev/null || :
        wait "$child_pid" 2>/dev/null || :
    fi
    exit "$signal_status"
}
trap cleanup EXIT
trap 'on_signal 129' HUP
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap >"$proof_root/trap-state"
if ! grep -Fq 'on_signal 130' "$proof_root/trap-state"; then
    printf '%s\n' 'release archive check signal handler unavailable: INT' >&2
    exit 2
fi

proof_archive="$proof_root/boundary-v0.7.0.tar.gz"
mtime_reference="$proof_root/mtime-reference.tar.gz"
proof_output="$proof_root/rejected-output.txt"
local_cache="$proof_root/local-cache"

run_build() {
    (
        cd "$repository_root"
        exec "$zig_exe" build \
            --cache-dir "$local_cache" \
            --global-cache-dir "$global_cache" \
            check-boundary-static-machine-release-archive-once \
            -Dboundary-release-archive="$proof_archive"
    ) &
    child_pid=$!
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
