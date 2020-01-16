#!/bin/bash

openssl ca -config issuingca.conf \
           -gencrl \
           -out issuing_ca/crl/crl.pem

openssl crl -in issuing_ca/crl/crl.pem \
            -out issuing_ca/crl/crl.der \
            -outform der

# create a combined CRL file containing the Root CA CRL and Issuing CA CRL

if [ -s root_ca/crl/crl.pem ]; then
  cat root_ca/crl/crl.pem > issuing_ca/crl/combined_crl.pem
  cat issuing_ca/crl/crl.pem >> issuing_ca/crl/combined_crl.pem
fi
