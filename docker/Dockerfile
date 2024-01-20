FROM ubuntu:latest
#    ubuntu:latest tracks the latest LTS release

RUN apt update \
	&& apt install -y sqlite3 libsdl2-2.0-0 \
	&& apt install -y --reinstall ca-certificates

ARG server_port=8221

ENV SERVER_PORT=$server_port

EXPOSE $server_port/udp

WORKDIR /server-files/
