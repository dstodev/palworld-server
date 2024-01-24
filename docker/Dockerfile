FROM ubuntu:latest
#    ubuntu:latest tracks the latest LTS release

RUN apt update \
	&& apt install -y sqlite3 libsdl2-2.0-0 \
	&& apt install -y --reinstall ca-certificates

ARG server_port
ARG rcon_port
ARG user_id
ARG user_name
ARG group_id
ARG group_name

RUN groupadd --gid $group_id $group_name \
	&& useradd --uid $user_id \
	           --gid $group_id \
	           $user_name

EXPOSE $server_port/udp
EXPOSE $rcon_port/tcp

WORKDIR /server-files/
#       /server-files/ is mounted as a volume
