#!/bin/bash

openssl ocsp -port 2552 -text -index /opt/ocsp/index.txt -CA /opt/ocsp/ca_cert.pem -rkey /opt/ocsp/key.pem -rsigner /opt/ocsp/cert.pem
