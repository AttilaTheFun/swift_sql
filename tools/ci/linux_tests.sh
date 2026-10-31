#!/bin/bash
# swift_sql's tests on Linux (the vendored amalgamation, built from
# cswiftsql.c): `swift test` in a container of Swift's own image, leased
# from OS Server through `oss machine run container --inside`, which holds
# a five-minute lease renewed while it runs and releases it however it
# ends: SIGTERM (the runner's cancel) releases it at once.
#
#   tools/ci/linux_tests.sh
#
#   SWIFT_SQL_CI_IMAGE  the image (default: Swift 6.2 on Ubuntu 24.04)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGE="${SWIFT_SQL_CI_IMAGE:-docker.io/library/swift:6.2-noble}"
OSS="/Applications/OS Server.app/Contents/Helpers/oss"
[ -x "$OSS" ] || OSS="$(command -v oss)"

steps='set -e
mkdir -p /tmp/swift_sql && tar -x -C /tmp/swift_sql && cd /tmp/swift_sql
swift --version
swift test'

# The tree from a file, not a pipe: exec then makes oss this process, so the
# runner's cancel reaches it, and it releases the container.
tree="${RUNNER_TEMP:-$(mktemp -d)}/swift_sql-tree.tar"
git -C "$ROOT" archive --format=tar -o "$tree" HEAD
exec "$OSS" machine run container --image="$IMAGE" --cpus=4 --memory=4 --inside --workdir=/ -- sh -c "$steps" < "$tree"
