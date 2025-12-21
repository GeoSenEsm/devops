# DevOps repository for the GeoSenEsm system

This repository contains detailed instructions of how you can setup the production environment for:

* REST API
* Admin panel

## Initial conditions

To setup the environment in the most basic scenario, you need at least one server. It needs to meet these conditions:

* Docker installed and running ([installation guide](https://docs.docker.com/get-docker/))
* Docker Compose installed ([installation guide](https://docs.docker.com/compose/install/))
* Nginx installed ([installation guide](https://nginx.org/en/docs/install.html))
* You need to purchase a domain for your server. Ultimately, you need two subdomains for admin panel and API. In this document we'll assume your domains are `admin.mydomain.com` and `api.mydomain.com`.

> **Attention!** Newer versions of docker have build in `compose` command. Therefore, standalone installation of `Docker compose` is not required. In this case, you can just run `docker compose` instead of `docker-compose` anywhere in this documentation. 

## Setting up the domain and Nginx

1. **Configure your domain** to point to your server IP via DNS.
2. **Install and start Nginx**:

```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

3. **Add privacy policy to your server**

    You are responsible for managing your respondents' data, therefore you have to define your own privacy policy. Respondents will have to accept it after first login to the mobile app. Privacy policy should be added as html documents in `/var/www/html/privacy-policy`. Currently, three languages are supported: English, Chinease, Polish. This is because mobile app supports this three languages. Add `en.html`, `cn.html`or `pl.html` to your server in the location mentioned above. If you want to add privacy policy in another language, you can add it as `en.html`. It will be use as default, if no other will be found on the server. In the future, when the mobile app supports more languages, more privacy policies will be supported as well. 

5. **Configure Nginx to proxy requests**

Below you can find an example configuration file in `/etc/nginx/sites-available/default`

```nginx
# Redirect http to https

server {
    listen 80;
    server_name api.mydomain.com admin.mydomain.com www.api.mydomain.com www.admin.mydomain.com;

    return 301 https://$host$request_uri;
}

# api.mydomain.com domain configuration

server {
    listen 443 ssl;
    server_name api.mydomain.com api.mydomain.com;

    # SSL certificate paths
    ssl_certificate /etc/letsencrypt/live/api.mydomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.mydomain.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Redirection to the app listening on 8083 port
    location / {
        proxy_pass         http://127.0.0.1:8083;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection $connection_upgrade;
        proxy_set_header   Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Handle /privacy-policy
    location /privacy-policy {
        root /var/www/html;privacy-policy
        try_files $uri $uri/ =404;
    }

}

# admin.mydomain.com domain configuration

server {
    listen 443 ssl;
    server_name admin.mydomain.com admin.mydomain.com;

    # SSL certificate paths
    ssl_certificate /etc/letsencrypt/live/admin.mydomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/admin.mydomain.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Redirection to the app listening on 8084 port
    location / {
        proxy_pass         http://127.0.0.1:8084;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection $connection_upgrade;
        proxy_set_header   Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # Handle /privacy-policy
    location /privacy-policy {
        root /var/www/html;privacy-policy
        try_files $uri $uri/ =404;
    }

}

```

In the configuration file above, replace `api.mydomain.com` and `admin.mydomain.com` with your actual domains.

Reload Nginx to apply changes:

```bash
sudo nginx -s reload
```

5. **Verify Nginx is running**:

```bash
sudo systemctl status nginx
```

4. **Setup SSL with Let’s Encrypt**:

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d api.mydomain.com -d admin.mydomain.com
```

## Docker images

Docker images for both REST API and the Admin panel need to be built from their respective repositories:

* [Admin panel](https://github.com/projekt-inzynierski/survey-admin-panel)
* [API](https://github.com/projekt-inzynierski/survey-api)

Follow the instructions in each repository's README. Make sure the images are accessible on your server (e.g., via Docker registry). After this step, we assume the images are available as:

* `api-image`
* `admin-image`

## Environment setup

To setup the environment, follow the detailed instructions for the variant you're interested in:

1. [I have one server for the system and separate MSSQL server](variants/separate_mssql/separate_mssql.md)

2. [I only one server (no separate MSSQL server)](variants/no_separate_mssql/no_separate_mssql.md)