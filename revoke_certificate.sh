#!/bin/bash

openssl ca -config issuingca.conf \
           -revoke client/certs/client2.cert.pem

