#!/usr/bin/env bash
set -euo pipefail

# Creates a self-signed code-signing certificate named "VoiceToText Local Signer"
# in the user's login keychain. Idempotent — exits early if already present.
#
# Why: ad-hoc signing (`-`) produces a new cdhash on every build, which invalidates
# TCC permission grants (microphone, accessibility). A stable self-signed cert gives
# a stable designated requirement so TCC grants persist across rebuilds.

CERT_NAME="VoiceToText Local Signer"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "✓ certificate already exists: $CERT_NAME"
    exit 0
fi

echo "→ creating self-signed code signing certificate"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/config.cnf" <<EOF
[req]
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ext

[req_dn]
CN = $CERT_NAME
O = VoiceToText

[v3_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -new -x509 -nodes -newkey rsa:2048 \
    -keyout "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -days 3650 \
    -config "$TMP/config.cnf" 2>&1 | tail -3

P12_PASS="temp"
openssl pkcs12 -export \
    -in "$TMP/cert.pem" \
    -inkey "$TMP/key.pem" \
    -out "$TMP/cert.p12" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASS" \
    -keypbe PBE-SHA1-3DES \
    -certpbe PBE-SHA1-3DES \
    -macalg SHA1 2>&1 | tail -3

security import "$TMP/cert.p12" \
    -k "$KEYCHAIN" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -P "$P12_PASS" 2>&1 | tail -3

echo "→ allowing codesign to use the key without prompting"
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" "$KEYCHAIN" 2>&1 | tail -3 || true

echo "✓ certificate created: $CERT_NAME"
