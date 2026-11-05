#!/bin/bash
# swift_sql's tests on Apple's platforms (the system's SQLite), built on
# Linux as a macos_unit_test bundle (MODULE.bazel, BUILD.bazel) in a
# container leased from the runner's Mac's OS Server, Bazel's tree kept in
# a volume between runs, then run on a slot of OS Server's primary Mac
# (`oss machine lease mac`: a macOS user of its own on a VM that stays up,
# ready in seconds), not in a macOS VM leased for the job: the macOS VMs
# are left to the agents that need one (Logan, 3 Nov 2026).
#
#   tools/ci/mac_vm_tests.sh
#
#   OSS_FILES_HOST      the name a container reaches this Mac's OS Server by
#                       (default: this Mac's tailnet name, from Tailscale)
#   SWIFT_SQL_CI_IMAGE  the builder (default: Visor's agent image, its 0.43
#                       line: Swift, clang and bazelisk)
#
# The tree goes into the container on standard input and the bundle comes
# out on standard output (base64, between markers), Bazel's log on
# standard error. The slot
# is the script's alone, released however it ends.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${SWIFT_SQL_CI_IMAGE:-ghcr.io/attilathefun/visor-agent:0.43}"
# Xcode 27.2's SDK archive, in OS Server's files by its SHA-256.
SDK_SHA256="b1583e60f9fd35881b5a948ce71627079877f1ced7ea231e14d3c342dd389668"
OSS="/Applications/OS Server.app/Contents/Helpers/oss"
[ -x "$OSS" ] || OSS="$(command -v oss)"
me="$(basename "$0")"

# OS Server's host, for its Bazel cache and files: OSS_FILES_HOST, else the
# first of OSS_SERVERS (an OS Server runner's), else this Mac's Tailscale name.
host="${OSS_FILES_HOST:-}"
if [ -z "$host" ] && [ -n "${OSS_SERVERS:-}" ]; then
    host="${OSS_SERVERS%%[ ,]*}"
    host="${host#*://}"
    host="${host%%[:/]*}"
fi
if [ -z "$host" ]; then
    host="$(/Applications/Tailscale.app/Contents/MacOS/Tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
fi

work="$(mktemp -d)"
slot=""
child=""
finished=""
# The slot given back, the work deleted, however the script ends; an end
# before `finished` is a failure, whatever it says (macOS's bash runs the
# EXIT trap with $? 0 when an unset variable stops the script).
cleanup() {
    local status=$?
    [ -n "$finished" ] || [ "$status" -ne 0 ] || status=1
    [ -z "$child" ] || kill "$child" 2> /dev/null || true
    [ -n "$slot" ] || slot="$(. "$work/lease" 2> /dev/null; printf '%s' "${OSS_ID:-}")"
    if [ -n "$slot" ]; then
        "$OSS" machine release "$slot" || echo "$me: slot $slot was not released: oss machine release $slot" >&2
    fi
    rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Long commands run in the background and are waited for, so a signal (the
# runner cancelling the job) reaches the trap at once, not when they end.
run() {
    "$@" &
    child=$!
    local status=0
    wait "$child" || status=$?
    child=""
    return "$status"
}
# The same with a file on its standard input (a command put in the
# background otherwise reads /dev/null).
run_from() {
    local input="$1"
    shift
    "$@" < "$input" &
    child=$!
    local status=0
    wait "$child" || status=$?
    child=""
    return "$status"
}

# In the container: the bundle built (the SDK archive and the cache from
# OS Server, by the host named), then written out as base64.
steps='set -e
mkdir -p /tmp/swift_sql && tar -x -C /tmp/swift_sql && cd /tmp/swift_sql
echo "rewrite apple-sdks\.invalid/.* http://$1:7490/files/sha256/$2" > /tmp/downloader.cfg
flags="--config=apple_on_linux --downloader_config=/tmp/downloader.cfg"
bazel build $flags --curses=no --color=no //:SwiftSQLTests >&2
bundle="$(bazel cquery $flags --output=files //:SwiftSQLTests 2> /dev/null | grep "\.zip$")"
echo "-- the bundle --"
base64 -w0 "$(bazel info $flags execution_root 2> /dev/null)/$bundle"
echo
echo "-- end --"'

echo "::group::The tests, built on Linux"
git -C "$ROOT" archive --format=tar -o "$work/tree.tar" HEAD
run_from "$work/tree.tar" "$OSS" machine run container --image="$IMAGE" --cpus=4 --memory=8 \
    --volume=swift_sql-ci:/var/cache/bazel:32:keep --inside --cache="$host" --workdir=/ -- \
    sh -c "$steps" sh "$host" "$SDK_SHA256" > "$work/bundle.b64"
# The bundle alone, whatever else came out on standard output.
sed -n '/^-- the bundle --$/,/^-- end --$/p' "$work/bundle.b64" | sed '1d;$d' | base64 --decode > "$work/SwiftSQLTests.zip"
ls -l "$work/SwiftSQLTests.zip"
echo "::endgroup::"

echo "::group::A slot on the primary Mac"
started=$SECONDS
run "$OSS" machine lease mac --wait --minutes=30 --exports > "$work/lease"
slot="$(. "$work/lease"; printf '%s' "$OSS_ID")"
echo "Slot $slot, in $((SECONDS - started))s"
echo "::endgroup::"

echo "::group::The tests"
started=$SECONDS
status=0
run "$OSS" machine xctest "$slot" --tests="$work/SwiftSQLTests.zip" > "$work/test.log" 2>&1 || status=$?
executed="$(grep -E 'Executed [0-9]+ tests?' "$work/test.log" | tail -1 | sed 's/^[[:space:]]*//')"
if [ "$status" -eq 0 ]; then
    echo "SwiftSQLTests PASSED in $((SECONDS - started))s: ${executed:-no count}"
else
    echo "SwiftSQLTests FAILED ($status) in $((SECONDS - started))s: ${executed:-no count}"
    tail -60 "$work/test.log"
    echo "::error::swift_sql's tests failed on the Mac ($status)"
fi
echo "::endgroup::"
finished=1
exit "$status"
