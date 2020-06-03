#!/bin/bash

# Generate a self-signed certificate: certificate-file and private-key-file
# Creates the certificate using Java keytool and openssl - must be in the PATH

KEYPAIR_ALIAS="alcide"
KEYSTORE="keystore"
KEYSTORE_PASSWORD="changeit"
CERTIFICATE_FILE="alcide.crt"
PRIVATE_KEY_FILE="alcide.key"
PRIVATE_KEY_PASSWORD="abcdef"
KEYSIZE=2048
KEY_VALIDITY_DAYS=3650

FIRST_LAST_NAME="Unknown"
ORGANIZATION="Alcide"
ORGANIZATIONAL_UNIT="Unkown"
COUNTRY_CODE="IL"
STATE_OR_PROVINCE="Unknown"
CITY_OR_LOCALITY="Unknown"

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

DNAME="CN=${FIRST_LAST_NAME},OU=${ORGANIZATIONAL_UNIT},O=${ORGANIZATION},L=${CITY_OR_LOCALITY},ST=${STATE_OR_PROVINCE},C=${COUNTRY_CODE}"

# Create key pair in keystore:
keytool -genkeypair \
  -alias ${KEYPAIR_ALIAS} \
  -keyalg RSA \
  -keysize ${KEYSIZE} \
  -validity ${KEY_VALIDITY_DAYS} \
  -storetype PKCS12 \
  -keystore ${KEYSTORE} \
  -storepass ${KEYSTORE_PASSWORD} \
  -dname ${DNAME} \
  -ext SAN=${SAN}
#Export KAudit certificate from keystore:
keytool -exportcert \
  -alias ${KEYPAIR_ALIAS} \
  -keystore ${KEYSTORE} \
  -storepass ${KEYSTORE_PASSWORD} \
  -rfc \
  -file ${CERTIFICATE_FILE}
#Export KAudit private-key from keystore:
openssl pkcs12 \
  -in ${KEYSTORE} \
  -nodes \
  -nocerts \
  -out ${PRIVATE_KEY_FILE} \
  -password pass:${KEYSTORE_PASSWORD} \
  -passout pass:${PRIVATE_KEY_PASSWORD}

