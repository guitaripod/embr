#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Embr setup"

if [ ! -f .env.local ]; then
  echo "==> Creating .env.local (edit it with your values)"
  TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '\(([A-Z0-9]{10})\)' | head -1 | tr -d '()' || true)"
  cat > .env.local <<EOF
EMBR_BUNDLE_ID=com.guitaripod.embr
EMBR_TEAM_ID=${TEAM_ID:-YOUR_TEAM_ID}
EMBR_DEVICE_NAME=iPhone
EMBR_DEVICE_UDID=
EOF
fi

if [ ! -f Embr/Secrets.swift ]; then
  echo "==> Creating Embr/Secrets.swift from example"
  cp Embr/Secrets.example.swift Embr/Secrets.swift
  echo "    Edit Embr/Secrets.swift: twitchClientID + workerBaseURL"
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen generate"
  xcodegen generate
else
  echo "    (xcodegen not found — install with: brew install xcodegen)"
fi

echo "==> EmbrCore sanity build"
swift build >/dev/null && echo "    EmbrCore builds."

echo "==> Done. Next: edit .env.local + Embr/Secrets.swift, then scripts/ios-deploy.sh"
