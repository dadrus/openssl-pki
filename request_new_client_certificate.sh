#!/bin/bash

ISSUING_CA_CONFIG=./issuingca.conf
ISSUING_CA_CHAIN_FILE=./issuing_ca/certs/ca_chain.pem

CLIENT_DIR=./client
CSR_CONFIG=./csr.conf
PRIVATE_KEY_FILE=$CLIENT_DIR/private/client2.key.pem
CSR_FILE=$CLIENT_DIR/csr/client2.csr.pem
CERTIFICATE_FILE=$CLIENT_DIR/certs/client2.cert.pem

# create directory structure required
mkdir -p \
    $CLIENT_DIR/certs \
    $CLIENT_DIR/private \
    $CLIENT_DIR/csr

# generate key
openssl genrsa -out $PRIVATE_KEY_FILE 2048
chmod 400 $PRIVATE_KEY_FILE

# create CSR to request the server certificate from the Issuing CA
openssl req -config $CSR_CONFIG \
            -new \
            -key $PRIVATE_KEY_FILE \
            -out $CSR_FILE
            
# sing the certificate by the Issuing CA
openssl ca -config $ISSUING_CA_CONFIG \
           -extensions user_cert \
           -days 365 -notext \
           -in $CSR_FILE \
           -out $CERTIFICATE_FILE 
            
chmod 444 $CERTIFICATE_FILE

# verify the issued certificate for test purposes
openssl verify -CAfile $ISSUING_CA_CHAIN_FILE $CERTIFICATE_FILE
