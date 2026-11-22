#!/bin/zsh
# One-time setup for Developer ID signing + notarization of Babelpen releases.
#
# Before running:
#   1. Create a "Developer ID Application" certificate (Xcode › Settings ›
#      Accounts › your team › Manage Certificates › + › Developer ID Application).
#   2. Export it from Keychain Access (My Certificates › right-click it ›
#      Export…) as a .p12 with a password. Export only that certificate.
#   3. Create an app-specific password for your Apple ID (account.apple.com ›
#      Sign-In and Security › App-Specific Passwords).
#
#   ./scripts/setup-signing.sh [path/to/certificate.p12]
#
# It checks the .p12 holds exactly one Developer ID Application certificate,
# checks the notarization credentials with Apple (and saves them as the local
# notarytool profile "babelpen"), then stores the six GitHub Actions secrets
# the release workflow uses. Secrets are typed hidden and piped straight to gh.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=${BABELPEN_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
P12=${1:-$HOME/Downloads/devid.p12}
[[ -f "$P12" ]] || { echo "✗ $P12 not found. Pass the .p12 path as the first argument."; exit 1; }

read -s "P12_PASSWORD?Password of $(basename "$P12") (hidden): "; echo

# Inspect the .p12 (works with OpenSSL 3 and LibreSSL).
pkcs12() { openssl pkcs12 "$@" -legacy 2>/dev/null || openssl pkcs12 "$@"; }
CERTS=$(pkcs12 -in "$P12" -nokeys -passin "pass:$P12_PASSWORD" | openssl crl2pkcs7 -nocrl -certfile /dev/stdin \
  | openssl pkcs7 -print_certs -noout | grep '^subject' || true)
KEYS=$(pkcs12 -in "$P12" -nocerts -nodes -passin "pass:$P12_PASSWORD" | grep -c 'BEGIN .*PRIVATE KEY' || true)
COUNT=$(echo "$CERTS" | grep -c 'subject' || true)
if [[ "$COUNT" != 1 || "$KEYS" != 1 || "$CERTS" != *"Developer ID Application"* ]]; then
  echo "✗ The .p12 must contain exactly one 'Developer ID Application' certificate and its key."
  echo "  Found $COUNT certificate(s) and $KEYS key(s):"
  echo "$CERTS" | sed 's/^/    /'
  exit 1
fi
IDENTITY=$(echo "$CERTS" | sed -E 's/.*CN ?= ?([^,/]+\([A-Z0-9]+\)).*/\1/')
TEAM_ID=$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
echo "→ Certificate: $IDENTITY"
echo "→ Team ID:     $TEAM_ID"
echo "→ Repository:  $REPO"
echo

read "APPLE_ID?Apple ID email of the account that owns team $TEAM_ID: "
read -s "APP_PASSWORD?App-specific password (hidden): "; echo

echo "→ Checking the notarization credentials with Apple…"
xcrun notarytool store-credentials babelpen --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" >/dev/null
xcrun notarytool history --keychain-profile babelpen >/dev/null
echo "✓ Credentials work (also saved locally as notarytool profile 'babelpen')"

echo "→ Saving GitHub Actions secrets in $REPO…"
base64 -i "$P12" | gh secret set MACOS_CERTIFICATE_P12 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set MACOS_CERTIFICATE_PASSWORD -R "$REPO"
printf '%s' "$IDENTITY" | gh secret set MACOS_SIGN_ID -R "$REPO"
printf '%s' "$APPLE_ID" | gh secret set NOTARY_APPLE_ID -R "$REPO"
printf '%s' "$TEAM_ID" | gh secret set NOTARY_TEAM_ID -R "$REPO"
printf '%s' "$APP_PASSWORD" | gh secret set NOTARY_PASSWORD -R "$REPO"
unset P12_PASSWORD APP_PASSWORD
echo "✓ Secrets set:"
gh secret list -R "$REPO"
echo
echo "You can delete $P12 now (the certificate stays in your keychain)."
echo "Next release will be signed with Developer ID and notarized."
