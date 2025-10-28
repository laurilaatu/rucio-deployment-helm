#!/bin/bash

# A script to generate self-signed certificates for the Rucio Helm chart,
# including the CA for the external IAM server.
# This script should be run from the root of the Helm chart directory.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---

# The output directory for the certificates.
CERT_DIR="certificates"

# Certificate validity in days.
DAYS=3650

# Certificate Authority details for your self-signed CA.
CA_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=DevOps/CN=My Test CA"

# --- Corrected Server Hostname Configuration ---
# Define the hostname in a variable for clarity and reuse.
SERVER_HOSTNAME="rucio-service"
# The CN must match the Kubernetes Service name.
SERVER_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Server/CN=${SERVER_HOSTNAME}"

# Client/user certificate details.
CLIENT_SUBJ="/C=GB/ST=London/L=London/O=MyOrg/OU=Users/CN=rucio-test-user"

# --- COMMENTS RESTORED ---
# rucio values would then use:
# openssl x509 -in ./certificates/usercert.pem -noout -subject -nameopt RFC2253
# subject=CN=rucio-test-user,OU=Users,O=MyOrg,L=London,ST=London,C=GB
# resulting in root_identity_dn: "CN=rucio-test-user,OU=Users,O=MyOrg,L=London,ST=London,C=GB"
# --- END COMMENTS RESTORED ---

# External IAM Server hostname
IAM_HOSTNAME="xlzd-iam.boulby.ac.uk"

# --- Script Logic ---

# 1. Create the output directory
echo "--- Creating output directory: $CERT_DIR ---"
mkdir -p "$CERT_DIR"
echo

# 2. Generate Certificate Authority (CA)
echo "--- Generating Self-Signed Certificate Authority (CA) ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/ca.key.pem"
# Generate the self-signed CA certificate FIRST
openssl req -x509 -new -nodes \
    -key "$CERT_DIR/ca.key.pem" \
    -sha256 -days "$DAYS" \
    -out "$CERT_DIR/ca.pem" \
    -subj "$CA_SUBJ"
echo "Self-signed CA key and certificate created."
echo

# --- NEW SECTION: 2b. Add External IAM CA ---
echo "--- Downloading and adding External IAM CA certificate(s) ---"
echo "Downloading certificate chain from ${IAM_HOSTNAME}..."
# Use openssl s_client to get the full chain and append it to ca.pem
# The awk command extracts only the PEM blocks
openssl s_client -connect "${IAM_HOSTNAME}:443" -showcerts </dev/null 2>/dev/null | \
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/ {print $0}' >> "$CERT_DIR/ca.pem"
echo "External IAM CA certificate(s) appended to ca.pem."
echo

# Create ca.cert.pem as a copy for compatibility
cp "$CERT_DIR/ca.pem" "$CERT_DIR/ca.cert.pem"
echo "Combined CA bundle created."
echo

# 3. Generate Server Certificate
echo "--- Generating Server Certificate for ${SERVER_HOSTNAME} ---"
openssl genpkey -algorithm RSA -out "$CERT_DIR/hostkey.pem"
openssl req -new \
    -key "$CERT_DIR/hostkey.pem" \
    -out "$CERT_DIR/host.csr.pem" \
    -subj "$SERVER_SUBJ"

# Create a temporary config file for the Subject Alternative Name (SAN) extension.
cat > "$CERT_DIR/v3.ext" <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${SERVER_HOSTNAME}
EOF

# Sign the server certificate using the COMBINED ca.pem
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

# Sign the client certificate using the COMBINED ca.pem
openssl x509 -req -in "$CERT_DIR/user.csr.pem" \
    -CA "$CERT_DIR/ca.pem" \
    -CAkey "$CERT_DIR/ca.key.pem" \
    -CAcreateserial \
    -out "$CERT_DIR/usercert.pem" \
    -days "$DAYS" -sha256
echo "Client certificate and key created."
echo

# 5. Create CA Hash Link
echo "--- Creating CA hash link (using combined CA bundle) ---"
# Calculate hash based on the first certificate in the combined bundle (your self-signed one)
HASH=$(openssl x509 -noout -subject_hash -in "$CERT_DIR/ca.pem")
# Create the hash link using the full combined bundle
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
echo "   The file '$CERT_DIR/ca.pem' now contains both your self-signed CA and the external IAM CA chain."