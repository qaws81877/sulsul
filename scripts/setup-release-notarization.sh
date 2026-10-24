#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNING_XCCONFIG="$REPO_ROOT/Signing.xcconfig"
SIGNING_LOCAL_XCCONFIG="$REPO_ROOT/Signing.local.xcconfig"
PROFILE_NAME="${VOICEINK_NOTARY_PROFILE:-Sulsul-Notarization}"
TEAM_ID="${VOICEINK_DEVELOPMENT_TEAM:-}"
# The git-ignored local file wins over the shared default, like the #include? in Signing.xcconfig.
for xcconfig in "$SIGNING_LOCAL_XCCONFIG" "$SIGNING_XCCONFIG"; do
    if [[ -z "$TEAM_ID" && -f "$xcconfig" ]]; then
        TEAM_ID="$(awk -F= '/^DEVELOPMENT_TEAM[[:space:]]*=/ { gsub(/[[:space:]]|\/\/.*/, "", $2); print $2; exit }' "$xcconfig")"
    fi
done

if [[ -z "$TEAM_ID" ]]; then
    printf 'error: Set DEVELOPMENT_TEAM in Signing.local.xcconfig before make release-setup\n' >&2
    exit 1
fi

printf 'Apple Developer Apple ID: '
read -r APPLE_ID || true

if [[ -z "$APPLE_ID" ]]; then
    printf 'error: Apple ID is required\n' >&2
    exit 1
fi

printf '\nnotarytool will securely prompt for your app-specific password.\n'
printf 'Team ID: %s\n' "$TEAM_ID"
xcrun notarytool store-credentials "$PROFILE_NAME" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --validate

printf '\nSaved and validated notarytool profile: %s\n' "$PROFILE_NAME"
