#!/bin/zsh
# One-time setup for Developer ID signing + notarization of Babelpen releases.
#
# Two ways in:
#
#   A) You created the certificate on developer.apple.com from a CSR made with
#      `./scripts/setup-signing.sh --csr` and downloaded the .cer:
#        ./scripts/setup-signing.sh ~/Downloads/developerID_application.cer
#
#   B) You exported an existing Developer ID Application identity from
#      Keychain Access as a .p12 (only that certificate):
#        ./scripts/setup-signing.sh ~/Downloads/devid.p12
#
# You also need an app-specific password for your Apple ID
# (account.apple.com › Sign-In and Security › App-Specific Passwords).
#
# It checks the certificate, installs it in your login keychain (A), checks the
# notarization credentials with Apple (saved as the local notarytool profile
# "babelpen"), stores the six GitHub Actions secrets the release workflow uses,
# and starts a release build. Secrets are typed hidden and piped straight to gh.
set -euo pipefail
cd "$(dirname "$0")/.."

STORE="$HOME/.babelpen-signing"     # private key + generated .p12 password (mode 700)
REPO=${BABELPEN_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
pkcs12() { openssl pkcs12 "$@" -legacy 2>/dev/null || openssl pkcs12 "$@"; }

# --csr: make a private key + certificate signing request to upload to Apple.
if [[ ${1:-} == "--csr" ]]; then
  mkdir -p "$STORE" && chmod 700 "$STORE"
  [[ -f "$STORE/devid.key" ]] || { openssl genrsa -out "$STORE/devid.key" 2048 2>/dev/null; chmod 600 "$STORE/devid.key"; }
  openssl req -new -key "$STORE/devid.key" -out "$STORE/devid.csr" -subj "/CN=Babelpen Developer ID/C=US" 2>/dev/null
  echo "CSR: $STORE/devid.csr"
  echo "Upload it at https://developer.apple.com/account/resources/certificates/add (Developer ID Application, G2 Sub-CA),"
  echo "download the .cer and run: ./scripts/setup-signing.sh ~/Downloads/developerID_application.cer"
  exit 0
fi

INPUT=${1:-}
[[ -f "$INPUT" ]] || { sed -n '2,20p' "$0"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [[ "$INPUT" == *.cer || "$INPUT" == *.crt || "$INPUT" == *.pem ]]; then
  # A) certificate from Apple + our private key → .p12, installed in the keychain.
  [[ -f "$STORE/devid.key" ]] || { echo "✗ $STORE/devid.key not found. Was the CSR made with --csr?"; exit 1; }
  openssl x509 -inform DER -in "$INPUT" -out "$WORK/cert.pem" 2>/dev/null || cp "$INPUT" "$WORK/cert.pem"
  CERT_KEY=$(openssl x509 -in "$WORK/cert.pem" -noout -pubkey | openssl sha256)
  OUR_KEY=$(openssl pkey -in "$STORE/devid.key" -pubout | openssl sha256)
  [[ "$CERT_KEY" == "$OUR_KEY" ]] || { echo "✗ This certificate wasn't issued for the key in $STORE."; exit 1; }
  SUBJECT=$(openssl x509 -in "$WORK/cert.pem" -noout -subject)
  [[ "$SUBJECT" == *"Developer ID Application"* ]] || { echo "✗ Not a Developer ID Application certificate: $SUBJECT"; exit 1; }
  P12_PASSWORD=$(openssl rand -base64 24)
  P12="$STORE/devid.p12"
  pkcs12 -export -in "$WORK/cert.pem" -inkey "$STORE/devid.key" -out "$P12" -passout "pass:$P12_PASSWORD" \
    -name "$(echo "$SUBJECT" | sed -E 's/.*CN ?= ?([^,/]+\([A-Z0-9]+\)).*/\1/')"
  chmod 600 "$P12"
  security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
  echo "✓ Developer ID installed in your login keychain"
else
  # B) exported identity.
  P12="$INPUT"
  read -s "P12_PASSWORD?Password of $(basename "$P12") (hidden): "; echo
fi

# The .p12 must hold exactly one Developer ID Application certificate and its key.
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
echo "→ Rebuilding the latest release signed and notarized…"
gh workflow run release.yml -R "$REPO" --ref main
sleep 4
echo "✓ Started: $(gh run list -R "$REPO" --workflow release.yml --limit 1 --json url -q '.[0].url')"
echo "  When it's green, the release assets are Developer ID signed and notarized."
