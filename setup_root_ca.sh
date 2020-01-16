#!/bin/bash

CA_DIR=./root_ca
CA_CONFIG=./rootca.conf
CSR_CONFIG=./csr.conf
CA_PRIVATE_KEY_FILE=$CA_DIR/private/root_ca_key.pem
CA_CERTIFICATE_FILE=$CA_DIR/certs/root_ca_cert.pem
OCSP_PRIVATE_KEY_FILE=$CA_DIR/private/root_ca_ocsp_key.pem
OCSP_CSR_FILE=$CA_DIR/csr/root_ca_ocsp_csr.pem
OCSP_CERTIFICATE_FILE=$CA_DIR/certs/root_ca_ocsp_cert.pem

# create directory structure required
mkdir -p \
    $CA_DIR/certs \
    $CA_DIR/crl \
    $CA_DIR/newcerts \
    $CA_DIR/private \
    $CA_DIR/csr
    
# create files required
touch $CA_DIR/index.txt
echo 1000 > $CA_DIR/serial
echo 1000 > $CA_DIR/crlnumber

# generate Root CA key
openssl genrsa -out $CA_PRIVATE_KEY_FILE 4096
chmod 400 $CA_PRIVATE_KEY_FILE

# create Root CA certificate
openssl req -config $CA_CONFIG \
            -key $CA_PRIVATE_KEY_FILE \
            -new -x509 -days 3650 -extensions root_ca \
            -out $CA_CERTIFICATE_FILE
            
chmod 444 $CA_CERTIFICATE_FILE

openssl x509 -in $CA_CERTIFICATE_FILE -out "${CA_CERTIFICATE_FILE/.pem/.der}" -outform der

echo "Generating private key for the OCSP responder"
openssl genrsa -out $OCSP_PRIVATE_KEY_FILE 2048
chmod 400 $OCSP_PRIVATE_KEY_FILE

echo "Creating CSR to request the OCSP responder certificate from the Root CA"
openssl req -config $CSR_CONFIG \
            -new \
            -key $OCSP_PRIVATE_KEY_FILE \
            -out $OCSP_CSR_FILE

echo "Sing the OCSP certificate by the Root CA"
openssl ca -config $CA_CONFIG \
           -extensions ocsp \
           -days 365 -notext \
           -in $OCSP_CSR_FILE \
           -out $OCSP_CERTIFICATE_FILE 

chmod 444 $OCSP_CERTIFICATE_FILE
