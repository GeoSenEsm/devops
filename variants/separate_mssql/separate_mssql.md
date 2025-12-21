# Setup with separate MSSQL Server

## Create database

First, create a database on the MSSQL server, and prepare a valid connection string, for example: `jdbc:sqlserver://mymssqlserver:1433;databaseName=mydatabasename;trustServerCertificate=true;user=sa;password=P@ssword123;`. In further steps, we'll assume the connection string is `DB_CONNECTION`.

## Run docker compose

Now, you're ready to run Docker Compose.

Copy the `docker-compose.yml` file from the directory where this document is located to your server. Replace Docker image names with the actual names you used when building.

### Ports

If needed, modify the `docker-compose.yml` file so that the services are redirected to proper external ports. By default, the ports are set to match the ports from the Nginx example configuration mentioned in the previous steps of the documentation.

### Environment variables

As you can see, there are some environment variables used in the `docker-compose.yml`. For each of them, you can read what it is responsible for in the appropriate repository:
- https://github.com/projekt-inzynierski/survey-api for the api service
- https://github.com/projekt-inzynierski/survey-admin-panel for the admin-panel service

Here, only required and most important ones are described

- `JWT_KEY`: this variable is used for generating a JWT token, it cannot be shared with anyone
- `ADMIN_USER_PASSWORD`: password for the administrator account (can be changed later in the system)
- `API_URL`: URL where the API (api service) will be available from the Internet. By default it is `http://localhost:8080`. This value will be used in the admin panel for making API requests. Replace with your api domain, e.g. `https://api.mydomain.com`.
- `DATABASE_USER`: your database user
- `DATABASE_PASSWORD`: Password to the database
- `DATABASE_CONNECTION_STRING`: `DB_CONNECTION` value

Place all of the environment variables in the `.env` file, in the same directory where you've placed `docker-compose.yml`.

Example `.env` file:
```txt
DATABASE_USER=sa
DATABASE_PASSWORD=mypsswd
```

### Start

Run
```bash
docker-compose up
```

command. After a short time, the environment should be up.