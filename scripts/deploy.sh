#!/usr/bin/env bash
# Archives the app and uploads it to App Store Connect (TestFlight) with cloud-managed signing. Run by CI.
# Usage: scripts/deploy.sh Staging|Release
# Env: APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (contents of the .p8), BUILD_NUMBER
set -euo pipefail

configuration="${1:?usage: deploy.sh Staging|Release}"
case "$configuration" in
    Staging) scheme="FitMe-Staging" ;;
    Release) scheme="FitMe" ;;
    *) echo "Unknown configuration: $configuration" >&2; exit 1 ;;
esac
: "${APPLE_TEAM_ID:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_PRIVATE_KEY:?}" "${BUILD_NUMBER:?}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
key_path="$work/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_PRIVATE_KEY" > "$key_path"
# Fail with a readable message (never the key itself) if the secret isn't the whole .p8 file.
if [[ "$(head -1 "$key_path")" != "-----BEGIN PRIVATE KEY-----" ]] \
    || ! grep -q -- "-----END PRIVATE KEY-----" "$key_path"; then
    echo "error: ASC_PRIVATE_KEY is not a full .p8 file ($(wc -l < "$key_path" | tr -d ' ') lines; expected a" \
        "BEGIN/END PRIVATE KEY block). Re-set it with: gh secret set ASC_PRIVATE_KEY < AuthKey_<KEYID>.p8" >&2
    exit 1
fi
auth=(
    -allowProvisioningUpdates
    -authenticationKeyPath "$key_path"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)
archive="$work/FitMe.xcarchive"

xcodegen generate --quiet
xcodebuild -project FitMe.xcodeproj -scheme "$scheme" -configuration "$configuration" \
    -destination 'generic/platform=iOS' -archivePath "$archive" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    "${auth[@]}" archive | xcbeautify

if [[ "$configuration" == "Release" ]]; then
    scripts/verify-release.sh "$archive/Products/Applications/FitMe.app"
fi

cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>upload</string>
    <key>teamID</key><string>$APPLE_TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/ExportOptions.plist" \
    -exportPath "$work/export" "${auth[@]}" | xcbeautify
echo "Uploaded $configuration build $BUILD_NUMBER to App Store Connect."
