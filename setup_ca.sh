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
    -cn | --common_name)
      COMMON_NAME="${2:?ERROR: '--common_name' requires a non-empty option argument}"
      shift
      ;;
    -t | --type)
      CA_TYPE="${2:?ERROR: '--type' requires a non-empty option argument}"
      CA_TYPE=$(tolower "${CA_TYPE}")
      shift
      ;;
    -o | --out_dir)
      WORKING_DIR="${2:?ERROR: '--out_dir' requires a non-empty option argument}"
      WORKING_DIR=$(realpath ${WORKING_DIR})
      shift
      ;;
    -p | --parent_dir)
      ISSUER_DIR="${2:?ERROR: '--parent_dir' requires a non-empty option argument}"
      ISSUER_DIR=$(realpath ${ISSUER_DIR})
      shift
      ;;
    -v | --verbose)
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

SCRIPT_PATH=$(dirname $(realpath -s $0))

BASE_NAME=$(tolower "$(echo "${COMMON_NAME}" | sed -r 's/[ _()]+/-/g')")
TEMPLATES_DIR=${SCRIPT_PATH}/templates
CONF_TEMPLATE=${TEMPLATES_DIR}/ca.conf.template
WORKING_CONF=${WORKING_DIR}/ca.conf
EXTENSION_REF=""
BASE_CA_CONFIG=""


case "${CA_TYPE}" in
  root-ca)
    EXTENSION_REF="root-ca"
    if [ -d "${ISSUER_DIR}" ]; then
      BASE_CA_CONFIG=${ISSUER_DIR}/ca.conf
    fi
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

CA_PRIVATE_KEY_FILE=$WORKING_DIR/private/ca_key.pem
CA_CERTIFICATE_FILE=$WORKING_DIR/certs/ca_cert.pem
CA_CROSS_CERTIFICATE_FILE=$WORKING_DIR/certs/ca_cross_cert.pem
CA_CSR_FILE=$WORKING_DIR/csr/ca_csr.pem
OCSP_PRIVATE_KEY_FILE=$WORKING_DIR/private/ocsp_key.pem
OCSP_CSR_FILE=$WORKING_DIR/csr/ocsp_csr.pem
OCSP_CERTIFICATE_FILE=$WORKING_DIR/certs/ocsp_cert.pem
CRL_FILE_NAME="${BASE_NAME}.crl"
CERTIFICATE_FILE_NAME="${BASE_NAME}.crt"
OCSP_DOMAIN_NAME="${BASE_NAME}-ocsp"
DOCKER_CONFIG_FILE=${WORKING_DIR}/docker.config
CA_CERT_STORE=$WORKING_DIR/certs/ca_chain.p12
CA_CERT_STORE_PASS="changeit"

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
  
  cat ${ISSUER_DIR}/certs/ca_chain.pem > $WORKING_DIR/certs/ca_chain.pem
  cat $CA_CERTIFICATE_FILE >> $WORKING_DIR/certs/ca_chain.pem

else
  # create self-signed CA certificate
  echo "Generating self-signed certificate"
  openssl req -config $WORKING_CONF \
              -new -x509 -days 3650 -extensions ${EXTENSION_REF} \
              -nodes \
              -subj "/C=DE/ST=NRW/L=Ruhr City/O=No Liability Ltd./CN=${COMMON_NAME}" \
              -keyout $CA_PRIVATE_KEY_FILE \
              -out $CA_CERTIFICATE_FILE

  cat $CA_CERTIFICATE_FILE > $WORKING_DIR/certs/ca_chain.pem

  # if ISSUER_DIR is supplied create a cross certificate
  if [ -d "${ISSUER_DIR}" ]; then
    echo "Creating cross-certificate"
    # create CSR from self-signed cert
    openssl x509 -x509toreq -in $CA_CERTIFICATE_FILE \
                 -signkey $CA_PRIVATE_KEY_FILE \
                 -out $CA_CSR_FILE

    # request cert from referenced CA
    echo "Request certificate"
    openssl ca -config $BASE_CA_CONFIG \
               -extensions intermediate-ca \
               -days 3650 -notext \
               -in $CA_CSR_FILE \
               -out $CA_CROSS_CERTIFICATE_FILE

    echo "Updating CA chain"
    cat $CA_CROSS_CERTIFICATE_FILE >> $WORKING_DIR/certs/ca_chain.pem
    cat ${ISSUER_DIR}/certs/ca_cert.pem >> $WORKING_DIR/certs/ca_chain.pem
  fi
fi

# create a pkcs#12 file with certificates from the chain file
# it would be great if we just could use openssl pkcs12, but it is unfortunatelly not compatible with Java KeyTool, which will be used
# by java client and server
cat $WORKING_DIR/certs/ca_chain.pem | awk 'split_after==1{n++;split_after=0} /-----END CERTIFICATE-----/ {split_after=1} {if(length($0) > 0) print > "tmp_cert" n ".pem"}'

counter=0
for file in $(ls tmp_cert*); do
  keytool -importcert -noprompt -alias "cert-$counter" -file $file -keystore ${CA_CERT_STORE} -storepass ${CA_CERT_STORE_PASS}
  rm $file
  let counter+=1
done

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

# generate some helper scripts

function generate() {
  IN_TEMPLATE=$1
  OUT_FILE=$2

  truncate -s 0 ${OUT_FILE}

  regex='\$\{([a-zA-Z_][a-zA-Z_0-9]*)\}'
  cat ${IN_TEMPLATE} | while read line; do
    while [[ "$line" =~ $regex ]]; do
        param="${BASH_REMATCH[1]}"
        line=${line//${BASH_REMATCH[0]}/${!param}}
    done
    echo "$line" >> ${OUT_FILE}
  done
}

# create docker.config file containing the relevant entries to generate a docker-compose file
cat > "${DOCKER_CONFIG_FILE}" <<EOF
OCSP_CERTIFICATE_FILE=${OCSP_CERTIFICATE_FILE}
OCSP_PRIVATE_KEY_FILE=${OCSP_PRIVATE_KEY_FILE}
CA_INDEX_FILE=${WORKING_DIR}/index.txt
CA_CHAIN_FILE=${WORKING_DIR}/certs/ca_chain.pem
CA_CERTIFICATE_FILE=${CA_CERTIFICATE_FILE/.pem/.der}
CA_CERTIFICATE_FILE_PEM=${CA_CERTIFICATE_FILE}
SRV_CERTIFICATE_FILE_NAME=${CERTIFICATE_FILE_NAME}
CRL_FILE=${WORKING_DIR}/crl/crl.pem
SRV_CRL_FILE_NAME=${CRL_FILE_NAME}
OCSP_DOMAIN_NAME=${OCSP_DOMAIN_NAME}
EOF

# generate CRL generator script
generate ${TEMPLATES_DIR}/generate_crl.sh.template ${WORKING_DIR}/generate_crl.sh

if [ "${ISSUER_DIR}" ]; then
  cat >> ${WORKING_DIR}/generate_crl.sh <<EOF

# create a crl bundle by merging the crl bundle of the parent ca with the own crl
if [ -s ${ISSUER_DIR}/crl/crl.bundle ]; then
  cat ${ISSUER_DIR}/crl/crl.bundle >> ${WORKING_DIR}/crl/crl.bundle
fi
EOF
fi

chmod +x ${WORKING_DIR}/generate_crl.sh

${WORKING_DIR}/generate_crl.sh

# generate cert revokation skript
generate ${TEMPLATES_DIR}/revoke_certificate.sh.template ${WORKING_DIR}/revoke_certificate.sh
chmod +x ${WORKING_DIR}/revoke_certificate.sh


