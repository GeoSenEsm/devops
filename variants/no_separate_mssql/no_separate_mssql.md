# Setup without separate MSSQL Server

## Create db data directory

Run

```bash
mkdir mssql-data
sudo chmod 777 mssql-data
```

## Run docker compose

Copy the `docker-compose.yml` file from the directory where this document is located to your server. Replace Docker image names with the actual names you used when building.

### Ports

If needed, modify the `docker-compose.yml` file so that the services are redirected to proper external ports. By default, the ports are set to match the ports from the Nginx example configuration mentioned in the previous steps of the documentation.

### Environment variables

As you can see, there are some environment variables used in the `docker-compose.yml`. For each of them, you can read what it is responsible for in the appropriate repository:
- https://github.com/GeoSenEsm/survey-api for the api service
- https://github.com/GeoSenEsm/survey-admin-panel for the admin-panel service

Here, only required and most important ones are described

- `JWT_KEY`: this variable is used for generating a JWT token, it cannot be shared with anyone
- `ADMIN_USER_PASSWORD`: password for the administrator account (can be changed later in the system)
- `API_URL`: URL where the API (api service) will be available from the Internet. By default it is `http://localhost:8080`. This value will be used in the admin panel for making API requests. Replace with your api domain, e.g. `https://api.mydomain.com`.
- `DATABASE_PASSWORD`: Password to the database

Place all of the environment variables in the `.env` file, in the same directory where you've placed `docker-compose.yml`.

Example `.env` file:
```txt
API_URL=https://api.mydomain.com
DATABASE_PASSWORD=mypsswd
```

### Start

Run
```bash
docker-compose up
```

command. After a short time, the environment should be up.
