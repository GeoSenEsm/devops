# DevOps repository for the GeoSenEsm system

This repository contains detailed instructions on how to set up the production environment for:

* REST API
* Admin panel

on Ubuntu.

## Initial conditions

To set up the environment in the most basic scenario, you need at least one server (Ubuntu). It needs to meet these conditions:

* Docker installed and running ([installation guide](https://www.datacamp.com/tutorial/install-docker-on-ubuntu))
* Nginx installed ([installation guide](https://nginx.org/en/docs/install.html))
* You need to purchase a domain for your server. Ultimately, you need two subdomains for admin panel and API. In this document we'll assume your domains are `admin.mydomain.com` and `api.mydomain.com`.

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

    You are responsible for managing your respondents' data, therefore you must provide a privacy policy. Respondents will have to accept it after their first login to the mobile app. Add the privacy policy as HTML documents in `/var/www/html/privacy-policy`. Currently three languages are supported: English (`en.html`), Chinese (`cn.html`), and Polish (`pl.html`). If you do not provide a language-specific policy, the English version (`en.html`) will be used as the default. In the future, additional languages may be supported as the mobile app evolves.

4. **Configure Nginx to proxy requests**

    Copy the configuration below to `/etc/nginx/sites-available/default`, replacing `api.mydomain.com` and `admin.mydomain.com` with your actual domains.

```nginx
server {
    listen 80;
    server_name api.mydomain.com;

    location / {
        proxy_pass http://127.0.0.1:8083;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    location /privacy-policy {
        root /var/www/html/privacy-policy;
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

    location /privacy-policy {
        root /var/www/html/privacy-policy;
        try_files $uri $uri/ =404;
    }
}
```

5. **Ensure http mapping is present**

    Ensure that the `http` section in `/etc/nginx/nginx.conf` contains the following configuration:

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

    If not, add it at the top of the `http` section.

6. **Reload Nginx to apply changes**

```bash
sudo nginx -s reload
```

7. **Verify Nginx is running**

```bash
sudo systemctl status nginx
```

8. **Setup SSL with Let’s Encrypt**

    Remember to replace the domains.

```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d api.mydomain.com -d admin.mydomain.com
```

## Environment setup

To set up the environment, follow the detailed instructions for the variant you're interested in:

1. [I have one server for the system and a separate MSSQL server](variants/separate_mssql/separate_mssql.md)

2. [I have only one server (no separate MSSQL server)](variants/no_separate_mssql/no_separate_mssql.md)