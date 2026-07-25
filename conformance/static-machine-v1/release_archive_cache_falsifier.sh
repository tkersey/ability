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
proof_root=$(mktemp -d "${TMPDIR:-/tmp}/boundary-release-archive-cache.XXXXXX")

cleanup() {
    case "$proof_root" in
        */boundary-release-archive-cache.*) rm -rf "$proof_root" ;;
        *) printf 'refusing to remove unexpected proof root: %s\n' "$proof_root" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

proof_archive="$proof_root/boundary-v0.7.0.tar.gz"
mtime_reference="$proof_root/mtime-reference.tar.gz"
proof_output="$proof_root/rejected-output.txt"
local_cache="$proof_root/local-cache"

cp "$reviewed_archive" "$proof_archive"
chmod u+w "$proof_archive"
touch -t 202001010000 "$proof_archive"
cp -p "$proof_archive" "$mtime_reference"

(
    cd "$repository_root"
    "$zig_exe" build \
        --cache-dir "$local_cache" \
        --global-cache-dir "$global_cache" \
        check-boundary-static-machine-release-archive-once \
        -Dboundary-release-archive="$proof_archive"
)

printf 'X' | dd of="$proof_archive" bs=1 count=1 conv=notrunc 2>/dev/null
touch -r "$mtime_reference" "$proof_archive"

if (
    cd "$repository_root"
    "$zig_exe" build \
        --cache-dir "$local_cache" \
        --global-cache-dir "$global_cache" \
        check-boundary-static-machine-release-archive-once \
        -Dboundary-release-archive="$proof_archive"
) >"$proof_output" 2>&1; then
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
