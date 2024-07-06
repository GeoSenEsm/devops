# DevOps repository for the UrbEat survey project
This repository contains detailed instructions of how you can start:
- the REST API 
- admin panel

## Initial condictions

To successfully run the project your machine needs to meet these conditions:
- docker installed and running
- docker-compose installed (on Windows it is auto installed with Docker Desktop, on Linux it has to be installed separately)
- if you use Windows, you also need to have WSL, as all of the containers are on based on some Linux images

## Login to ghcr

To be able to pull proper docker images you need to be authenticated to GitHub Docker Container Registry. Therefore you need an access token (contact with organization owner to get one). If you have a token you can authenticate with:

```
docker login ghcr.io -u projekt-inzynierski -p <token>
```

where `<token>` is your access token.

For more details visit the `docs` directory in this repository