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
# Several instances side by side on one host (each gets its own Compose
# project, deploy dir, Nginx site and image version):
#   ./deploy.sh --name prod --domain example.com ...
#   ./deploy.sh --name staging --api-tag test --admin-tag test \
#               --api-domain api-staging.example.com --admin-domain admin-staging.example.com \
#               --api-port 8093 --admin-port 8094 ...
# or all at once from a manifest (one line of flags per instance):
#   ./deploy.sh --instances instances.conf --email admin@example.com
#
# Simple mode — just list names; shop-api.example.com / shop-admin.example.com
# on ports 8083/8084, lab-api.example.com / lab-admin.example.com on 8085/8086:
#   ./deploy.sh --names shop,lab --domain example.com
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
NAME="geosenesm"
VARIANT=""
DOMAIN=""
API_DOMAIN=""
ADMIN_DOMAIN=""
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
API_TAG="prod"
ADMIN_TAG="prod"
DEPLOY_DIR=""
INSTANCES_FILE=""
INSTANCE_NAMES=""
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

Instance:
  --name NAME                Instance name (default: geosenesm). Used as the
                              Compose project name, the Nginx site name and the
                              default deploy dir. Give every instance on the
                              same host its own name and ports.
  --api-tag TAG              survey-api image tag, e.g. prod, test, v3.0.0
                              (default: prod).
  --admin-tag TAG            survey-admin-panel image tag (default: prod).
  --instances FILE           Deploy several instances in one run. Each
                              non-empty, non-# line of FILE holds the flags for
                              one instance and must include --name. Flags given
                              on the command line apply to every instance;
                              flags on a line override them.
  --names N1,N2,...          Simple mode: deploy one instance per name. With
                              --domain D they are served at N-api.D and
                              N-admin.D; with --ip on ports only. Ports count
                              up from --api-port: N1 gets 8083/8084, N2
                              8085/8086, and so on.

Target (pick one):
  --domain DOMAIN            Public domain, e.g. example.com. Creates
                              api.DOMAIN and admin.DOMAIN, sets up Nginx +
                              Let's Encrypt (unless --skip-nginx/--skip-tls).
  --api-domain HOST          Exact API hostname, e.g. api-test.example.com.
  --admin-domain HOST        Exact admin hostname. Pass both instead of
                              --domain, or one alongside it to override it.
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
                              (default: \$HOME/NAME).

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

validate_instance_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || err "Instance names must be lowercase letters, digits, '-' or '_' (got: $1)."
}

prompt_target() {
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
  if [ -n "$DOMAIN" ] && [ -n "$IP" ]; then
    err "Pass only one of --domain / --ip."
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
ALL_ARGS=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --api-tag) API_TAG="$2"; shift 2 ;;
    --admin-tag) ADMIN_TAG="$2"; shift 2 ;;
    --instances) INSTANCES_FILE="$2"; shift 2 ;;
    --names) INSTANCE_NAMES="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --api-domain) API_DOMAIN="$2"; shift 2 ;;
    --admin-domain) ADMIN_DOMAIN="$2"; shift 2 ;;
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
# Multi-instance mode: re-run this script once per instance line, taken from
# the --instances manifest or generated from --names
# ---------------------------------------------------------------------------
if [ -n "$INSTANCES_FILE" ] || [ -n "$INSTANCE_NAMES" ]; then
  if [ -n "$INSTANCES_FILE" ] && [ -n "$INSTANCE_NAMES" ]; then
    err "Pass only one of --instances / --names."
  fi

  common_args=()
  for ((i = 0; i < ${#ALL_ARGS[@]}; i++)); do
    case "${ALL_ARGS[$i]}" in
      --instances|--names) i=$((i + 1)) ;;
      *) common_args+=("${ALL_ARGS[$i]}") ;;
    esac
  done

  split_line() {
    # xargs splits on whitespace and honours quotes without evaluating anything.
    mapfile -t line_args < <(printf '%s\n' "$1" | xargs printf '%s\n')
    instance_name=""
    for ((i = 0; i < ${#line_args[@]} - 1; i++)); do
      if [ "${line_args[$i]}" = "--name" ]; then
        instance_name="${line_args[$((i + 1))]}"
      fi
    done
  }

  # Collect and validate every instance before deploying anything; reading the
  # manifest up front also keeps stdin free for interactive prompts.
  instance_lines=()
  if [ -n "$INSTANCES_FILE" ]; then
    [ -f "$INSTANCES_FILE" ] || err "Instances file not found: $INSTANCES_FILE"
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
      instance_lines+=("$line")
    done < "$INSTANCES_FILE"
  else
    for name in ${INSTANCE_NAMES//,/ }; do
      validate_instance_name "$name"
    done
    prompt_target
    if [ -n "$DOMAIN" ]; then
      if [ "$SKIP_TLS" != true ] && [ "$SKIP_NGINX" != true ]; then
        prompt_value EMAIL "Email for Let's Encrypt renewal notices"
        common_args+=(--email "$EMAIL")
      fi
    else
      common_args+=(--ip "$IP")
    fi
    port="$API_PORT"
    for name in ${INSTANCE_NAMES//,/ }; do
      target=""
      [ -z "$DOMAIN" ] || target="--api-domain ${name}-api.${DOMAIN} --admin-domain ${name}-admin.${DOMAIN}"
      instance_lines+=("--name $name $target --api-port $port --admin-port $((port + 1))")
      port=$((port + 2))
    done
  fi
  [ ${#instance_lines[@]} -gt 0 ] || err "No instances given."

  seen_names=" "
  for line in "${instance_lines[@]}"; do
    split_line "$line"
    [ -n "$instance_name" ] || err "Every instance needs --name: $line"
    [[ "$seen_names" == *" $instance_name "* ]] && err "Duplicate instance name: $instance_name"
    seen_names+="$instance_name "
  done

  succeeded=()
  failed=()
  for line in "${instance_lines[@]}"; do
    split_line "$line"
    log "=== Instance: $instance_name ==="
    if "$BASH" "$0" ${common_args[@]+"${common_args[@]}"} "${line_args[@]}"; then
      succeeded+=("$instance_name")
    else
      failed+=("$instance_name")
      warn "Instance $instance_name failed — continuing with the next one."
    fi
  done

  log "Instances deployed: ${succeeded[*]:-none}"
  [ ${#failed[@]} -eq 0 ] || err "Instances failed: ${failed[*]}"
  exit 0
fi

validate_instance_name "$NAME"
[ -n "$DEPLOY_DIR" ] || DEPLOY_DIR="${HOME:-.}/${NAME}"
[ "$API_PORT" != "$ADMIN_PORT" ] || err "--api-port and --admin-port must differ."
log "Instance: $NAME (survey-api:${API_TAG}, survey-admin-panel:${ADMIN_TAG})"

# ---------------------------------------------------------------------------
# Resolve target (domain vs IP)
# ---------------------------------------------------------------------------
if [ -z "$DOMAIN" ] && { [ -n "$API_DOMAIN" ] || [ -n "$ADMIN_DOMAIN" ]; }; then
  [ -n "$API_DOMAIN" ] && [ -n "$ADMIN_DOMAIN" ] || err "Without --domain, pass both --api-domain and --admin-domain."
  DOMAIN="$API_DOMAIN"
fi

prompt_target

if [ -n "$DOMAIN" ]; then
  API_DOMAIN="${API_DOMAIN:-api.${DOMAIN}}"
  ADMIN_DOMAIN="${ADMIN_DOMAIN:-admin.${DOMAIN}}"
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

if [ -z "$JWT_KEY" ] && [ -f "$DEPLOY_DIR/.env" ]; then
  # Reuse the key from a previous run — a new one would log out every respondent.
  JWT_KEY="$(sed -n 's/^JWT_KEY=//p' "$DEPLOY_DIR/.env")"
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

port_taken_by_other() {
  local port=$1
  require_cmd ss || return 1
  ss -ltnH "( sport = :$port )" | grep -q . || return 1
  ! $DOCKER ps --filter "label=com.docker.compose.project=$NAME" --format '{{.Ports}}' | grep -q ":$port->"
}
for port in "$API_PORT" "$ADMIN_PORT"; do
  if port_taken_by_other "$port"; then
    err "Port $port is already used by something other than instance '$NAME' — pick another with --api-port/--admin-port."
  fi
done

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
    image: ghcr.io/geosenesm/survey-api:${API_TAG:-prod}
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
    image: ghcr.io/geosenesm/survey-admin-panel:${ADMIN_TAG:-prod}
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
    image: ghcr.io/geosenesm/survey-api:${API_TAG:-prod}
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
    image: ghcr.io/geosenesm/survey-admin-panel:${ADMIN_TAG:-prod}
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
  echo "COMPOSE_PROJECT_NAME=${NAME}"
  echo "API_TAG=${API_TAG}"
  echo "ADMIN_TAG=${ADMIN_TAG}"
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

    # Nginx's own default (1M) is smaller than uploads the API itself accepts
    # (e.g. survey option images), so raise it here or every such upload gets
    # silently rejected with a 413 before it ever reaches the app.
    client_max_body_size 10M;

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
  sudo cp "$NGINX_CONF" "/etc/nginx/sites-available/${NAME}"
  rm -f "$NGINX_CONF"
  sudo ln -sf "/etc/nginx/sites-available/${NAME}" "/etc/nginx/sites-enabled/${NAME}"

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
echo "  Instance:    $NAME (survey-api:${API_TAG}, survey-admin-panel:${ADMIN_TAG})"
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
echo "  $DOCKER compose pull && $DOCKER compose up -d   # upgrade to newer :${API_TAG}/:${ADMIN_TAG} images"
echo "  $DOCKER compose down                            # stop (keeps data)"
