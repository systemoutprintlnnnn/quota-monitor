#!/usr/bin/env bash
# ============================================================================
#  STATUS: SCAFFOLD-ONLY — not used by the current 0.1.x release flow.
#
#  QuotaMonitor ships ad-hoc-signed today (no Apple Developer account). The
#  active release pipeline is `tools/release.sh` (build → ad-hoc sign → DMG).
#  This script is intentionally kept in-tree so that the day we DO acquire a
#  Developer ID Application certificate, we don't have to rediscover the
#  notarytool incantation from scratch.
#
#  Do NOT wire this into release.sh until the cert is available; running it
#  without `IDENTITY` set will (correctly) refuse and exit 1.
# ============================================================================
#
# Notarize and staple QuotaMonitor.app for Gatekeeper-friendly distribution.
#
# Pre-reqs (when reactivating):
#   1. Apple Developer account with a Developer ID Application certificate
#      installed in your login keychain.
#   2. An app-specific password stored in keychain via:
#        xcrun notarytool store-credentials quotamonitor-notary \
#          --apple-id you@example.com \
#          --team-id ABCDE12345 \
#          --password app-specific-password
#   3. ./build.sh release  (must be a release build — debug binaries are
#      stripped of dSYMs and may fail notarization for unrelated reasons)
#
# Usage:
#   IDENTITY="Developer ID Application: Your Name (TEAMID)" ./tools/notarize.sh
#
# Optional env vars:
#   IDENTITY        codesign identity (default: $DEVELOPER_ID_APPLICATION)
#   PROFILE         keychain profile name (default: quotamonitor-notary)
#   APP_BUNDLE      path to .app (default: .build/QuotaMonitor.app)

set -euo pipefail
cd "$(dirname "$0")/.."

APP_BUNDLE="${APP_BUNDLE:-.build/QuotaMonitor.app}"
PROFILE="${PROFILE:-quotamonitor-notary}"
IDENTITY="${IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
ENTITLEMENTS="Resources/QuotaMonitor.entitlements"

if [[ -z "${IDENTITY}" ]]; then
    echo "error: set IDENTITY=\"Developer ID Application: ... (TEAMID)\"" >&2
    echo "       (or export DEVELOPER_ID_APPLICATION)" >&2
    exit 1
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "error: ${APP_BUNDLE} missing — run ./build.sh release first" >&2
    exit 1
fi

echo "==> Re-signing ${APP_BUNDLE} with hardened runtime"
# --options runtime enables hardened runtime; --timestamp asks Apple's TSA
# (notarization rejects ad-hoc timestamps).
codesign --force --deep --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${IDENTITY}" \
    "${APP_BUNDLE}"

echo "==> Verifying signature"
codesign --verify --strict --deep --verbose=2 "${APP_BUNDLE}"

# Notarization requires a flat container. Use ditto so the .zip preserves
# extended attributes (xattrs); the `zip` CLI does not.
ZIP_PATH="${APP_BUNDLE%.app}-notarize.zip"
echo "==> Packaging ${ZIP_PATH}"
rm -f "${ZIP_PATH}"
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

echo "==> Submitting to Apple notary service (this can take 1-5 min)"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${PROFILE}" \
    --wait

echo "==> Stapling notarization ticket onto ${APP_BUNDLE}"
xcrun stapler staple "${APP_BUNDLE}"

echo "==> Verifying Gatekeeper acceptance"
spctl --assess --type execute --verbose=2 "${APP_BUNDLE}" || {
    echo "warning: spctl rejected the bundle — check the ticket manually" >&2
    exit 1
}

rm -f "${ZIP_PATH}"
echo "==> Done. ${APP_BUNDLE} is notarized + stapled."
echo "    Ship via: ./tools/make-dmg.sh"
