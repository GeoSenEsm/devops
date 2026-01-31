# Setup without separate MSSQL Server

## Go to location you want to place the docker file in, for example home directory

```bash
cd ~
```

## Create db data directory

Run

```bash
mkdir mssql-data
sudo chmod 777 mssql-data
```

## Run docker compose

Create `docker-compose.yml` with the following content:

```yml
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

  db-init:
    image: mcr.microsoft.com/mssql-tools
    depends_on:
      - database
    entrypoint: /bin/bash -c "
      sleep 10;
      /opt/mssql-tools/bin/sqlcmd -S database -U sa -P '${DATABASE_PASSWORD}' -Q \"IF DB_ID('GeoSenEsm') IS NULL CREATE DATABASE GeoSenEsm;\""

  api:
    image: ghcr.io/geosenesm/survey-api:prod
    pull_policy: always
    ports:
      - 8083:8080
    depends_on:
      - db-init
    environment:
      SPRING_DATASOURCE_URL: jdbc:sqlserver://database:1433;databaseName=GeoSenEsm;trustServerCertificate=true;encrypt=false;user=sa;password=${DATABASE_PASSWORD};
      SPRING_DATASOURCE_USER: sa
      SPRING_DATASOURCE_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_USER: sa
      ADMIN_USER_PASSWORD: ${ADMIN_USER_PASSWORD:-qwerty}
      JWT_KEY: ${JWT_KEY:-SOME_PRIVATE_KEY_DONT_SHARE}
    volumes:
      - imagevolume:/uploads
    env_file:
      - .env

  admin-panel:
    image: ghcr.io/geosenesm/survey-admin-panel:prod
    pull_policy: always
    depends_on:
      - api
    environment:
      API_URL: ${API_URL:-http://localhost:8080}
    ports:
      - 8084:80

volumes:
  mssql-data:
  imagevolume:
```

### Ports

If needed, modify the `docker-compose.yml` file so that the services are redirected to proper external ports. By default, the ports are set to match the ports from the Nginx example configuration mentioned in the previous steps of the documentation, so you don't have to change anything.

### Environment variables

As you can see, there are some environment variables used in the `docker-compose.yml`. For each of them, you can read what it is responsible for in the appropriate repository, if you are interested:
- https://github.com/projekt-inzynierski/survey-api for the api service
- https://github.com/projekt-inzynierski/survey-admin-panel for the admin-panel service

Here, only required and most important ones are described

- `JWT_KEY`: this variable is used for generating a JWT token, it cannot be shared with anyone. The key should have at least 256 bits of length. You can for example use this website to generate the key: https://jwtsecrets.com/.
- `ADMIN_USER_PASSWORD`: set password for the administrator account (can be changed later in the system)
- `API_URL`: URL where the API (api service) will be available from the Internet. By default it is `http://localhost:8080`. This value will be used in the admin panel for making API requests. Replace with your api domain, e.g. `https://api.mydomain.com`.
- `DATABASE_PASSWORD`: set password to the database. It has to meet MSSQL conditions: **"The password must be at least 8 characters long and contain characters from three of the following four sets: Uppercase letters, Lowercase letters, Base 10 digits, and Symbols."**

Place all of the environment variables in the `.env` file, in the same directory where you've placed `docker-compose.yml`.

Example `.env` file:
```txt
JWT_KEY=my_key
API_URL=https://api.mydomain.com
DATABASE_PASSWORD=my_database_password
ADMIN_USER_PASSWORD=my_admin_password
```

### Start

Run
```bash
docker compose up
```

command. After a short time, the environment should be up.