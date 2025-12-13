#!/bin/sh
set -e
#logging functions
LOG_TS() { date +"%Y-%m-%d %H:%M:%S%z"; }
log_info()  { echo "$(LOG_TS) | [INFO]  $*"; }
log_warn() { echo "$(LOG_TS) | [WARN]  $*" >&2; }
log_error(){ echo "$(LOG_TS) | [ERROR] $*" >&2; exit 1; }

: "${PORT:=80}"
: "${SAVE_LOGS:=false}"
# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
  --help | -h)
    echo "Usage: $0 [--port PORT] [--save-logs]"
    echo ""
    echo "Options:"
    echo "  --port PORT            Port number for nginx (default: 80)"
    echo "  --save-logs            Save nginx logs instead of deleting them"
    exit 0
    ;;
  --port)
    PORT="$2"
    shift 2
    ;;
  --save-logs)
    SAVE_LOGS="true"
    shift 1
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

#remove symlink if exists
if [ -L "/etc/systemd/system/multi-user.target.wants/nginx_${PORT}.service" ]; then
  log_info "Removing symlink for nginx service..."
  sudo rm -f "/etc/systemd/system/multi-user.target.wants/nginx_${PORT}.service"
fi

#remove log files
if [ "${SAVE_LOGS}" = "true" ]; then
  log_info "Saving nginx log files..."
else
  log_info "Removing nginx log files..."
  NGINX_LOG_DIR="/var/log/nginx_${PORT}"
  if [ -d "${NGINX_LOG_DIR}" ]; then
    sudo rm -rf "${NGINX_LOG_DIR}"
  fi
fi

#remove nginx config file if exists
NGINX_CONF_PATH="/etc/nginx/sites-available/nginx_${PORT}.conf"
if [ -f "${NGINX_CONF_PATH}" ]; then
  log_info "Removing nginx config file..."
  sudo rm -f "${NGINX_CONF_PATH}"
fi

# Reload systemd daemon
log_info "Reloading systemd daemon..."
sudo systemctl daemon-reload



