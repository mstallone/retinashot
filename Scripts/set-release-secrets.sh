#!/bin/bash
# One-time setup of the GitHub Actions secrets the Release workflow needs. Same names and material as
# mx-master-input and runway. Run it from a Mac that has the NextByte Developer ID .p12 export.
#   Scripts/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXX.p8> <issuer-id>
# You will be prompted for the .p12 password. Nothing is written to disk.
set -euo pipefail
P12="${1:?path to the Developer ID Application .p12}"
P8="${2:?path to the App Store Connect API key (.p8)}"
ISSUER="${3:?App Store Connect issuer ID}"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
KEY_ID="$(basename "$P8" | sed -E 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/')"
[[ "$KEY_ID" != "$(basename "$P8")" ]] || { echo "the .p8 must be named AuthKey_<KEY_ID>.p8" >&2; exit 1; }

read -r -s -p "Password for $(basename "$P12"): " P12_PASSWORD; echo
openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys -legacy 2>/dev/null | grep -q 'Developer ID Application' \
  || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys 2>/dev/null | grep -q 'Developer ID Application' \
  || { echo "could not open the .p12 with that password, or it is not a Developer ID Application certificate" >&2; exit 1; }

base64 -i "$P12" | gh secret set DEVELOPER_ID_CERTIFICATE_BASE64 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo "$REPO"
base64 -i "$P8" | gh secret set APPLE_NOTARY_PRIVATE_KEY_BASE64 --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set APPLE_NOTARY_KEY_ID --repo "$REPO"
printf '%s' "$ISSUER" | gh secret set APPLE_NOTARY_ISSUER_ID --repo "$REPO"
gh secret list --repo "$REPO"
