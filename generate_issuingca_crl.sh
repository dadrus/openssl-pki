#!/bin/bash

openssl ca -config issuingca.conf \
           -gencrl \
           -out issuing_ca/crl/crl.pem

openssl crl -in issuing_ca/crl/crl.pem \
            -out issuing_ca/crl/crl.der \
            -outform der
