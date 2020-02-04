FROM alpine:3.9

LABEL maintainer="dimitrij.drus@innoq.com"

RUN apk update && apk add python3 bash curl && \
    pip3 install -q Flask

WORKDIR /service

COPY test-service.py /service

ENTRYPOINT [ "python3" ]
CMD [ "test-service.py" ]