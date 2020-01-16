#!/bin/bash

openssl ca -config rootca.conf \
           -gencrl \
           -out root_ca/crl/crl.pem

openssl crl -in root_ca/crl/crl.pem \
            -out root_ca/crl/crl.der \
            -outform der
