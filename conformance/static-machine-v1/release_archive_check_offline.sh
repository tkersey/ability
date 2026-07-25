#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' \
        'usage: release_archive_check_offline.sh <zig-exe> <reviewed-archive>' >&2
    exit 2
fi

zig_exe=$1
reviewed_archive=$2
case "$zig_exe" in
    */*) ;;
    *)
        zig_exe=$(command -v "$zig_exe") || {
            printf 'zig executable not found: %s\n' "$zig_exe" >&2
            exit 2
        }
        ;;
esac
case "$zig_exe" in
    /*) ;;
    *)
        zig_exe=$(
            CDPATH= cd -- "$(dirname "$zig_exe")" &&
                printf '%s/%s\n' "$PWD" "$(basename "$zig_exe")"
        )
        ;;
esac
case "$reviewed_archive" in
    -*) reviewed_archive="./$reviewed_archive" ;;
esac
case "$reviewed_archive" in
    /*) ;;
    *)
        reviewed_archive=$(
            CDPATH= cd -- "$(dirname "$reviewed_archive")" &&
                printf '%s/%s\n' "$PWD" "$(basename "$reviewed_archive")"
        )
        ;;
esac
script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
proof_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-release-archive-offline.XXXXXX")
proof_root=$(CDPATH= cd -- "$proof_root" && pwd)
child_pid=

cleanup() {
    case "$proof_root" in
        */boundary-release-archive-offline.*) rm -rf "$proof_root" ;;
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

local_cache="$proof_root/local-cache"
global_cache="$proof_root/global-cache"
mkdir -p "$local_cache" "$global_cache"

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
    "$proof_root" &
child_pid=$!
if wait "$child_pid"; then
    child_status=0
else
    child_status=$?
fi
child_pid=
exit "$child_status"
