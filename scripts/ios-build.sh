#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env.local ]; then
  echo "error: .env.local missing. Run scripts/setup.sh first." >&2
  exit 1
fi
set -a; . ./.env.local; set +a

DESTINATION="${1:-platform=iOS,name=${EMBR_DEVICE_NAME:-iPhone}}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not installed (brew install xcodegen)." >&2
  exit 1
fi
if [ ! -f Embr/Secrets.swift ]; then
  echo "error: Embr/Secrets.swift missing. Run scripts/setup.sh." >&2
  exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild ($DESTINATION)"
LOG="$(mktemp)"
set -o pipefail
if ! xcodebuild \
    -project Embr.xcodeproj \
    -scheme Embr \
    -destination "$DESTINATION" \
    -configuration Debug \
    build 2>&1 | tee "$LOG"; then
  echo "==> BUILD FAILED — extracting errors:" >&2
  grep -E "error:|actor-isolated|nonisolated|Sendable|FAILED|Cannot find" "$LOG" >&2 || true
  exit 1
fi

APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'Embr.app' -path '*Debug-iphoneos*' -print 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  APP="$(find ~/Library/Developer/Xcode/DerivedData -name 'Embr.app' -print 2>/dev/null | head -1)"
fi
if [ -z "$APP" ]; then
  echo "error: built Embr.app not found in DerivedData" >&2
  exit 1
fi

BIN="$APP/Embr"
if [ ! -f "$BIN" ]; then
  echo "error: binary missing inside $APP" >&2
  exit 1
fi

NEWER="$(find Embr -name '*.swift' -newer "$BIN" 2>/dev/null || true)"
if [ -n "$NEWER" ]; then
  echo "error: source files are newer than the built binary — build was a no-op:" >&2
  echo "$NEWER" >&2
  exit 1
fi

echo "==> Build OK: $APP ($(stat -f '%z bytes · %Sm' "$BIN" 2>/dev/null || stat -c '%s bytes · %y' "$BIN"))"
echo "$APP"
