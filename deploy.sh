#!/usr/bin/env bash
#
# GeoSenEsm — one-shot production deploy for a Linux host with Docker installed.
#
# Feed it the crucial elements (a domain or a bare IP, the admin password, the
# database password / connection info) and it will generate the Compose file
# and .env, start survey-api + survey-admin-panel + MongoDB (+ SQL Server for
# the single-server variant), and — when a domain is given — configure Nginx
# and a Let's Encrypt certificate.
#
# Run with no flags for a fully interactive walkthrough, or pass flags for a
# non-interactive / scripted deploy. Re-running is safe: it only rewrites
# generated files and re-runs `docker compose up -d`.
#
# Examples
# --------
# Single VM, everything in Docker, public domain with automatic TLS:
#   ./deploy.sh --domain example.com --email admin@example.com \
#               --admin-password 'S3cretAdmin!' --db-password 'Str0ng!Passw0rd'
#
# Bare IP, no domain yet (skips Nginx/TLS, exposes ports directly):
#   ./deploy.sh --ip 203.0.113.10 \
#               --admin-password 'S3cretAdmin!' --db-password 'Str0ng!Passw0rd'
#
# External SQL Server already running elsewhere:
#   ./deploy.sh --domain example.com --email admin@example.com \
#               --variant separate \
#               --db-host mymssqlserver.internal --db-name GeoSenEsm \
#               --db-user sa --db-password 'mypsswd' \
#               --admin-password 'S3cretAdmin!'
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
VARIANT=""
DOMAIN=""
IP=""
EMAIL=""
ADMIN_PASSWORD=""
DB_PASSWORD=""
DB_USER="sa"
DB_HOST=""
DB_NAME="GeoSenEsm"
DB_CONNECTION_STRING=""
JWT_KEY=""
JWT_EXPIRATION="180"
ALLOWED_ORIGINS=""
API_PORT="8083"
ADMIN_PORT="8084"
DEPLOY_DIR="${HOME:-.}/geosenesm"
SKIP_NGINX=false
SKIP_TLS=false
INSTALL_DOCKER=false
NO_PULL=false

SCRIPT_NAME="$(basename "$0")"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { printf '\033[1;32m[deploy]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[deploy]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[deploy]\033[0m %s\n' "$*" >&2; exit 1; }

is_tty() { [ -t 0 ]; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Target (pick one):
  --domain DOMAIN            Public domain, e.g. example.com. Creates
                              api.DOMAIN and admin.DOMAIN, sets up Nginx +
                              Let's Encrypt (unless --skip-nginx/--skip-tls).
  --ip IP                    Public/host IP. No Nginx or TLS; services are
                              published directly on --api-port/--admin-port.

Variant:
  --variant single|separate  single  = SQL Server + MongoDB + API + admin,
                              all in Docker on this host (default).
                              separate = SQL Server runs elsewhere; only
                              MongoDB + API + admin run here.

Secrets / config:
  --admin-password PASS      Initial admin account password (required).
  --db-password PASS         Database password (required).
  --db-user USER             DB user, separate variant only (default: sa).
  --db-host HOST             DB host, separate variant only.
  --db-name NAME             DB name, separate variant only (default: GeoSenEsm).
  --db-connection-string STR Full JDBC URL, separate variant only. Overrides
                              --db-host/--db-name/--db-user/--db-password
                              composition.
  --jwt-key KEY               HMAC signing key (>=256 bit). Auto-generated
                              with openssl if omitted.
  --jwt-expiration DAYS      JWT lifetime in days (default: 180).
  --allowed-origins LIST     CORS allow-list, comma separated (default: *).
  --email EMAIL              Contact email for Let's Encrypt (required
                              unless --skip-tls).

Ports / paths:
  --api-port PORT            Host port for survey-api (default: 8083).
  --admin-port PORT          Host port for survey-admin-panel (default: 8084).
  --deploy-dir DIR           Where to write compose/.env/data dirs
                              (default: \$HOME/geosenesm).

Flags:
  --skip-nginx               Don't touch Nginx even if --domain is set.
  --skip-tls                 Configure Nginx but skip certbot/TLS.
  --install-docker           Install Docker via get.docker.com if missing
                              (Debian/Ubuntu only).
  --no-pull                  Skip 'docker compose pull' (use local images).
  -h, --help                 Show this help.

Run with no flags to be prompted interactively for anything required.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

prompt_value() {
  # prompt_value VARNAME "Prompt text" [secret]
  local __var=$1 __text=$2 __secret=${3:-false}
  local __current=""
  eval "__current=\${$__var}"
  if [ -n "$__current" ]; then
    return
  fi
  if ! is_tty; then
    err "Missing required value for $__var. Pass it as a flag (see --help) or run interactively."
  fi
  local __input=""
  if [ "$__secret" = true ]; then
    read -rs -p "$__text: " __input; echo
  else
    read -r -p "$__text: " __input
  fi
  [ -n "$__input" ] || err "$__var cannot be empty."
  printf -v "$__var" '%s' "$__input"
}

generate_secret() {
  if require_cmd openssl; then
    openssl rand -base64 48 | tr -d '\n'
  else
    head -c 48 /dev/urandom | base64 | tr -d '\n'
  fi
}

validate_mssql_password() {
  local pass=$1 classes=0
  [[ "$pass" =~ [A-Z] ]] && classes=$((classes + 1))
  [[ "$pass" =~ [a-z] ]] && classes=$((classes + 1))
  [[ "$pass" =~ [0-9] ]] && classes=$((classes + 1))
  [[ "$pass" =~ [^a-zA-Z0-9] ]] && classes=$((classes + 1))
  if [ "${#pass}" -lt 8 ] || [ "$classes" -lt 3 ]; then
    err "--db-password must be at least 8 characters and contain characters from at least 3 of: uppercase, lowercase, digits, symbols."
  fi
}

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --ip) IP="$2"; shift 2 ;;
    --variant) VARIANT="$2"; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
    --db-password) DB_PASSWORD="$2"; shift 2 ;;
    --db-user) DB_USER="$2"; shift 2 ;;
    --db-host) DB_HOST="$2"; shift 2 ;;
    --db-name) DB_NAME="$2"; shift 2 ;;
    --db-connection-string) DB_CONNECTION_STRING="$2"; shift 2 ;;
    --jwt-key) JWT_KEY="$2"; shift 2 ;;
    --jwt-expiration) JWT_EXPIRATION="$2"; shift 2 ;;
    --allowed-origins) ALLOWED_ORIGINS="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-port) API_PORT="$2"; shift 2 ;;
    --admin-port) ADMIN_PORT="$2"; shift 2 ;;
    --deploy-dir) DEPLOY_DIR="$2"; shift 2 ;;
    --skip-nginx) SKIP_NGINX=true; shift ;;
    --skip-tls) SKIP_TLS=true; shift ;;
    --install-docker) INSTALL_DOCKER=true; shift ;;
    --no-pull) NO_PULL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1 (see --help)" ;;
  esac
done

[ "$(uname -s)" = "Linux" ] || warn "This script targets Linux; behaviour on $(uname -s) is untested."

# ---------------------------------------------------------------------------
# Resolve target (domain vs IP)
# ---------------------------------------------------------------------------
if [ -z "$DOMAIN" ] && [ -z "$IP" ]; then
  if is_tty; then
    read -r -p "Public domain (leave empty to use a bare IP instead): " DOMAIN
    if [ -z "$DOMAIN" ]; then
      prompt_value IP "Server public IP"
    fi
  else
    err "Pass --domain or --ip (see --help)."
  fi
fi
[ -n "$DOMAIN" ] && [ -n "$IP" ] && err "Pass only one of --domain / --ip."

if [ -n "$DOMAIN" ]; then
  API_DOMAIN="api.${DOMAIN}"
  ADMIN_DOMAIN="admin.${DOMAIN}"
  API_URL="https://${API_DOMAIN}"
else
  SKIP_NGINX=true
  SKIP_TLS=true
  API_URL="http://${IP}:${API_PORT}"
fi

# ---------------------------------------------------------------------------
# Resolve variant
# ---------------------------------------------------------------------------
if [ -z "$VARIANT" ]; then
  if [ -n "$DB_HOST" ] || [ -n "$DB_CONNECTION_STRING" ]; then
    VARIANT="separate"
  elif is_tty; then
    choice=""
    read -r -p "SQL Server location — [1] in Docker on this host (default), [2] external server: " choice
    case "$choice" in
      2) VARIANT="separate" ;;
      *) VARIANT="single" ;;
    esac
  else
    VARIANT="single"
  fi
fi
case "$VARIANT" in
  single|separate) ;;
  *) err "--variant must be 'single' or 'separate'." ;;
esac
log "Variant: $VARIANT"

# ---------------------------------------------------------------------------
# Resolve secrets
# ---------------------------------------------------------------------------
prompt_value ADMIN_PASSWORD "Admin account password" true

if [ "$VARIANT" = "single" ]; then
  prompt_value DB_PASSWORD "Database (SA) password" true
  validate_mssql_password "$DB_PASSWORD"
else
  if [ -z "$DB_CONNECTION_STRING" ]; then
    prompt_value DB_HOST "External SQL Server host"
    prompt_value DB_PASSWORD "Database password" true
    [ -n "$DB_NAME" ] || DB_NAME="GeoSenEsm"
    DB_CONNECTION_STRING="jdbc:sqlserver://${DB_HOST}:1433;databaseName=${DB_NAME};trustServerCertificate=true;user=${DB_USER};password=${DB_PASSWORD};"
  fi
fi

if [ -z "$JWT_KEY" ]; then
  JWT_KEY="$(generate_secret)"
  log "Generated JWT_KEY (also saved in .env — back it up, rotating it invalidates all sessions)."
fi

if [ -n "$DOMAIN" ] && [ "$SKIP_TLS" != true ]; then
  prompt_value EMAIL "Email for Let's Encrypt renewal notices"
fi

# ---------------------------------------------------------------------------
# Docker checks
# ---------------------------------------------------------------------------
if ! require_cmd docker; then
  if [ "$INSTALL_DOCKER" = true ]; then
    log "Docker not found — installing via get.docker.com ..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable --now docker || true
    sudo usermod -aG docker "$USER" || true
    warn "Added $USER to the 'docker' group — log out/in (or run 'newgrp docker') for it to take effect in this shell."
  else
    err "Docker is not installed. Install it (see https://docs.docker.com/engine/install/) or re-run with --install-docker."
  fi
fi

DOCKER="docker"
if ! docker version >/dev/null 2>&1; then
  DOCKER="sudo docker"
  $DOCKER version >/dev/null 2>&1 || err "Cannot run docker (even with sudo). Check the Docker install / your permissions."
fi
$DOCKER compose version >/dev/null 2>&1 || err "Docker Compose plugin not found (need 'docker compose', not the standalone 'docker-compose')."

# ---------------------------------------------------------------------------
# Write deploy directory: compose file, data dirs, .env
# ---------------------------------------------------------------------------
mkdir -p "$DEPLOY_DIR"
log "Deploy directory: $DEPLOY_DIR"

if [ "$VARIANT" = "single" ]; then
  mkdir -p "$DEPLOY_DIR/mssql-data" "$DEPLOY_DIR/mongo-data"
  chmod 777 "$DEPLOY_DIR/mssql-data" "$DEPLOY_DIR/mongo-data"

  cat > "$DEPLOY_DIR/docker-compose.yml" <<'COMPOSE_EOF'
services:
  database:
    image: mcr.microsoft.com/mssql/server:2019-latest
    pull_policy: always
    environment:
      ACCEPT_EULA: Y
      MSSQL_SA_PASSWORD: ${DATABASE_PASSWORD}
      MSSQL_PID: Express
    volumes:
      - ./mssql-data:/var/opt/mssql
    restart: unless-stopped

  db-init:
    image: mcr.microsoft.com/mssql-tools
    depends_on:
      - database
    entrypoint: /bin/bash -c "
      sleep 10;
      /opt/mssql-tools/bin/sqlcmd -S database -U sa -P '${DATABASE_PASSWORD}' -Q \"IF DB_ID('GeoSenEsm') IS NULL CREATE DATABASE GeoSenEsm;\""

  mongo:
    image: mongo:7.0
    volumes:
      - ./mongo-data:/data/db
    restart: unless-stopped

  api:
    image: ghcr.io/geosenesm/survey-api:prod
    pull_policy: always
    ports:
      - "${API_PORT:-8083}:8080"
    depends_on:
      - db-init
      - mongo
    environment:
      SPRING_DATASOURCE_URL: jdbc:sqlserver://database:1433;databaseName=GeoSenEsm;trustServerCertificate=true;encrypt=false;user=sa;password=${DATABASE_PASSWORD};
      SPRING_DATASOURCE_USER: sa
      SPRING_DATASOURCE_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_USER: sa
      SPRING_DATA_MONGODB_URI: mongodb://mongo:27017/GeoSenEsm
      SPRING_DATA_MONGODB_DATABASE: GeoSenEsm
      ADMIN_USER_PASSWORD: ${ADMIN_USER_PASSWORD}
      JWT_KEY: ${JWT_KEY}
      JWT_EXPIRATION: ${JWT_EXPIRATION:-180}
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS:-*}
    volumes:
      - imagevolume:/uploads
    restart: unless-stopped

  admin-panel:
    image: ghcr.io/geosenesm/survey-admin-panel:prod
    pull_policy: always
    depends_on:
      - api
    environment:
      API_URL: ${API_URL}
    ports:
      - "${ADMIN_PORT:-8084}:80"
    restart: unless-stopped

volumes:
  imagevolume:
COMPOSE_EOF
else
  cat > "$DEPLOY_DIR/docker-compose.yml" <<'COMPOSE_EOF'
services:
  mongo:
    image: mongo:7.0
    volumes:
      - mongo-data:/data/db
    restart: unless-stopped

  api:
    image: ghcr.io/geosenesm/survey-api:prod
    pull_policy: always
    depends_on:
      - mongo
    ports:
      - "${API_PORT:-8083}:8080"
    environment:
      SPRING_DATASOURCE_URL: ${DATABASE_CONNECTION_STRING}
      SPRING_DATASOURCE_USER: ${DATABASE_USER}
      SPRING_DATASOURCE_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_USER: ${DATABASE_USER}
      SPRING_DATA_MONGODB_URI: mongodb://mongo:27017/GeoSenEsm
      SPRING_DATA_MONGODB_DATABASE: GeoSenEsm
      ADMIN_USER_PASSWORD: ${ADMIN_USER_PASSWORD}
      JWT_KEY: ${JWT_KEY}
      JWT_EXPIRATION: ${JWT_EXPIRATION:-180}
      ALLOWED_ORIGINS: ${ALLOWED_ORIGINS:-*}
    volumes:
      - imagevolume:/uploads
    restart: unless-stopped

  admin-panel:
    image: ghcr.io/geosenesm/survey-admin-panel:prod
    pull_policy: always
    depends_on:
      - api
    environment:
      API_URL: ${API_URL}
    ports:
      - "${ADMIN_PORT:-8084}:80"
    restart: unless-stopped

volumes:
  mongo-data:
  imagevolume:
COMPOSE_EOF
fi

ENV_FILE="$DEPLOY_DIR/.env"
{
  echo "# Generated by deploy.sh on $(date -u +%FT%TZ) — treat as a secret, do not commit."
  echo "JWT_KEY=${JWT_KEY}"
  echo "JWT_EXPIRATION=${JWT_EXPIRATION}"
  echo "ADMIN_USER_PASSWORD=${ADMIN_PASSWORD}"
  echo "API_URL=${API_URL}"
  echo "API_PORT=${API_PORT}"
  echo "ADMIN_PORT=${ADMIN_PORT}"
  [ -n "$ALLOWED_ORIGINS" ] && echo "ALLOWED_ORIGINS=${ALLOWED_ORIGINS}"
  echo "DATABASE_PASSWORD=${DB_PASSWORD}"
  if [ "$VARIANT" = "separate" ]; then
    echo "DATABASE_USER=${DB_USER}"
    echo "DATABASE_CONNECTION_STRING=${DB_CONNECTION_STRING}"
  fi
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
log "Wrote $ENV_FILE and docker-compose.yml"

# ---------------------------------------------------------------------------
# Nginx + TLS (domain only)
# ---------------------------------------------------------------------------
if [ -n "$DOMAIN" ] && [ "$SKIP_NGINX" != true ]; then
  if ! require_cmd nginx; then
    if require_cmd apt-get; then
      log "Installing Nginx ..."
      sudo apt-get update -y && sudo apt-get install -y nginx
    else
      warn "Nginx not found and apt-get unavailable — skipping Nginx setup. Configure a reverse proxy manually (see README.md)."
      SKIP_NGINX=true
    fi
  fi
fi

if [ -n "$DOMAIN" ] && [ "$SKIP_NGINX" != true ]; then
  sudo mkdir -p /var/www/html/privacy-policy

  NGINX_CONF=$(mktemp)
  cat > "$NGINX_CONF" <<'NGINX_EOF'
server {
    listen 80;
    server_name __API_DOMAIN__;

    location / {
        proxy_pass http://127.0.0.1:__API_PORT__;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /privacy-policy/ {
        root /var/www/html;
        try_files $uri $uri/ =404;
    }
}

server {
    listen 80;
    server_name __ADMIN_DOMAIN__;

    location / {
        proxy_pass http://127.0.0.1:__ADMIN_PORT__;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /privacy-policy/ {
        root /var/www/html;
        try_files $uri $uri/ =404;
    }
}
NGINX_EOF
  sed -i \
    -e "s/__API_DOMAIN__/${API_DOMAIN}/g" \
    -e "s/__ADMIN_DOMAIN__/${ADMIN_DOMAIN}/g" \
    -e "s/__API_PORT__/${API_PORT}/g" \
    -e "s/__ADMIN_PORT__/${ADMIN_PORT}/g" \
    "$NGINX_CONF"

  sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  sudo cp "$NGINX_CONF" /etc/nginx/sites-available/geosenesm
  rm -f "$NGINX_CONF"
  sudo ln -sf /etc/nginx/sites-available/geosenesm /etc/nginx/sites-enabled/geosenesm

  if ! sudo grep -q 'connection_upgrade' /etc/nginx/nginx.conf 2>/dev/null; then
    MAP_SNIPPET=$(mktemp)
    cat > "$MAP_SNIPPET" <<'MAP_EOF'
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }
MAP_EOF
    sudo sed -i "/http {/r $MAP_SNIPPET" /etc/nginx/nginx.conf
    rm -f "$MAP_SNIPPET"
  fi

  sudo nginx -t && sudo nginx -s reload 2>/dev/null || sudo systemctl reload nginx || sudo systemctl restart nginx
  log "Nginx configured for ${API_DOMAIN} and ${ADMIN_DOMAIN} (proxying to ports ${API_PORT}/${ADMIN_PORT})."

  if [ "$SKIP_TLS" != true ]; then
    if ! require_cmd certbot; then
      if require_cmd apt-get; then
        log "Installing certbot ..."
        sudo apt-get update -y && sudo apt-get install -y certbot python3-certbot-nginx
      else
        warn "certbot not found and apt-get unavailable — skipping TLS. Run certbot manually later."
        SKIP_TLS=true
      fi
    fi
  fi

  if [ "$SKIP_TLS" != true ]; then
    log "Requesting Let's Encrypt certificate for ${API_DOMAIN} and ${ADMIN_DOMAIN} ..."
    sudo certbot --nginx -d "$API_DOMAIN" -d "$ADMIN_DOMAIN" -m "$EMAIL" --agree-tos --non-interactive --redirect \
      || warn "certbot failed — check DNS for ${API_DOMAIN}/${ADMIN_DOMAIN} point at this server, then re-run: sudo certbot --nginx -d ${API_DOMAIN} -d ${ADMIN_DOMAIN}"
  fi
fi

# ---------------------------------------------------------------------------
# Start the stack
# ---------------------------------------------------------------------------
cd "$DEPLOY_DIR"
if [ "$NO_PULL" != true ]; then
  log "Pulling images ..."
  $DOCKER compose pull
fi
log "Starting containers ..."
$DOCKER compose up -d

# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
if require_cmd curl; then
  log "Waiting for the API to become healthy on 127.0.0.1:${API_PORT} ..."
  ready=false
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${API_PORT}/actuator/health"; then
      ready=true
      break
    fi
    sleep 5
  done
  if [ "$ready" = true ]; then
    log "API is healthy."
  else
    warn "API did not report healthy within 2.5 minutes — check: $DOCKER compose -f '$DEPLOY_DIR/docker-compose.yml' logs -f api"
  fi
else
  warn "curl not found — skipping health check."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "Done."
echo
if [ -n "$DOMAIN" ]; then
  scheme="http"; [ "$SKIP_TLS" != true ] && scheme="https"
  echo "  Admin panel: ${scheme}://${ADMIN_DOMAIN}"
  echo "  API:         ${scheme}://${API_DOMAIN}"
else
  echo "  Admin panel: http://${IP}:${ADMIN_PORT}"
  echo "  API:         http://${IP}:${API_PORT}"
fi
echo "  Admin login: admin / <the --admin-password you provided>"
echo "  Deploy dir:  $DEPLOY_DIR  (docker-compose.yml, .env, data volumes)"
echo
echo "Day-2 commands (run from $DEPLOY_DIR):"
echo "  $DOCKER compose ps"
echo "  $DOCKER compose logs -f api"
echo "  $DOCKER compose pull && $DOCKER compose up -d   # upgrade to newer :prod images"
echo "  $DOCKER compose down                            # stop (keeps data)"
