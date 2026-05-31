#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env.local; set +a

UDID="${1:-${EMBR_DEVICE_UDID:?set EMBR_DEVICE_UDID in .env.local or pass a UDID}}"

APP="$(scripts/ios-build.sh "platform=iOS,id=$UDID" | tail -1)"
if [ ! -d "$APP" ]; then
  echo "error: build did not yield an app bundle" >&2
  exit 1
fi

echo "==> Installing on $UDID"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "==> Relaunching ${EMBR_BUNDLE_ID}"
xcrun devicectl device process terminate --device "$UDID" --bundle-identifier "${EMBR_BUNDLE_ID}" 2>/dev/null || true
xcrun devicectl device process launch --device "$UDID" --terminate-existing "${EMBR_BUNDLE_ID}"
echo "==> Deployed."
