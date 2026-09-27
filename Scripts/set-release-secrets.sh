#!/bin/bash
# One-time setup of the GitHub Actions secrets the Release workflow needs.
#   Scripts/set-release-secrets.sh <issuer-id> [AuthKey_XXXX.p8] [DeveloperID.p12]
# With no .p12, the Developer ID identity is exported straight from your login keychain (macOS asks
# once to allow access to the key) with a random password; nothing is left on disk afterwards.
# Set DEVELOPER_ID_NAME to a longer prefix if more than one Developer ID identity is installed.
# The Sparkle key is exported from the login keychain, where generate_keys stored it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUER="${1:?App Store Connect issuer ID}"
P8="${2:-$(ls "$HOME"/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1)}"
P12="${3:-}"
IDENTITY_PREFIX="${DEVELOPER_ID_NAME:-Developer ID Application:}"
REPO="$(git -C "$ROOT" remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"

[[ -f "$P8" ]] || { echo "App Store Connect API key not found; pass its path as the second argument" >&2; exit 1; }
KEY_ID="$(basename "$P8" | sed -E 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/')"
[[ "$KEY_ID" != "$(basename "$P8")" ]] || { echo "the .p8 must be named AuthKey_<KEY_ID>.p8" >&2; exit 1; }

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
if [[ -n "$P12" ]]; then
  read -r -s -p "Password for $(basename "$P12"): " P12_PASSWORD; echo
else
  P12="$TEMP/developer-id.p12"
  P12_PASSWORD="$(openssl rand -base64 24)"
  swiftc -O "$ROOT/Tools/export-identity.swift" -o "$TEMP/export-identity"
  "$TEMP/export-identity" "$IDENTITY_PREFIX" "$P12" "$P12_PASSWORD"
fi
openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys -legacy 2>/dev/null | grep -q 'Developer ID Application' \
  || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys 2>/dev/null | grep -q 'Developer ID Application' \
  || { echo "the .p12 could not be opened or is not a Developer ID Application certificate" >&2; exit 1; }

base64 -i "$P12" | gh secret set DEVELOPER_ID_CERTIFICATE_BASE64 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo "$REPO"
base64 -i "$P8" | gh secret set APPLE_NOTARY_PRIVATE_KEY_BASE64 --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set APPLE_NOTARY_KEY_ID --repo "$REPO"
printf '%s' "$ISSUER" | gh secret set APPLE_NOTARY_ISSUER_ID --repo "$REPO"
"$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_keys" --account cc.stallone.retinashot -x "$TEMP/sparkle.key"
gh secret set SPARKLE_ED_PRIVATE_KEY --repo "$REPO" <"$TEMP/sparkle.key"
gh secret list --repo "$REPO"
