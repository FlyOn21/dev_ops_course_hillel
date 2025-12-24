#!/bin/bash
: "${PORT:=80}"
: "${HOME_DIR:=/home/flyon21}"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            PORT="$2"
            shift 2
            ;;
        --home-dir)
            HOME_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done
cd ~/PycharmProjects/dev_ops_course_hillel
podman build \
  --build-arg PORT=${PORT} \
  -t nginx-hw10 \
  -f ${HOME_DIR}/PycharmProjects/dev_ops_course_hillel/containerization/hw_10/Containerfile \
  .
