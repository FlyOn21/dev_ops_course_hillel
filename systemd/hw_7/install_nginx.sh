#!/bin/sh
set -e
#logging functions
LOG_TS() { date +"%Y-%m-%d %H:%M:%S%z"; }
log_info() { echo "$(LOG_TS) | [INFO]  $*"; }
log_warn() { echo "$(LOG_TS) | [WARN]  $*" >&2; }
log_error() { echo "$(LOG_TS) | [ERROR] $*" >&2; exit 1; }

: "${PORT:=80}"
: "${INDEX_HTML_TEMPLATE:=./index_html.template}"
: "${NGINX_CONF_TEMPLATE:=./nginx_conf.template}"
: "${ENABLE_SERVICE:=false}"


#parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --help | -h)
      echo "Usage: $0 [--port PORT] [--index-html-template PATH] [--nginx-conf-template PATH] [--enable-service]"
      echo ""
      echo "Options:"
      echo "  --port PORT                     Port number for nginx (default: 80)"
      echo "  --index-html-template PATH      Path to index HTML template file (default: ./index_html.template)"
      echo "  --nginx-conf-template PATH      Path to nginx config template file (default: ./nginx_conf.template)"
      echo "  --enable-service                Enable the nginx systemd service after installation"
      exit 0
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --index-html-template | -iht)
      INDEX_HTML_TEMPLATE="$2"
      shift 2
      ;;
    --nginx-conf-template | -nct)
      NGINX_CONF_TEMPLATE="$2"
      shift 2
      ;;
    --enable-service | -es)
      ENABLE_SERVICE="true"
      shift 1
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

#check nginx installed
if ! command -v nginx >/dev/null 2>&1; then
  log_error "nginx is not installed. Please install nginx and try again."
  exit 1
fi

#check template files exists
if [ ! -f "$INDEX_HTML_TEMPLATE" ]; then
  log_error "Index HTML template file not found: $INDEX_HTML_TEMPLATE"
fi
if [ ! -f "$NGINX_CONF_TEMPLATE" ]; then
  log_error "Nginx config template file not found: $NGINX_CONF_TEMPLATE"
fi

log_info "Deploying nginx with port=$PORT, index_html_template=$INDEX_HTML_TEMPLATE, nginx_conf_template=$NGINX_CONF_TEMPLATE"
# Check install envsubst
if ! command -v envsubst >/dev/null 2>&1; then
  log_warn "envsubst is not installed. Please install the 'gettext' package."
  log_info "Installing gettext..."
  sudo apt-get update && sudo apt-get install -y gettext
  log_info "gettext installed."
fi

export PORT NGINX_CONF_TEMPLATE INDEX_HTML_TEMPLATE
# Create nginx config from template
log_info "Creating nginx config from template..."

CONF_FILE_PATH="/etc/nginx/sites-available/nginx_${PORT}.conf"

if [ ! -e "$CONF_FILE_PATH" ]; then
  sudo touch "$CONF_FILE_PATH"
else
  sudo mv "$CONF_FILE_PATH" "$CONF_FILE_PATH.bak"
fi

envsubst '$PORT' < "${NGINX_CONF_TEMPLATE}" | sudo tee "$CONF_FILE_PATH" > /dev/null

#create index.html from template
log_info "Creating index.html from template..."
INDEX_HTML_PATH="/var/www/html/index_${PORT}.html"
if [ ! -e "$INDEX_HTML_PATH" ]; then
  sudo touch "$INDEX_HTML_PATH"
else
  sudo mv "$INDEX_HTML_PATH" "$INDEX_HTML_PATH.bak"
fi
envsubst '$PORT' < "${INDEX_HTML_TEMPLATE}" | sudo tee "$INDEX_HTML_PATH" > /dev/null

# create unit service file
log_info "Creating systemd service for nginx on port $PORT..."
SERVICE_FILE_PATH="/etc/systemd/system/nginx_${PORT}.service"
if [ ! -e "$SERVICE_FILE_PATH" ]; then
  sudo touch "$SERVICE_FILE_PATH"
else
  sudo mv "$SERVICE_FILE_PATH" "$SERVICE_FILE_PATH.bak"
fi
sudo tee "$SERVICE_FILE_PATH" > /dev/null <<EOF
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target
ConditionFileIsExecutable=/usr/sbin/nginx

[Service]
Type=forking
PIDFile=/run/nginx_${PORT}.pid
ExecStartPre=/usr/sbin/nginx -t -q -c ${CONF_FILE_PATH}
ExecStart=/usr/sbin/nginx -c ${CONF_FILE_PATH}
ExecReload=/usr/sbin/nginx -c ${CONF_FILE_PATH} -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx_${PORT}.pid
TimeoutStopSec=5
StandardOutput=append:/var/log/nginx_${PORT}/access.log
StandardError=append:/var/log/nginx_${PORT}/error.log
KillMode=mixed
PrivateTmp=true

[Install]
WantedBy=multi-user.target

EOF

# create log directory
LOG_DIR="/var/log/nginx_${PORT}"
if [ ! -d "$LOG_DIR" ]; then
  log_info "Creating log directory: $LOG_DIR"
  sudo mkdir -p "$LOG_DIR"
fi

# reload systemd and start nginx service
log_info "Reloading systemd daemon..."
sudo systemctl daemon-reload
log_info "Enabling and starting nginx service on port $PORT..."
if
[ "$ENABLE_SERVICE" = "true" ]; then
  log_info "--enable-service set, enbled service."
  sudo systemctl enable "nginx_${PORT}.service"
fi
sudo systemctl start "nginx_${PORT}.service"





