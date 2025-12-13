#!/bin/sh
set -e
#logging functions
LOG_TS() { date +"%Y-%m-%d %H:%M:%S%z"; }
log_info()  { echo "$(LOG_TS) | [INFO]  $*"; }
log_warn() { echo "$(LOG_TS) | [WARN]  $*" >&2; }
log_error(){ echo "$(LOG_TS) | [ERROR] $*" >&2; exit 1; }

: "${PORT:=80}"
# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    echo "Usage: $0 [--port PORT]"
    echo ""
    echo "Options:"
    echo "  --port PORT  Port number for nginx (default: 80)"
    exit 0
    ;;
  --port)
    PORT="$2"
    shift 2
    ;;
  *)
    log_error "Unknown argument: $1"
    exit 1
    ;;
  esac
done

SERVICE_FILE_PATH="/etc/systemd/system/nginx_${PORT}.service"
INDEX_HTML_PATH="/var/www/html/index_${PORT}.html"

if [ ! -e "${SERVICE_FILE_PATH}" ]; then
  log_warn "Nginx service file not found at ${SERVICE_FILE_PATH}. Nginx may not be installed on port=${PORT}."
  exit 0
fi

log_info "Uninstalling nginx from port=$PORT"
# Stop and disable nginx service

log_info "Disabling nginx service..."
sudo systemctl is-enabled --quiet "nginx_${PORT}.service" && {
  sudo systemctl disable "nginx_${PORT}.service"
}
log_info "Stopping nginx service..."
sudo systemctl is-active --quiet "nginx_${PORT}.service" && {
  sudo systemctl stop "nginx_${PORT}.service"
}
# Remove service file
log_info "Removing nginx service file..."
sudo rm -f "${SERVICE_FILE_PATH}"

# Remove index html file
log_info "Removing nginx index html file..."
sudo rm -f "${INDEX_HTML_PATH}"


