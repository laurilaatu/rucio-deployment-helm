#!/bin/bash

# Also create grid certificates for Rucio:
# kubectl create secret generic rucio-grid-secret --from-file=/etc/grid-security/certificates

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

# --- Corrected Server Hostname Configuration ---
# Define the hostname in a variable for clarity and reuse.
SERVER_HOSTNAME="rucio-service"
# The CN must match the Kubernetes Service name.
SERVER_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Server/CN=${SERVER_HOSTNAME}"

# Client/user certificate details.
CLIENT_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Users/CN=rucio-test-user"


# --- Script Logic ---

# 1. Create the output directory
echo "--- Creating output directory: $CERT_DIR ---"
mkdir -p "$CERT_DIR"
echo

# 2. Generate Certificate Authority (CA)
echo "--- Generating Certificate Authority (CA) ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/ca.key.pem"
openssl req -x509 -new -nodes \
    -key "$CERT_DIR/ca.key.pem" \
    -sha256 -days "$DAYS" \
    -out "$CERT_DIR/ca.pem" \
    -subj "$CA_SUBJ"
# Create ca.cert.pem as a copy for compatibility
cp "$CERT_DIR/ca.pem" "$CERT_DIR/ca.cert.pem"
echo "CA key and certificate created."
echo

# 3. Generate Server Certificate
echo "--- Generating Server Certificate for ${SERVER_HOSTNAME} ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/hostkey.pem"
openssl req -new \
    -key "$CERT_DIR/hostkey.pem" \
    -out "$CERT_DIR/host.csr.pem" \
    -subj "$SERVER_SUBJ"

# Create a temporary config file for the Subject Alternative Name (SAN) extension.
# This ensures the certificate is valid for the hostname 'rucio-service'.
cat > "$CERT_DIR/v3.ext" <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${SERVER_HOSTNAME}
EOF

# Sign the server certificate, applying the SAN extension from the temp file.
openssl x509 -req -in "$CERT_DIR/host.csr.pem" \
    -CA "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca.key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/hostcert.pem" \
    -days "$DAYS" -sha256 \
    -extfile "$CERT_DIR/v3.ext"

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
    -CA "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca.key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/usercert.pem" \
    -days "$DAYS" -sha256
echo "Client certificate and key created."
echo

# 5. Create CA Hash Link
echo "--- Creating CA hash link ---"
HASH=$(openssl x509 -noout -subject_hash -in "$CERT_DIR/ca.pem")
cp "$CERT_DIR/ca.pem" "$CERT_DIR/$HASH.0"
echo "Hash link created: $HASH.0"
echo

# 6. Clean up temporary files
echo "--- Cleaning up intermediate files ---"
rm "$CERT_DIR"/*.csr.pem
rm "$CERT_DIR"/*.srl
rm "$CERT_DIR/v3.ext"
echo

echo "✅ All certificates regenerated successfully in the '$CERT_DIR' directory."