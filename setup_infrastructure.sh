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

CA_DIRS=""
SERVER_TYPE=""
OUT_DIR=""
VERBOSE=false

declare -a CA_REFERENCES
declare -a SERVERS
declare -a CONTAINER_REFERENCES

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -ca | --ca_dir)
      CA_DIR="${2:?ERROR: '--ca_dir' requires a non-empty option argument}"
      CA_DIR=$(realpath ${CA_DIR})
      CA_REFERENCES+=($CA_DIR)
      shift
      ;;
    -s | --server)
      SERVER="${2:?ERROR: '--server' requires a non-empty option argument}"
      SERVERS+=($SERVER)
      shift
      ;;
    -o | --out_dir)
      OUT_DIR="${2:?ERROR: '--out_dir' requires a non-empty option argument}"
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

DOCKER_COMPOSE_FILE=${OUT_DIR}/docker-compose.yml
SCRIPT_PATH=$(dirname $(realpath -s $0))
mkdir -p ${OUT_DIR}

# create OCSP responder entries for each CA reference
echo "CAs: ${CA_REFERENCES[@]}"

cat > "${DOCKER_COMPOSE_FILE}" <<EOF
version: '3.6'
services:
EOF

CONTAINER_PORT=2552
for ca_dir in "${CA_REFERENCES[@]}"; do
  DOCKER_CONF_FILE=${ca_dir}/docker.config

  [ -s "${DOCKER_CONF_FILE}" ] || abort "ERROR:" "no docker.config found in $ca_dir"

  source ${DOCKER_CONF_FILE}

  cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
  ${OCSP_DOMAIN_NAME}:
    build: ${SCRIPT_PATH}/ocsp
    ports:
      - "${CONTAINER_PORT}:2552"
    volumes:
      - ${CA_INDEX_FILE}:/opt/ocsp/index.txt
      - ${CA_CHAIN_FILE}:/opt/ocsp/ca-chain.pem
      - ${OCSP_PRIVATE_KEY_FILE}:/opt/ocsp/key.pem
      - ${OCSP_CERTIFICATE_FILE}:/opt/ocsp/cert.pem

EOF
  let CONTAINER_PORT+=1

  CONTAINER_REFERENCES+=(${OCSP_DOMAIN_NAME})
done

# create certificate directory entry
cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
  cert-dir:
    build: nginx
    ports:
      - "8080:80"
    volumes:
      - ${SCRIPT_PATH}/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ${SCRIPT_PATH}/nginx/servers/cert-dir.conf:/etc/nginx/my-conf.d/cert-dir.conf
EOF
for ca_dir in "${CA_REFERENCES[@]}"; do
  DOCKER_CONF_FILE=${ca_dir}/docker.config

  [ -s "${DOCKER_CONF_FILE}" ] || abort "ERROR:" "no docker.config found in $ca_dir"

  source ${DOCKER_CONF_FILE}
  cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
      - ${CA_CERTIFICATE_FILE}:/var/www/cert-dir/${SRV_CERTIFICATE_FILE_NAME}
      - ${CRL_FILE}:/var/www/cert-dir/${SRV_CRL_FILE_NAME}
EOF
done

CONTAINER_REFERENCES+=("cert-dir")

# create server entries based on given type
CONTAINER_PORT=8443
for srv in "${SERVERS[@]}"; do
  IFS=',' read -ra SERVER_AND_TYPE <<< "$srv"
  SRV_PATH=${SERVER_AND_TYPE[0]}
  SRV_TYPE=$(tolower "${SERVER_AND_TYPE[1]}")

  echo "SRV: ${SRV_PATH} - ${SRV_TYPE}"

  DOCKER_CONF_FILE=${SRV_PATH}/docker.config

  [ -s "${DOCKER_CONF_FILE}" ] || abort "ERROR:" "no docker.config found in $SRV_PATH"

  source ${DOCKER_CONF_FILE}

  cat >> "${DOCKER_COMPOSE_FILE}" <<EOF

  ${SERVER_DOMAIN}:
    image: ${SRV_TYPE}
    ports:
      - "${CONTAINER_PORT}:443"
    links:
EOF

  for ref in "${CONTAINER_REFERENCES[@]}"; do
    cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
      - ${ref}
EOF
  done

  cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
    volumes:
      - ${SCRIPT_PATH}/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ${SCRIPT_PATH}/nginx/servers/example.com.conf:/etc/nginx/my-conf.d/example.com.conf
      - ${SCRIPT_PATH}/nginx/web/index.html:/var/www/example.com/index.html
      - ${SRV_CERTIFICATE_FILE}:/var/www/certs/example.com.cert.pem
      - ${SRV_PRIVATE_KEY_FILE}:/var/www/certs/example.com.key.pem
      - ${CA_CHAIN_FILE}:/var/www/certs/ca-chain.pem
      - ${CRL_FILE}:/var/www/certs/crl.pem
EOF
done


