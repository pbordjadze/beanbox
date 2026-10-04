#!/usr/bin/env bash
# Runs a Swift toolchain command for the package inside the swift:6.2 Docker image.
#   tools/swift.sh build
#   tools/swift.sh test
# Runs as the calling user so .build/ isn't left owned by root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT:$ROOT" -w "$ROOT" swift:6.2-noble swift "$@"
