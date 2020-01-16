#!/bin/bash

CA_DIR=./root_ca
CA_CONFIG=./rootca.conf
PRIVATE_KEY_FILE=$CA_DIR/private/root_ca_key.pem
CERTIFICATE_FILE=$CA_DIR/certs/root_ca_cert.pem

# create directory structure required
mkdir -p \
    $CA_DIR/certs \
    $CA_DIR/crl \
    $CA_DIR/newcerts \
    $CA_DIR/private
    
# create files required
touch $CA_DIR/index.txt
echo 1000 > $CA_DIR/serial

# generate Root CA key
openssl genrsa -out $PRIVATE_KEY_FILE 4096
chmod 400 $PRIVATE_KEY_FILE

# create Root CA certificate
openssl req -config $CA_CONFIG \
            -key $PRIVATE_KEY_FILE \
            -new -x509 -days 3650 -extensions root_ca \
            -out $CERTIFICATE_FILE
            
chmod 444 $CERTIFICATE_FILE
