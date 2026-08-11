#!/usr/bin/env bash
# Reproducible, low-risk timing probe for a mounted network filesystem
# (Isilon/SMB, PetaLibrary/sshfs, or anything else mounted under a local
# path). Measures directory-listing, sequential-write, and warm-read timing
# using a disposable test directory it creates and deletes itself.
#
# It NEVER touches, lists, or names anything outside the disposable test
# directory it creates, and it never unmounts anything. Forcing a true
# cold-read measurement by unmounting/remounting was tried by hand once and
# broke a live mount's non-interactive auth (see
# docs/storage-mount-benchmark.md) - this script deliberately does not
# attempt that.
#
# Usage:
#   ./benchmark_storage_mount.sh <mount-path> [size-mb]
#
# Example:
#   ./benchmark_storage_mount.sh ~/mnt/some-share 20

set -euo pipefail

MOUNT_PATH="${1:?Usage: $0 <mount-path> [size-mb]}"
SIZE_MB="${2:-20}"

if [ ! -d "$MOUNT_PATH" ]; then
    echo "✗ Not a directory: $MOUNT_PATH" >&2
    exit 1
fi

if ! mount | grep -qF " $MOUNT_PATH "; then
    echo "! Warning: $MOUNT_PATH doesn't appear in \`mount\` output." >&2
    echo "  Continuing anyway - this may just be a local path for comparison." >&2
fi

TESTDIR="$MOUNT_PATH/.benchmark-test-$$"
TESTFILE="$TESTDIR/probe.bin"

cleanup() {
    rm -f "$TESTFILE" 2>/dev/null || true
    rmdir "$TESTDIR" 2>/dev/null || true
}
trap cleanup EXIT

# Portable wall-clock timer (avoids depending on bash's `time` builtin output
# format, which differs across shells/versions).
timed() {
    local start end
    start=$(date +%s.%N)
    "$@" >/dev/null
    end=$(date +%s.%N)
    awk -v s="$start" -v e="$end" 'BEGIN { printf "%.3f", e - s }'
}

echo "Target: $MOUNT_PATH"
echo "Test file size: ${SIZE_MB}MB"
echo ""

t_list_root=$(timed ls -la "$MOUNT_PATH")
echo "1. List existing root contents ......... ${t_list_root}s"

t_mkdir=$(timed mkdir "$TESTDIR")
echo "2. Create disposable test dir ........... ${t_mkdir}s"

t_list_empty=$(timed ls -la "$TESTDIR")
echo "3. List freshly created empty dir ....... ${t_list_empty}s"

t_write=$(timed dd if=/dev/zero of="$TESTFILE" bs=1m count="$SIZE_MB")
write_rate=$(awk -v mb="$SIZE_MB" -v t="$t_write" 'BEGIN { if (t > 0) printf "%.1f", mb / t; else print "n/a" }')
echo "4. Write ${SIZE_MB}MB sequential ................ ${t_write}s (~${write_rate} MB/s)"
sync

t_list_full=$(timed ls -la "$TESTDIR")
echo "5. List dir after write (1 file) ........ ${t_list_full}s"

t_read=$(timed dd if="$TESTFILE" bs=1m)
echo "6. Read ${SIZE_MB}MB back (WARM/CACHED, not a real network number) ... ${t_read}s"
echo "   ^ this is almost certainly served from the local page cache, not"
echo "     the network - see docs/storage-mount-benchmark.md before citing it."

cleanup
trap - EXIT
echo ""
echo "Cleaned up: $TESTDIR"
