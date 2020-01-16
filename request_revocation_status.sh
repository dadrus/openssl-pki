#!/bin/bash

openssl ocsp -CAfile issuing_ca/certs/ca_chain.pem \
             -url http://localhost:2552 -resp_text \
             -issuer issuing_ca/certs/issuing_ca_cert.pem \
             -cert server/certs/example1.com.cert.pem
