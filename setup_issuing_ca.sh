#!/bin/bash

ROOT_CA_CONFIG=./rootca.conf
ROOT_CA_CERTIFICATE=./root_ca/certs/root_ca_cert.pem

CA_DIR=./issuing_ca
CSR_CONFIG=./csr.conf
ISSUING_CA_CONF=./issuingca.conf
CA_PRIVATE_KEY_FILE=$CA_DIR/private/issuing_ca_key.pem
CA_CSR_FILE=$CA_DIR/csr/issuing_ca_csr.pem
CA_CERTIFICATE_FILE=$CA_DIR/certs/issuing_ca_cert.pem
OCSP_PRIVATE_KEY_FILE=$CA_DIR/private/issuing_ca_ocsp_key.pem
OCSP_CSR_FILE=$CA_DIR/csr/issuing_ca_ocsp_csr.pem
OCSP_CERTIFICATE_FILE=$CA_DIR/certs/issuing_ca_ocsp_cert.pem
CERTIFICATE_CHAIN_FILE=$CA_DIR/certs/ca_chain.pem


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

echo "Generating private key for the CA"
openssl genrsa -out $CA_PRIVATE_KEY_FILE 4096
chmod 400 $CA_PRIVATE_KEY_FILE

echo "Creating CSR to request the CA certificate from the Root CA"
openssl req -config $CSR_CONFIG \
            -new \
            -key $CA_PRIVATE_KEY_FILE \
            -out $CA_CSR_FILE
            
echo "Sing the CA certificate by the Root CA"
openssl ca -config $ROOT_CA_CONFIG \
           -extensions issuing_ca \
           -days 1825 -notext \
           -in $CA_CSR_FILE \
           -out $CA_CERTIFICATE_FILE

openssl x509 -in $CA_CERTIFICATE_FILE -out "${CA_CERTIFICATE_FILE/.pem/.der}" -outform der
            
chmod 444 $CA_CERTIFICATE_FILE

# verify the issued certificate for test purposes
openssl verify -CAfile $ROOT_CA_CERTIFICATE $CA_CERTIFICATE_FILE

# create a certificate chain file
cat $CA_CERTIFICATE_FILE $ROOT_CA_CERTIFICATE > $CERTIFICATE_CHAIN_FILE
chmod 444 $CERTIFICATE_CHAIN_FILE

echo "Generating private key for the OCSP responder"
openssl genrsa -out $OCSP_PRIVATE_KEY_FILE 2048
chmod 400 $OCSP_PRIVATE_KEY_FILE

echo "Creating CSR to request the OCSP responder certificate from the Issuing CA"
openssl req -config $CSR_CONFIG \
            -new \
            -key $OCSP_PRIVATE_KEY_FILE \
            -out $OCSP_CSR_FILE

echo "Sing the OCSP certificate by the Issuing CA"
openssl ca -config $ISSUING_CA_CONF \
           -extensions ocsp \
           -days 365 -notext \
           -in $OCSP_CSR_FILE \
           -out $OCSP_CERTIFICATE_FILE 

chmod 444 $OCSP_CERTIFICATE_FILE

