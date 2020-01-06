#!/bin/bash
#
# Build and run this project in a Docker container

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root"
	exit
fi

docker build .
docker run -it --privileged -p 3000:3000 -p 8086:8086 `docker images -q | head -n 1`
