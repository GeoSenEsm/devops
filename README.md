# devops

Production deployment guides for the GeoSenEsm platform on Ubuntu. Covers
Docker Compose for `survey-api`, `survey-admin-panel`, and MongoDB (response
documents), Nginx reverse proxying, TLS (Let’s Encrypt), and privacy-policy
hosting for the mobile app.


|                   |                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------- |
| Role              | Server setup docs + Compose variants (not application source)                            |
| Host              | Ubuntu with Docker and Nginx                                                             |
| Container images  | `ghcr.io/geosenesm/survey-api:prod`, `ghcr.io/geosenesm/survey-admin-panel:prod`         |
| Host ports        | API `8083` → container `8080`; admin `8084` → container `80` (match the Nginx examples) |
| Domains (example) | `api.mydomain.com`, `admin.mydomain.com`                                                 |
| Product repos     | `survey-api`, `survey-admin-panel`, `mobile-app`                                         |


---

## Fast path (recommended)

`deploy.sh` automates everything below: it writes the right `docker-compose.yml`
and `.env` for your chosen variant, starts the containers, and — when you give
it a domain — configures Nginx and requests a Let's Encrypt certificate too.

```bash
git clone https://github.com/GeoSenEsm/devops.git
cd devops
chmod +x deploy.sh

# Domain + automatic TLS
./deploy.sh --domain example.com --email admin@example.com \
            --admin-password 'S3cretAdmin!' --db-password 'Str0ng!Passw0rd'

# Bare IP, no domain yet (services published directly on 8083/8084)
./deploy.sh --ip 203.0.113.10 \
            --admin-password 'S3cretAdmin!' --db-password 'Str0ng!Passw0rd'
```

Run it with no flags for an interactive walkthrough, or `./deploy.sh --help`
for every option (external SQL Server, custom ports, skipping Nginx/TLS,
installing Docker itself, etc.). It's safe to re-run — it only rewrites the
generated compose/.env files and re-applies `docker compose up -d`.

The manual, step-by-step version of the same process (useful to understand
what the script does, or to adapt it) is documented below.

---

## What you end up with

```
Internet
   │
   ├─ https://api.mydomain.com    ──Nginx──► 127.0.0.1:8083  (survey-api)
   │                              └── /privacy-policy/*  → /var/www/html/privacy-policy
   └─ https://admin.mydomain.com  ──Nginx──► 127.0.0.1:8084  (survey-admin-panel)

Docker (app host)
   ├─ api          (GHCR image)
   ├─ admin-panel  (GHCR image)
   ├─ mongo        (internal only — no published host port)
   └─ database     (optional — only in the single-server variant)
```

Mobile app respondents enter `https://api.mydomain.com` as `apiUrl` on login.

---

## Repository contents


| Path                              | Purpose                                                              |
| --------------------------------- | -------------------------------------------------------------------- |
| `README.md`                       | This file — full server runbook                                      |
| `deploy.sh`                       | Automated deploy: generates Compose/`.env`, starts Docker, configures Nginx + TLS |
| `variants/separate_mssql/`        | External SQL Server; MongoDB + API + admin in Docker on the app host |
| `variants/no_separate_mssql/`     | SQL Server + MongoDB + API + admin all in Docker on one VM           |
| `variants/*/docker-compose.yml`   | Compose files to copy onto the server                                |
| `variants/*/*.md`                 | Extra detail for that variant (same steps as below)                  |


```
devops/
├── README.md
├── deploy.sh
└── variants/
    ├── separate_mssql/
    │   ├── docker-compose.yml
    │   └── separate_mssql.md
    └── no_separate_mssql/
        ├── docker-compose.yml
        └── no_separate_mssql.md
```

---

## Prerequisites

Ubuntu server with:

* Docker Engine + Compose plugin
  ([install Docker on Ubuntu](https://www.datacamp.com/tutorial/install-docker-on-ubuntu))
* Nginx ([install guide](https://nginx.org/en/docs/install.html))
* A domain with two subdomains — this guide uses `api.mydomain.com` and
  `admin.mydomain.com`
* Outbound access to pull images from GHCR and (for the single-server
  variant) Microsoft Container Registry

Verify Docker:

```bash
sudo docker version
sudo docker compose version
```

If your user is in the `docker` group you can omit `sudo` below.

---

## 1. Domain and Nginx

1. **Point DNS** for both subdomains at the server’s public IP.

2. **Install and start Nginx**:

```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

3. **Publish privacy policy HTML**

   You are responsible for respondents’ data, so you must provide a privacy
   policy. Respondents accept it after their first login in the mobile app.
   Place language-specific HTML under `/var/www/html/privacy-policy`:

```bash
sudo mkdir -p /var/www/html/privacy-policy
# copy en.html, cn.html, pl.html into that directory
```

   | File      | Language                                      |
   | --------- | --------------------------------------------- |
   | `en.html` | English (fallback if a locale is missing)     |
   | `cn.html` | Chinese                                       |
   | `pl.html` | Polish                                        |

4. **Configure Nginx as reverse proxy**

   Copy the following into `/etc/nginx/sites-available/default`, replacing the
   example hostnames with yours.

```nginx
server {
    listen 80;
    server_name api.mydomain.com;

    # Nginx's own default (1M) is smaller than uploads the API itself accepts
    # (e.g. survey option images), so raise it here or every such upload gets
    # silently rejected with a 413 before it ever reaches the app.
    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:8083;
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
    server_name admin.mydomain.com;

    location / {
        proxy_pass http://127.0.0.1:8084;
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
```

5. **WebSocket upgrade map**

   Ensure the `http` block in `/etc/nginx/nginx.conf` includes:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

   Add it near the top of the `http` section if it is missing.

6. **Reload and verify Nginx**

```bash
sudo nginx -t
sudo nginx -s reload
sudo systemctl status nginx
```

7. **TLS with Let’s Encrypt**

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d api.mydomain.com -d admin.mydomain.com
```

---

## 2. Choose a Compose variant

| Variant | When to use | Guide |
| ------- | ----------- | ----- |
| **Single server** | One VM; SQL Server + MongoDB + API + admin in Docker | [§3a](#3a-single-server--sql-server-in-docker) |
| **Separate MSSQL** | SQL Server already runs elsewhere; Mongo + API + admin on this host | [§3b](#3b-separate-mssql-host) |

MongoDB runs in Docker on the app host in both variants and is **not**
published to the internet (no host port).

---

## 3a. Single server — SQL Server in Docker

### Steps

```bash
# 1. Get the Compose file onto the server
git clone https://github.com/GeoSenEsm/devops.git
cd devops/variants/no_separate_mssql

# Or: copy only the Compose file into a deploy directory
# mkdir -p ~/geosenesm && cp docker-compose.yml ~/geosenesm/ && cd ~/geosenesm

# 2. Persistent data directories (SQL + Mongo)
mkdir -p mssql-data mongo-data
sudo chmod 777 mssql-data mongo-data

# 3. Create .env next to docker-compose.yml (see example below)
nano .env

# 4. Pull images and start in the background
docker compose pull
docker compose up -d

# 5. Watch logs until the API is healthy
docker compose ps
docker compose logs -f api
```

Detach from logs with `Ctrl+C` (containers keep running).

### Example `.env`

```txt
JWT_KEY=replace_with_at_least_256_bit_secret
API_URL=https://api.mydomain.com
DATABASE_PASSWORD=Str0ng!Passw0rd
ADMIN_USER_PASSWORD=change_me
```

`DATABASE_PASSWORD` must meet SQL Server rules: at least 8 characters and
characters from three of: uppercase, lowercase, digits, symbols.

### Services started

| Service       | Image                                              | Host port | Notes                          |
| ------------- | -------------------------------------------------- | --------- | ------------------------------ |
| `database`    | `mcr.microsoft.com/mssql/server:2019-latest`       | —         | Data in `./mssql-data`         |
| `db-init`     | `mcr.microsoft.com/mssql-tools`                    | —         | Creates DB `GeoSenEsm` once    |
| `mongo`       | `mongo:7.0`                                        | —         | Data in `./mongo-data`         |
| `api`         | `ghcr.io/geosenesm/survey-api:prod`                | `8083`    | Talks to SQL + Mongo           |
| `admin-panel` | `ghcr.io/geosenesm/survey-admin-panel:prod`        | `8084`    | Uses `API_URL` from `.env`     |

Full Compose file: [`variants/no_separate_mssql/docker-compose.yml`](variants/no_separate_mssql/docker-compose.yml).

---

## 3b. Separate MSSQL host

### Before Compose

1. Create a database on your SQL Server.
2. Prepare a JDBC URL, for example:

```text
jdbc:sqlserver://mymssqlserver:1433;databaseName=mydatabasename;trustServerCertificate=true;user=sa;password=P@ssword123;
```

The app host must be able to reach that SQL Server on the network.

### Steps

```bash
# 1. Get the Compose file onto the server
git clone https://github.com/GeoSenEsm/devops.git
cd devops/variants/separate_mssql

# 2. Create .env next to docker-compose.yml (see example below)
nano .env

# 3. Pull images and start in the background
docker compose pull
docker compose up -d

# 4. Watch logs until the API is healthy
docker compose ps
docker compose logs -f api
```

### Example `.env`

```txt
DATABASE_USER=sa
DATABASE_PASSWORD=mypsswd
DATABASE_CONNECTION_STRING=jdbc:sqlserver://mymssqlserver:1433;databaseName=mydatabasename;trustServerCertificate=true;user=sa;password=mypsswd;
JWT_KEY=replace_with_at_least_256_bit_secret
JWT_EXPIRATION=180
API_URL=https://api.mydomain.com
ADMIN_USER_PASSWORD=change_me
```

### Services started

| Service       | Image                                       | Host port | Notes                                      |
| ------------- | ------------------------------------------- | --------- | ------------------------------------------ |
| `mongo`       | `mongo:7.0`                                 | —         | Named volume `mongo-data`                  |
| `api`         | `ghcr.io/geosenesm/survey-api:prod`         | `8083`    | SQL via `DATABASE_CONNECTION_STRING`       |
| `admin-panel` | `ghcr.io/geosenesm/survey-admin-panel:prod` | `8084`    | Uses `API_URL` from `.env`                 |

Full Compose file: [`variants/separate_mssql/docker-compose.yml`](variants/separate_mssql/docker-compose.yml).

---

## 4. Environment variables (common)

| Variable                   | Required | Purpose                                                                 |
| -------------------------- | -------- | ----------------------------------------------------------------------- |
| `JWT_KEY`                  | yes      | Signing key for JWTs (≥ 256 bits). Keep secret. ([generator](https://jwtsecrets.com/)) |
| `JWT_EXPIRATION`           | no       | Token lifetime in days (separate-MSSQL Compose reads it)                |
| `ADMIN_USER_PASSWORD`      | yes      | Initial admin password (changeable later in the app)                    |
| `API_URL`                  | yes      | Public API URL for the admin panel, e.g. `https://api.mydomain.com`     |
| `DATABASE_PASSWORD`        | yes      | SQL Server password                                                     |
| `DATABASE_USER`            | separate | SQL user (separate-MSSQL variant)                                       |
| `DATABASE_CONNECTION_STRING` | separate | Full JDBC URL (separate-MSSQL variant)                                |

Mongo is wired in Compose as `mongodb://mongo:27017/GeoSenEsm` — no Mongo
vars needed in `.env` unless you change that.

More detail: [survey-api](https://github.com/GeoSenEsm/survey-api) and
[survey-admin-panel](https://github.com/GeoSenEsm/survey-admin-panel) READMEs.

If GHCR images are private:

```bash
echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

---

## 5. Verify

```bash
# Containers running
docker compose ps

# API on the host (behind Nginx locally)
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8083/actuator/health

# Through Nginx / TLS (replace hostnames)
curl -sS -o /dev/null -w "%{http_code}\n" https://api.mydomain.com/actuator/health
curl -sS -o /dev/null -w "%{http_code}\n" https://admin.mydomain.com/
```

Then open `https://admin.mydomain.com` in a browser and sign in with the
admin password from `.env`. Point the mobile app’s login `apiUrl` at
`https://api.mydomain.com`.

---

## 6. Day-2 Docker commands

Run these from the directory that contains `docker-compose.yml` and `.env`.

```bash
# Status
docker compose ps

# Logs (all / one service)
docker compose logs -f
docker compose logs -f api

# Restart after .env or Compose edits
docker compose up -d

# Pull newer :prod images and recreate
docker compose pull
docker compose up -d

# Stop (keeps volumes / data dirs)
docker compose down

# Stop and remove named volumes (destructive — separate-MSSQL mongo-data, uploads)
# docker compose down -v
```

Uploaded survey images live in the Docker volume `imagevolume`. SQL data is
in `./mssql-data` (single-server) or on your external SQL host. Mongo data is
in `./mongo-data` (single-server) or the named volume `mongo-data`
(separate-MSSQL).

---

## Related repositories

| Repository | Role |
| ---------- | ---- |
| [GeoSenEsm/survey-api](https://github.com/GeoSenEsm/survey-api) | REST backend image source |
| [GeoSenEsm/survey-admin-panel](https://github.com/GeoSenEsm/survey-admin-panel) | Admin portal image source |
| [GeoSenEsm/mobile-app](https://github.com/GeoSenEsm/mobile-app) | Respondent app (points at your API URL) |
| [GeoSenEsm/.github](https://github.com/GeoSenEsm/.github) | Organization docs |
