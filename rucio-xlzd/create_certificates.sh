#!/bin/bash

# A script to generate self-signed certificates for the Rucio Helm chart.
# This script should be run from the root of the Helm chart directory.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---

# The output directory for the certificates.
CERT_DIR="certificates"

# Certificate validity in days.
DAYS=3650

# Certificate Authority details.
CA_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=DevOps/CN=My Test CA"

# Server certificate details. The CN must match the rucio.server.host value from your values.yaml.
SERVER_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Server/CN=rucio-service"

# Client/user certificate details.
CLIENT_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Users/CN=rucio-test-user"


# --- Script Logic ---

# 1. Create the output directory
echo "--- Creating output directory: $CERT_DIR ---"
mkdir -p "$CERT_DIR"
echo

# 2. Generate Certificate Authority (CA)
echo "--- Generating Certificate Authority (CA) ---"
if [ -f "$CERT_DIR/ca.key.pem" ]; then
    echo "CA key already exists, skipping."
else
    openssl genpkey -algorithm RSA -out "$CERT_DIR/ca.key.pem"
    openssl req -x509 -new -nodes \
        -key "$CERT_DIR/ca.key.pem" \
        -sha256 -days "$DAYS" \
        -out "$CERT_DIR/ca.cert.pem" \
        -subj "$CA_SUBJ"
    echo "CA key and certificate created."
fi
echo

# 3. Generate Server Certificate
echo "--- Generating Server Certificate ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/hostkey.pem"
openssl req -new \
    -key "$CERT_DIR/hostkey.pem" \
    -out "$CERT_DIR/host.csr.pem" \
    -subj "$SERVER_SUBJ"

# Best Practice: Use a Subject Alternative Name (SAN) for DNS and IP addresses.
# This makes the certificate valid for multiple hostnames.
SAN_CONFIG="subjectAltName = DNS:$SERVER_SUBJ,DNS:rucio-service.default.svc.cluster.local"

openssl x509 -req -in "$CERT_DIR/host.csr.pem" \
    -CA "$CERT_DIR/ca.cert.pem" \
    -CAkey "$CERT_DIR/ca.key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/hostcert.pem" \
    -days "$DAYS" -sha256 \
    -extfile <(printf "%s\n" "$SAN_CONFIG")

echo "Server certificate and key created."
echo

# 4. Generate Client Certificate
echo "--- Generating Client/User Certificate ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/userkey.pem"
openssl req -new \
    -key "$CERT_DIR/userkey.pem" \
    -out "$CERT_DIR/user.csr.pem" \
    -subj "$CLIENT_SUBJ"

openssl x509 -req -in "$CERT_DIR/user.csr.pem" \
    -CA "$CERT_DIR/ca.cert.pem" \
    -CAkey "$CERT_DIR/ca.key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/usercert.pem" \
    -days "$DAYS" -sha256
echo "Client certificate and key created."
echo

# 5. Create CA Hash Link
echo "--- Creating CA hash link ---"
HASH=$(openssl x509 -noout -subject_hash -in "$CERT_DIR/ca.cert.pem")
# Use cp instead of ln for better Docker/build context compatibility
cp "$CERT_DIR/ca.cert.pem" "$CERT_DIR/$HASH.0"
echo "Hash link created: $HASH.0"
echo

# 6. Clean up temporary files
echo "--- Cleaning up intermediate files ---"
rm "$CERT_DIR"/*.csr.pem
rm "$CERT_DIR"/*.srl
echo

echo "✅ All certificates generated successfully in the '$CERT_DIR' directory."