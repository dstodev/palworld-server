FROM ubuntu:latest
#    ubuntu:latest tracks the latest LTS release

RUN apt update \
	&& apt install -y sqlite3 libsdl2-2.0-0 \
	&& apt install -y --reinstall ca-certificates

ARG server_port=8211
ARG user_id=30120
ARG group_id=30120

RUN addgroup --gid $group_id server-group \
	&& adduser --disabled-password \
	           --gecos '' \
	           --uid $user_id \
	           --gid $group_id \
	           server-user

ENV SERVER_PORT=$server_port
ENV USER_ID=$user_id
ENV GROUP_ID=$group_id

EXPOSE $server_port/udp

WORKDIR /server-files/
#       /server-files/ is mounted as a volume
