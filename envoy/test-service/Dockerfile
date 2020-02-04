FROM alpine:3.9

RUN apk update && apk add python3 bash curl
RUN pip3 install -q Flask
RUN mkdir /code
ADD ./test-service.py /code
ADD ./app /code
ADD ./start_service.sh /usr/local/bin/start_service.sh
RUN chmod u+x /usr/local/bin/start_service.sh
ENTRYPOINT /usr/local/bin/start_service.sh