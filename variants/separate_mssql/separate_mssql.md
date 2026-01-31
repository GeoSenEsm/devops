# Setup with separate MSSQL Server

## Create database

First, create a database on the MSSQL server, and prepare a valid connection string, for example: `jdbc:sqlserver://mymssqlserver:1433;databaseName=mydatabasename;trustServerCertificate=true;user=sa;password=P@ssword123;`. In the examples below we'll assume the connection string is provided in an environment variable named `DATABASE_CONNECTION_STRING`.

## Change to the directory where you want to place the Docker files (for example, your home directory)

```bash
cd ~
```

## Run docker compose

Create `docker-compose.yml` with the following content:

```yml
services:
  api:
    image: ghcr.io/geosenesm/survey-api:prod
    ports:
      - 8083:8080
    environment:
      SPRING_DATASOURCE_URL: ${DATABASE_CONNECTION_STRING}
      SPRING_DATASOURCE_USER: ${DATABASE_USER}
      SPRING_DATASOURCE_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_PASSWORD: ${DATABASE_PASSWORD}
      SPRING_FLYWAY_USER: ${DATABASE_USER}
      ADMIN_USER_PASSWORD: ${ADMIN_USER_PASSWORD:-qwerty}
      JWT_KEY: ${JWT_KEY}
      JWT_EXPIRATION: ${JWT_EXPIRATION}
    volumes:
      - imagevolume:/uploads

  admin-panel:
    image: ghcr.io/geosenesm/survey-admin-panel:prod
    depends_on: 
      - api
    environment:
      API_URL: ${API_URL:-http://localhost:8080}
    ports:
      - 8084:80

volumes:
  imagevolume:
```

### Ports

If needed, modify the `docker-compose.yml` file so that the services are redirected to proper external ports. By default, the ports are set to match the ports from the Nginx example configuration mentioned in the previous steps of the documentation.

### Environment variables

As you can see, there are some environment variables used in the `docker-compose.yml`. For each of them, you can read what it is responsible for in the appropriate repository, if you are interested:
- https://github.com/projekt-inzynierski/survey-api for the api service
- https://github.com/projekt-inzynierski/survey-admin-panel for the admin-panel service

Here, only required and most important ones are described

- `JWT_KEY`: this variable is used for generating a JWT token, it cannot be shared with anyone. The key should have at least 256 bits of length. You can for example use this website to generate the key: https://jwtsecrets.com/.
- `ADMIN_USER_PASSWORD`: set password for the administrator account (can be changed later in the system)
- `API_URL`: URL where the API (api service) will be available from the Internet. By default it is `http://localhost:8080`. This value will be used in the admin panel for making API requests. Replace with your api domain, e.g. `https://api.mydomain.com`.
- `DATABASE_USER`: your database user
- `DATABASE_PASSWORD`: password to your database
- `DATABASE_CONNECTION_STRING`: the database connection string (see the example above)

Place **all** of the environment variables in the `.env` file, in the same directory where you've placed `docker-compose.yml`.

Example `.env` file:
```txt
DATABASE_USER=sa
DATABASE_PASSWORD=mypsswd
```

### Start

Run
```bash
docker compose up
```

command. After a short time, the environment should be up.