#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building EmbrCore"
swift build

echo "==> Testing EmbrCore"
swift test "$@"

echo "==> EmbrCore OK"
