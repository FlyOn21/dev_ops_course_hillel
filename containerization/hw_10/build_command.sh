#!/bin/bash
: "${PORT:=80}"
: "${HOME_DIR:=/home/flyon21}"

if [ $# -lt 2 ];
then
    echo "Usage: $0 --port PORT --home-dir HOME_DIR"
    exit 1
fi

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
cd "${HOME_DIR}/PycharmProjects/dev_ops_course_hillel" || exit 1
podman build \
  --build-arg PORT="${PORT}" \
  -t nginx-hw10 \
  -f "${HOME_DIR}/PycharmProjects/dev_ops_course_hillel/containerization/hw_10/Containerfile" \
  .
