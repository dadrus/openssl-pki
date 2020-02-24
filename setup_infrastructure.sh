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
      CA_DIR=$(grealpath ${CA_DIR})
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
SCRIPT_PATH=$(dirname $(grealpath -s $0))
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
      - ${CA_CERTIFICATE_FILE_PEM}:/opt/ocsp/ca_cert.pem
      - ${OCSP_PRIVATE_KEY_FILE}:/opt/ocsp/key.pem
      - ${OCSP_CERTIFICATE_FILE}:/opt/ocsp/cert.pem

EOF
  let CONTAINER_PORT+=1

  CONTAINER_REFERENCES+=(${OCSP_DOMAIN_NAME})
done

# create certificate directory entry
cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
  cert-dir:
    image: nginx
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

# create entry for the backend service
cat >> "${DOCKER_COMPOSE_FILE}" <<EOF

  test-service:
    build:
      context: ${SCRIPT_PATH}/backend
      dockerfile: Dockerfile
    expose:
      - "9090"
EOF

CONTAINER_REFERENCES+=("test-service")

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

  
  # there is no way to specify a separate file containing the certificate chain
  # for the given ee certificate. Therefore we create a new file with all relevant entries
  TMP_CERT_FILE_WITH_CHAIN="/tmp/srv-cert-with-chain-$(date +%Y-%m-%d-%H%M%S%N).pem"
  cat ${SRV_CERTIFICATE_FILE} > ${TMP_CERT_FILE_WITH_CHAIN}
  cat ${CA_CHAIN_FILE} >> ${TMP_CERT_FILE_WITH_CHAIN}

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
  
  if [ "${SRV_TYPE}" == "nginx" ]; then
    cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
    volumes:
      - ${SCRIPT_PATH}/nginx/nginx.conf:/etc/nginx/nginx.conf
      - ${SCRIPT_PATH}/nginx/servers/example.com.conf:/etc/nginx/my-conf.d/example.com.conf
      - ${SCRIPT_PATH}/nginx/web/index.html:/var/www/example.com/index.html
      - ${TMP_CERT_FILE_WITH_CHAIN}:/var/www/certs/srv_cert.pem
      - ${SRV_PRIVATE_KEY_FILE}:/var/www/certs/srv_key.pem
      - ${CA_CHAIN_FILE}:/var/www/certs/ca-chain.pem
      - ${CRL_FILE}:/var/www/certs/crl.pem
EOF
  elif [ "${SRV_TYPE}" == "httpd" ]; then
    cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
    volumes:
      - ${SCRIPT_PATH}/httpd/web/index.html:/usr/local/apache2/htdocs/index.html
      - ${SCRIPT_PATH}/httpd/httpd.conf:/usr/local/apache2/conf/httpd.conf
      - ${SCRIPT_PATH}/httpd/httpd-ssl.conf:/usr/local/apache2/conf/extra/httpd-ssl.conf
      - ${SRV_CERTIFICATE_FILE}:/usr/local/apache2/conf/server.crt
      - ${SRV_PRIVATE_KEY_FILE}:/usr/local/apache2/conf/server.key
      - ${CA_CHAIN_FILE}:/usr/local/apache2/conf/server-ca.crt
      - ${CA_CHAIN_FILE}:/usr/local/apache2/conf/ssl.crt/ca-bundle.crt
      - ${CRL_FILE}:/usr/local/apache2/conf/ssl.crl/ca-bundle.crl
EOF
  elif [ "${SRV_TYPE}" == "envoyproxy/envoy" ]; then
      cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
    volumes:
      - ${SCRIPT_PATH}/envoy/envoy.yaml:/etc/envoy/envoy.yaml
      - ${TMP_CERT_FILE_WITH_CHAIN}:/etc/envoy/server.crt
      - ${SRV_PRIVATE_KEY_FILE}:/etc/envoy/server.key
      - ${CA_CHAIN_FILE}:/etc/envoy/ca_bundle.crt
      - ${CRL_FILE}:/etc/envoy/ca_bundle.crl
EOF
  elif [ "${SRV_TYPE}" == "haproxy" ]; then
    # haproxy needs both certificate and the key in one file
    TMP_CERT_FILE_WITH_CHAIN_AND_KEY="/tmp/srv-cert-with-chain-and-key-$(date +%Y-%m-%d-%H%M%S%N).pem"
    cat ${TMP_CERT_FILE_WITH_CHAIN} > ${TMP_CERT_FILE_WITH_CHAIN_AND_KEY}
    cat ${SRV_PRIVATE_KEY_FILE} >> ${TMP_CERT_FILE_WITH_CHAIN_AND_KEY}

    # to support OCSP stapling we need a file with exact the same name as the cert&key file with .ocsp ending
    OCSP_RESPONSE_FILE=/tmp/haproxy_ocsp_resonse.ocsp
    touch ${OCSP_RESPONSE_FILE}

    cat >> "${DOCKER_COMPOSE_FILE}" <<EOF
    volumes:
      - ${SCRIPT_PATH}/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
      - ${TMP_CERT_FILE_WITH_CHAIN_AND_KEY}:/usr/local/etc/haproxy/cert_and_key.pem
      - ${OCSP_RESPONSE_FILE}:/usr/local/etc/haproxy/cert_and_key.pem.ocsp
      - ${CA_CHAIN_FILE}:/usr/local/etc/haproxy/ca_bundle.crt
      - ${CRL_FILE}:/usr/local/etc/haproxy/ca_bundle.crl
EOF
  else
    abort "ERROR:" "Unsupported server type $SRV_TYPE"
  fi
  let CONTAINER_PORT+=1
done
