#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../Core/EmbrCore"

echo "==> Building EmbrCore"
swift build

echo "==> Testing EmbrCore"
swift test "$@"

echo "==> EmbrCore OK"
