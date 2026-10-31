#!/bin/bash
# swift_sql's tests on Apple's platforms (the system's SQLite), in a macOS VM
# leased from OS Server (xcode-27.0): `swift test`.
#
#   tools/ci/mac_vm_tests.sh
#
# The VM (tools/ci/mac_vm.sh) is the script's alone, released however it
# ends.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
. "$ROOT/tools/ci/mac_vm.sh"
mac_vm_start swift_sql-ci

mac_vm_steps << 'STEPS'
    test)
        cd swift_sql && swift test
        ;;
STEPS

echo "::group::A macOS VM (xcode-27.0)"
mac_vm_lease
mac_vm_copy_tree
echo "::endgroup::"

status=0
run in_vm test || status=$?
[ "$status" -eq 0 ] || echo "::error::swift test failed ($status)"
mac_vm_release
finished=1
exit "$status"
