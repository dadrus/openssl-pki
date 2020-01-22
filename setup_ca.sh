#!/bin/bash

usage() {
    cat << EOF
This script supports setup of a simple PKI.
EOF
}

[ "$*" ] || { usage; exit 1; }

abort() {
    message="$*"

    echo "$message" >&2
    exit 1
}

tolower() {
  echo "$*" | tr '[:upper:]' '[:lower:]'
}

COMMON_NAME=""
CA_TYPE=""
WORKING_DIR=""
ISSUER_DIR=""
VERBOSE=false

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --common_name)
      COMMON_NAME="${2:?ERROR: '--common_name' requires a non-empty option argument}"
      shift
      ;;
    --ca_type)
      CA_TYPE="${2:?ERROR: '--ca_type' requires a non-empty option argument}"
      CA_TYPE=$(tolower "${CA_TYPE}")
      shift
      ;;
    --working_dir)
      WORKING_DIR="${2:?ERROR: '--working_dir' requires a non-empty option argument}"
      shift
      ;;
    --issuer_dir)
      ISSUER_DIR="${2:?ERROR: '--issuer_dir' requires a non-empty option argument}"
      shift
      ;;
    --verbose)
      VERBOSE=true
      ;;
    *)
      abort "Invalid option: $*"
      ;;
  esac

  shift
done

[ "${COMMON_NAME}" ] || abort "ERROR:" "Usage of --common_name is mandatory"
[ "${CA_TYPE}" ]     || abort "ERROR:" "Usage of --ca_type argument is mandatory"
[ "${WORKING_DIR}" ] || abort "ERROR:" "Usage of --working_dir argument is mandatory"

BASE_NAME=$(tolower "$(echo "${COMMON_NAME}" | sed -r 's/[ _()]+/-/g')")
CONF_TEMPLATE=./ca.conf.template
WORKING_CONF=${WORKING_DIR}/ca.conf
EXTENSION_REF=""
BASE_CA_CONFIG=""


case "${CA_TYPE}" in
  root-ca)
    EXTENSION_REF="root-ca"
    ;;
  intermediate-ca)
    EXTENSION_REF="intermediate-ca"
    [ "${ISSUER_DIR}" ] || abort "ERROR:" "Usage of --issuer_dir argument is mandatory for ca_type set to \"intermediate-ca\""
    BASE_CA_CONFIG=${ISSUER_DIR}/ca.conf
    ;;
  issuing-ca)
    EXTENSION_REF="issuing-ca"
    [ "${ISSUER_DIR}" ] || abort "ERROR:" "Usage of --issuer_dir argument is mandatory for ca_type set to \"issuing-ca\""
    BASE_CA_CONFIG=${ISSUER_DIR}/ca.conf
    ;;
  *) abort "ERROR:" "Unsupported CA type \"${CA_TYPE}\"!"
esac

# create directory structure required
mkdir -p \
    $WORKING_DIR/certs \
    $WORKING_DIR/crl \
    $WORKING_DIR/newcerts \
    $WORKING_DIR/private \
    $WORKING_DIR/csr
    
# create files required
touch $WORKING_DIR/index.txt
echo 1000 > $WORKING_DIR/serial
echo 1000 > $WORKING_DIR/crlnumber

CSR_CONFIG=./csr.conf
CA_PRIVATE_KEY_FILE=$WORKING_DIR/private/ca_key.pem
CA_CERTIFICATE_FILE=$WORKING_DIR/certs/ca_cert.pem
CA_CSR_FILE=$WORKING_DIR/csr/ca_csr.pem
OCSP_PRIVATE_KEY_FILE=$WORKING_DIR/private/ocsp_key.pem
OCSP_CSR_FILE=$WORKING_DIR/csr/ocsp_csr.pem
OCSP_CERTIFICATE_FILE=$WORKING_DIR/certs/ocsp_cert.pem
CRL_FILE_NAME="${BASE_NAME}.crl"
CERTIFICATE_FILE_NAME="${BASE_NAME}.crt"
OCSP_DOMAIN_NAME="${BASE_NAME}-ocsp"

# generate openssl config
eval "echo \"$(cat "${CONF_TEMPLATE}")\"" > ${WORKING_CONF}

if [ ${CA_TYPE} != "root-ca" ]; then
  echo "Creating CSR to request the CA certificate from the CA"
  openssl req -config ${WORKING_CONF} \
          -new \
          -nodes \
          -subj "/C=DE/ST=NRW/L=Ruhr City/O=No Liability Ltd./CN=${COMMON_NAME}" \
          -keyout $CA_PRIVATE_KEY_FILE \
          -out $CA_CSR_FILE

  echo "Request certificate"
  openssl ca -config $BASE_CA_CONFIG \
             -extensions ${EXTENSION_REF} \
             -days 1825 -notext \
             -in $CA_CSR_FILE \
             -out $CA_CERTIFICATE_FILE
else
  # create self-signed CA certificate
  openssl req -config $WORKING_CONF \
              -new -x509 -days 3650 -extensions ${EXTENSION_REF} \
              -nodes \
              -subj "/C=DE/ST=NRW/L=Ruhr City/O=No Liability Ltd./CN=${COMMON_NAME}" \
              -keyout $CA_PRIVATE_KEY_FILE \
              -out $CA_CERTIFICATE_FILE
fi

chmod 400 $CA_PRIVATE_KEY_FILE      
chmod 444 $CA_CERTIFICATE_FILE

openssl x509 -in $CA_CERTIFICATE_FILE -out "${CA_CERTIFICATE_FILE/.pem/.der}" -outform der

echo "Creating CSR to request the OCSP responder certificate from the CA"
openssl req -config ${WORKING_CONF} \
            -new \
            -nodes \
            -subj "/C=DE/ST=NRW/L=Ruhr City/O=No Liability Ltd./CN=${COMMON_NAME} OCSP" \
            -keyout $OCSP_PRIVATE_KEY_FILE \
            -out $OCSP_CSR_FILE

echo "Sing the OCSP certificate by the CA"
openssl ca -config ${WORKING_CONF} \
           -extensions ocsp \
           -days 365 -notext \
           -in $OCSP_CSR_FILE \
           -out $OCSP_CERTIFICATE_FILE 

chmod 400 $OCSP_PRIVATE_KEY_FILE
chmod 444 $OCSP_CERTIFICATE_FILE
