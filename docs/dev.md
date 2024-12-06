# Development environment

This document describes how you can run the project in your local environment

## ATTENTION!!

The state of the application you run with this guide is the current `develop` branches state and should not be used on production. But this is very good to very quickly setup everything without need of any configuration. This can be used for quick tests, or for example when you develop some external application that communicates with the API (for example UrbEat mobile app) and want to have a real environment without need to pull and run REST API repository. 

## Steps

- download the `docker_composes/dev/docker-compose.yml` file from this repository
- open shell (bash on Linux, Powershell on Windows)
- navigate to the directory, where the downloaded file is located
- run `docker-compose -f docker-compose-dev.yml up`
- wait some time (should be up to a minute or two)
- admin panel is available under `80` port, API under `8080`

Note, that when you run this for the first time it may need some time to pull all the containers required. 

## Additional optional setup:

If you want, you can set `API_URL` environmental variable to configure api url different that `http://localhost:8080`:

```bash
export API_URL="<your endpoint>"
```