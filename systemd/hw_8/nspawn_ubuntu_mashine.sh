#!/bin/sh
set -ex
: "${PLATFORM:=amd64}"
: "${UBUNTU_RELEASE:=noble}"
: "${MACHINE_NAME:=noble1}"
: "${USERNAME_SCRIPT:=admin}"
: "${CURRENT_HOME:=/home/flyon21}"
: "${ONLY_SPAWN:=false}"

while [ $# -gt 0 ]; do
  case "$1" in
    --help | -h)
      echo "Usage: $0 [--platform PLATFORM] [--ubuntu-release RELEASE] [--machine-name NAME] [--username USERNAME] [--current-home PATH] [--only-spawn BOOL]"
      echo ""
      echo "Options:"
      echo "  --platform PLATFORM             Architecture platform (default: amd64)"
      echo "  --ubuntu-release RELEASE        Ubuntu release name (default: noble)"
      echo "  --machine-name NAME             Name of the nspawn machine (default: noble1)"
      echo "  --username USERNAME             Username to create inside the machine (default: admin)"
      echo "  --current-home PATH             Path to current user's home directory (default: /home/flyon21)"
      echo "  --only-spawn BOOL               If true, only spawn the machine without further setup (default: true)"
      exit 0
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --ubuntu-release)
      UBUNTU_RELEASE="$2"
      shift 2
      ;;
    --machine-name)
      MACHINE_NAME="$2"
      shift 2
      ;;
    --username)
      USERNAME_SCRIPT="$2"
      shift 2
      ;;
    --current-home)
      CURRENT_HOME="$2"
      shift 2
      ;;
    --only-spawn)
      ONLY_SPAWN=true
      shift 1
      ;;
  *)
    log_error "Unknown argument: $1"
    exit 1
    ;;
  esac
done


MACHINE_PATH="/var/lib/machines/${MACHINE_NAME}"
if [ "${ONLY_SPAWN}" = "true" ]; then
  sudo systemd-nspawn \
    --bind="${CURRENT_HOME}/PycharmProjects/dev_ops_course_hillel/systemd/hw_8:/mnt/hw_8" \
    -b -D "${MACHINE_PATH}"
  exit 0
else
  set -e
  sudo apt update && sudo apt install -y debootstrap systemd-container

  sudo debootstrap --arch="${PLATFORM}" "${UBUNTU_RELEASE}" "${MACHINE_PATH}" http://archive.ubuntu.com/ubuntu


  sudo systemd-nspawn -D "${MACHINE_PATH}" passwd

  sudo systemd-nspawn -D "${MACHINE_PATH}" useradd -m -s /bin/bash "${USERNAME_SCRIPT}"
  sudo systemd-nspawn -D "${MACHINE_PATH}" passwd "${USERNAME_SCRIPT}"
  #needed groups
  sudo systemd-nspawn -D "${MACHINE_PATH}" usermod -aG sudo "${USERNAME_SCRIPT}"
  sudo systemd-nspawn -D "${MACHINE_PATH}" usermod -aG systemd-journal "${USERNAME_SCRIPT}"
  sudo systemd-nspawn -D "${MACHINE_PATH}" usermod -aG adm "${USERNAME_SCRIPT}"

  sudo systemd-nspawn --bind-ro=/etc/resolv.conf -D "${MACHINE_PATH}" \
    sh -c "apt update && apt install -y software-properties-common && add-apt-repository -y universe"

  sudo systemd-nspawn --bind-ro=/etc/resolv.conf -D "${MACHINE_PATH}" apt update
  sudo systemd-nspawn --bind-ro=/etc/resolv.conf -D "${MACHINE_PATH}" apt install -y sudo vim net-tools iputils-ping systemd-sysv dbus graphviz cups daemonize stress openssh-server

  sudo systemd-nspawn \
    --bind="${CURRENT_HOME}/PycharmProjects/dev_ops_course_hillel/systemd/hw_8:/mnt/hw_8" \
    -b -D "${MACHINE_PATH}"
fi

