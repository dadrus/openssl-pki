#!/usr/bin/env bash

usage() {
    cat << EOF
This script supports generation of CSRs.

Usage:


EOF
}

abort() {
    message="$*"

    echo "$message" >&2
    exit 1
}

tolower() {
  echo "$*" | tr '[:upper:]' '[:lower:]'
}

toupper() {
  echo "$*" | tr '[:lower:]' '[:upper:]'
}

[ "$*" ] || { usage; exit 1; }

COMMON_NAME=""
SUBJECT_ALT_NAMES=""
CERTIFICATE_TYPE=""
CA_DIR=""
OUT_DIR=""

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
    -san | --subject_alt_names)
      SUBJECT_ALT_NAMES="${2:?ERROR: '--subject_alt_names' requires a non-empty option argument}"
      shift
      ;;
    -t | --type)
      CERTIFICATE_TYPE="${2:?ERROR: '--type' requires a non-empty option argument}"
      shift
      ;;
    -ca | --ca_dir)
      CA_DIR="${2:?ERROR: '--ca_dir' requires a non-empty option argument}"
      CA_DIR=$(grealpath ${CA_DIR})
      shift
      ;;
    -o | --out_dir)
      OUT_DIR="${2:-$OUT_DIR}"
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

[ "${COMMON_NAME}" ]      || abort "ERROR:" "Usage of --common_name is mandatory"
[ "${CA_DIR}" ]           || abort "ERROR:" "Usage of --ca_dir argument is mandatory"
[ "${OUT_DIR}" ]          || abort "ERROR:" "Usage of --out_dir argument is mandatory"
[ "${CERTIFICATE_TYPE}" ] || abort "ERROR:" "Usage of --type argument is mandatory"

mkdir -p "${OUT_DIR}"
OUT_DIR=$(grealpath ${OUT_DIR})
CONFIG_FILE_NAME="$(echo "${COMMON_NAME}" | sed -E 's/[ _()]+/-/g' | sed -E 's/[*]+/star/g')-$(date +%Y-%m-%d-%H%M%S)"

EXTENSION_REF=""
CA_CONFIG=${CA_DIR}/ca.conf
PRIVATE_KEY_FILE=${OUT_DIR}/key.pem
CSR_FILE=${OUT_DIR}/csr.pem
CERTIFICATE_FILE=${OUT_DIR}/cert.pem
CONFIG_FILE="/tmp/${CONFIG_FILE_NAME}.conf"
CA_CHAIN_FILE=${CA_DIR}/certs/ca_chain.pem
DOCKER_CONFIG_FILE=${OUT_DIR}/docker.config

[ -s "${CA_CONFIG}" ]     || abort "ERROR:" "Referenced CA directory does not contain the required configuration"
[ -s "${CA_CHAIN_FILE}" ] || abort "ERROR:" "Referenced CA directory does not contain the required configuration"

case "${CERTIFICATE_TYPE}" in
  tls-client)
    EXTENSION_REF="user-cert"
    ;;
  tls-server)
    EXTENSION_REF="server-cert"
    ;;
  *) abort "ERROR:" "Unsupported certificate type \"${CERTIFICATE_TYPE}\"!"
esac

# generate OpenSSL config file
cat > "${CONFIG_FILE}" <<EOF
[ req ]
default_bits            = 2048        # RSA key size
encrypt_key             = yes         # Protect private key
default_md              = sha256      # MD to use
utf8                    = yes         # Input is UTF-8
string_mask             = utf8only    # Emit UTF-8 strings
prompt                  = no          # Don't prompt for DN
distinguished_name      = req_dn     # DN section
req_extensions          = req_ext     # Desired extensions

[ req_dn ]
C   = "DE"
L   = "Ruhr City"
ST  = "NRW"
O   = "No Liability Ltd."
CN  = "$COMMON_NAME"

[ req_ext ]
subjectKeyIdentifier    = hash
EOF

if [ "${SUBJECT_ALT_NAMES}" ]; then
  cat >> "${CONFIG_FILE}" <<EOF
subjectAltName          = $SUBJECT_ALT_NAMES
EOF
fi

echo "Creating CSR to request the CA certificate from the CA"
openssl req -config ${CONFIG_FILE} \
            -new \
            -nodes \
            -keyout ${PRIVATE_KEY_FILE} \
            -out ${CSR_FILE}

echo "Request certificate"
openssl ca -config ${CA_CONFIG} \
           -extensions ${EXTENSION_REF} \
           -days 365 -notext \
           -in ${CSR_FILE} \
           -out ${CERTIFICATE_FILE}

chmod 400 ${PRIVATE_KEY_FILE}
chmod 444 ${CERTIFICATE_FILE}

cp $CA_CHAIN_FILE ${OUT_DIR}/
openssl verify -CAfile ${CA_CHAIN_FILE} ${CERTIFICATE_FILE}

# create docker.config file containing the relevant entries to generate a docker-compose file
cat > "${DOCKER_CONFIG_FILE}" <<EOF
SERVER_DOMAIN=${COMMON_NAME}
SRV_CERTIFICATE_FILE=${CERTIFICATE_FILE}
SRV_PRIVATE_KEY_FILE=${PRIVATE_KEY_FILE}
CA_CHAIN_FILE=${CA_CHAIN_FILE}
CRL_FILE=${CA_DIR}/crl/crl.bundle
EOF
