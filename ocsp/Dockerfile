FROM debian:buster-slim

RUN apt-get update && apt-get upgrade -y && apt-get install -y openssl
COPY ocsp.sh /opt/ocsp/ocsp.sh

CMD ["/opt/ocsp/ocsp.sh"]


