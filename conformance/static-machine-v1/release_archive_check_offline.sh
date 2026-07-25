#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    printf '%s\n' \
        'usage: release_archive_check_offline.sh <zig-exe> <reviewed-archive>' >&2
    exit 2
fi

zig_exe=$1
reviewed_archive=$2
script_directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
proof_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-release-archive-offline.XXXXXX")

cleanup() {
    case "$proof_root" in
        */boundary-release-archive-offline.*) rm -rf "$proof_root" ;;
        *) printf 'refusing to remove unexpected proof root: %s\n' "$proof_root" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

local_cache="$proof_root/local-cache"
global_cache="$proof_root/global-cache"
mkdir -p "$local_cache" "$global_cache"

(
    cd "$repository_root"
    "$zig_exe" run \
        --cache-dir "$local_cache" \
        --global-cache-dir "$global_cache" \
        --dep boundary_static_machine_release_metadata \
        -Mroot=conformance/static-machine-v1/release_archive_check.zig \
        -Mboundary_static_machine_release_metadata=conformance/static-machine-v1/release_metadata.zig \
        -- \
        "$zig_exe" \
        "$reviewed_archive" \
        "$global_cache"
)
