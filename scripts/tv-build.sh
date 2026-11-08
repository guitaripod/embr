#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f App/Secrets.swift ]; then
  echo "error: App/Secrets.swift missing. Run scripts/setup.sh." >&2
  exit 1
fi
export EMBR_BUNDLE_ID=com.guitaripod.embr EMBR_TEAM_ID=P4DQK6SRKR

TARGET="${1:-simulator}"
case "$TARGET" in
  simulator) DESTINATION='generic/platform=tvOS Simulator'; EXTRA=(CODE_SIGNING_ALLOWED=NO) ;;
  device) DESTINATION="platform=tvOS,id=${EMBR_TV_UDID:?set EMBR_TV_UDID to the Apple TV UDID}"; EXTRA=() ;;
  *) echo "usage: scripts/tv-build.sh [simulator|device]" >&2; exit 2 ;;
esac

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild EmbrTV ($DESTINATION)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
if ! xcodebuild -project Embr.xcodeproj -scheme EmbrTV -destination "$DESTINATION" -configuration Debug build "${EXTRA[@]}" 2>&1 | tee "$LOG" >/dev/null; then
  echo "==> BUILD FAILED" >&2
  grep -E "error:|actor-isolated|Sendable" "$LOG" >&2 || true
  exit 1
fi
grep -E "warning: .*/(TV|Shared)/" "$LOG" | sort -u || true
echo "==> BUILD SUCCEEDED"
