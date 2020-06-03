#!/bin/bash

CERTS_DIR="certs"
CSR_DIR="csr"
PRIVATE_DIR="private"

CA_CERTIFICATE_FILE="${CERTS_DIR}/ca.crt.pem"
CA_CERTIFICATE_PWD="change1"
CA_PRIVATE_KEY_FILE="${PRIVATE_DIR}/ca.key.pem"
CA_PRIVATE_KEY_PWD="change2"

SERVER_CERTIFICATE_FILE="${CERTS_DIR}/server.crt.pem"
SERVER_PRIVATE_KEY_FILE="${PRIVATE_DIR}/server.key.pem"
SERVER_PRIVATE_KEY_PWD="change4"
SERVER_CERTIFICATE_REQUEST="${CSR_DIR}/server.csr.pem"

CLIENT_CERTIFICATE_FILE="${CERTS_DIR}/client.crt.pem"
CLIENT_PRIVATE_KEY_FILE="${PRIVATE_DIR}/client.key.pem"
CLIENT_PRIVATE_KEY_PWD="change6"
CLIENT_CERTIFICATE_REQUEST="${CSR_DIR}/client.csr.pem"

OPENSSL_CONF="openssl.cnf"
KEYSIZE=4096
KEY_VALIDITY_DAYS=365

FIRST_LAST_NAME="Unknown"
ORGANIZATION="Alcide"
ORGANIZATIONAL_UNIT="Unkown"
COUNTRY_CODE="IL"
STATE_OR_PROVINCE="Unknown"
CITY_OR_LOCALITY="Unknown"

#"/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=Acme Root CA"
DNAME="CN=${FIRST_LAST_NAME}/OU=${ORGANIZATIONAL_UNIT}/O=${ORGANIZATION}/L=${CITY_OR_LOCALITY}/ST=${STATE_OR_PROVINCE}/C=${COUNTRY_CODE}"

CERTIFICATE_DOMAINS=("localhost" "kaudit.alcide-kaudit.svc")
CERTIFICATE_IPS=("127.0.0.1" "192.168.99.100" "192.168.99.101" "192.168.99.102")

SAN=""
NUM_DOMAINS=${#CERTIFICATE_DOMAINS[*]}
NUM_IPS=${#CERTIFICATE_IPS[*]}
for ((i=0; i<NUM_DOMAINS; i++)); do
    SAN=${SAN}"dns:${CERTIFICATE_DOMAINS[i]}"
    if (( (i+1) < (NUM_DOMAINS+NUM_IPS) )); then
      SAN=${SAN}","
    fi
done
for ((i=0; i<NUM_IPS; i++)); do
    SAN=${SAN}"ip:${CERTIFICATE_IPS[i]}"
    if (( (i+1) < NUM_IPS )); then
      SAN=${SAN}","
    fi
done


# Prepare directories
mkdir -p ${CERTS_DIR} ${CSR_DIR} ${PRIVATE_DIR}
touch index.txt
echo "1000" > serial

# Create openssl configuration: out of band

# CA private key file, used to sign the certificates: ca.key.pem
openssl genrsa \
  -aes256 \
  -passout pass:${CA_PRIVATE_KEY_PWD} \
  -out ${CA_PRIVATE_KEY_FILE} \
  ${KEYSIZE}

#  CA certificate: ca.crt.pem
#openssl req -new -x509 -days 365 -key ca.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=Acme Root CA" -out ca.crt
#  -addext 'subjectAltName=DNS:example.com,DNS:example.net'
#  -subj ${DNAME} \
openssl req \
  -config ${OPENSSL_CONF} \
  -key ${CA_PRIVATE_KEY_FILE} \
  -passin pass:${CA_PRIVATE_KEY_PWD} \
  -new \
  -x509 \
  -days ${KEY_VALIDITY_DAYS} \
  -sha256 \
  -extensions v3_ca \
  -passout pass:${CA_CERTIFICATE_PWD} \
  -out ${CA_CERTIFICATE_FILE}


# for the server component
# private key: server.key.pem
openssl genrsa \
  -aes256 \
  -passout pass:${SERVER_PRIVATE_KEY_PWD} \
  -out ${SERVER_PRIVATE_KEY_FILE} \
  ${KEYSIZE}

# generate a certificate request: server.csr.pem
#openssl req -newkey rsa:2048 -nodes -keyout server.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=*.example.com" -out server.csr
#  -addext "'subjectAltName=${SAN}'" \
#  -subj ${DNAME} \
openssl req \
  -config ${OPENSSL_CONF} \
  -key ${SERVER_PRIVATE_KEY_FILE} \
  -passin pass:${SERVER_PRIVATE_KEY_PWD} \
  -new \
  -sha256 \
  -out ${SERVER_CERTIFICATE_REQUEST}

# sign CSR with our CA: server.crt.pem
# Fill out Common Name as hostname or fqdn
openssl ca \
  -config ${OPENSSL_CONF} \
  -outdir ${CERTS_DIR} \
  -cert ${CA_CERTIFICATE_FILE} \
  -keyfile ${CA_PRIVATE_KEY_FILE} \
  -passin pass:${CA_PRIVATE_KEY_PWD} \
  -extensions server_cert \
  -days ${KEY_VALIDITY_DAYS} \
  -notext \
  -md sha256 \
  -in ${SERVER_CERTIFICATE_REQUEST} \
  -out ${SERVER_CERTIFICATE_FILE}

# for the client component
# private key: client.key.pem
openssl genrsa \
  -aes256 \
  -passout pass:${CLIENT_PRIVATE_KEY_PWD} \
  -out ${CLIENT_PRIVATE_KEY_FILE} \
  ${KEYSIZE}

# generate certification request: client.csr.pem
#  -addext "'subjectAltName=${SAN}'" \
#  -subj ${DNAME} \
openssl req \
  -config ${OPENSSL_CONF} \
  -key ${CLIENT_PRIVATE_KEY_FILE} \
  -passin pass:${CLIENT_PRIVATE_KEY_PWD} \
  -new \
  -sha256 \
  -out ${CLIENT_CERTIFICATE_REQUEST}

# sign the Client CSR with CA: client.crt.pem
# fill out Common Name as hostname or fqdn
openssl ca \
  -config ${OPENSSL_CONF} \
  -outdir ${CERTS_DIR}  \
  -cert ${CA_CERTIFICATE_FILE} \
  -keyfile ${CA_PRIVATE_KEY_FILE} \
  -passin pass:${CA_PRIVATE_KEY_PWD} \
  -extensions client_cert \
  -days ${KEY_VALIDITY_DAYS} \
  -notext \
  -md sha256 \
  -in ${CLIENT_CERTIFICATE_REQUEST} \
  -out ${CLIENT_CERTIFICATE_FILE}


# test
#openssl s_server -accept 7569 \
#  -CAfile certs/ca.crt.pem \
#  -cert certs/server.crt.pem \
#  -key private/server.key.pem \
#  -Verify 10 -tls1_2 -state -quiet
# verify depth is 10, must return a certificate
# Enter pass phrase for private/server.key.pem:

#openssl s_client -connect localhost:7569 \
#  -CAfile certs/ca.crt.pem \
#  -cert certs/client.crt.pem \
#  -key private/client.key.pem \
#  -tls1_2 -state -quiet
# Enter pass phrase for private/client.key.pem: