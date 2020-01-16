#!/bin/bash

ISSUING_CA_CONFIG=./issuingca.conf
ISSUING_CA_CHAIN_FILE=./issuing_ca/certs/ca_chain.pem

SERVER_DIR=./server
CSR_CONFIG=./csr.conf
PRIVATE_KEY_FILE=$SERVER_DIR/private/example2.com.key.pem
CSR_FILE=$SERVER_DIR/csr/example2.com.csr.pem
CERTIFICATE_FILE=$SERVER_DIR/certs/example2.com.cert.pem

# create directory structure required
mkdir -p \
    $SERVER_DIR/certs \
    $SERVER_DIR/private \
    $SERVER_DIR/csr

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
           -extensions server_cert \
           -days 365 -notext \
           -in $CSR_FILE \
           -out $CERTIFICATE_FILE 
            
chmod 444 $CERTIFICATE_FILE

# verify the issued certificate for test purposes
openssl verify -CAfile $ISSUING_CA_CHAIN_FILE $CERTIFICATE_FILE
