#!/bin/bash

openssl ocsp -port 2552 -text -index /opt/ocsp/index.txt -CA /opt/ocsp/ca-chain.pem -rkey /opt/ocsp/key.pem -rsigner /opt/ocsp/cert.pem
