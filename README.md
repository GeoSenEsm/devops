# DevOps repository for the GeoSenEsm system
This repository contains detailed instructions of how you can setup the production environment for:
- the REST API 
- admin panel

## Initial condictions

To be able to setup the environment in most basic scenario, you need at least one server. It needs to meet these conditions:
- docker installed and running
- docker-compose installed

Also, we'll assume you already have properly configured network, certificates etc.

## Docker images

You need to build the docker images  for both REST API, and the administrator panel. To do so,
visit the repositories:
- [Admin panel](https://github.com/projekt-inzynierski/survey-admin-panel)
- [API](https://github.com/projekt-inzynierski/survey-api)

and follow the instructions in their `README` files. Also, you probably need to use some docker container registry, to be able to easily pull the built images on the server, where you want to setup the environment. In the further steps of the guid we'll assume, that the images are already built and pulled to the server with names:
- `api-image`
- `admin-image`

# Environment setup

To finally setup the environment, follow the detailed instructions for the variant you're interested in:
1. [I have one server for the system and separate MSSQL server](variants/separate_mssql//separate_mssql.md)