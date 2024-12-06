# Production and Testing Environment Setup

This document describes how to set up and run the production and test environments for the project using Docker Compose.

## Prerequisites

Before starting, make sure you have:

- Docker installed on your machine.
- Docker Compose installed.

## WARNING!!

The production services described here are intended for production-like environments. The test services (`test-api`, `test-admin-panel`, etc.) are specifically for creating test accounts for services like Google and Apple, which require test accounts to be created. These environments should **not** be used in production, except for testing and staging purposes.

### Key Environment Variables

1. **PRODUCTION_API_URL**:  
    This variable is used to define the URL that should point to the `production-api` service through the Nginx Proxy Manager. It must be configured so that the Nginx proxy correctly points to the `production-api`. Example:


    ```bash
    export PRODUCTION_API_URL="http://production-api.local"
    ```

2. **DATABASE_PASSWORD**:  
   This variable is used to set the password for the SQL Server databases. It's critical to set it correctly for both production and test environments. Example:

    ```bash
    export DATABASE_PASSWORD="your_secure_password"
    ```

3. **ADMIN_USER_PASSWORD**:  
   This is the password for the admin user in the production environment. Ensure you set it securely. Example:

    ```bash
    export ADMIN_USER_PASSWORD="your_admin_password"
    ```

4. **TEST_API_URL**:  
   This variable is used to define the URL for the `test-api` service. This URL will be used by the test admin panel to connect to the test API. If not provided, the default URL will be `http://localhost:8080`. Example:

    ```bash
    export TEST_API_URL="http://test-api.local"
    ```

## Steps to Run the Environment

1. Download the `docker-composes/production/docker-compose.yml` file from the repository.
2. Open a shell (bash on Linux, PowerShell on Windows).
3. Navigate to the directory where the `docker-compose.yml` file is located.
4. Run the following command to start all services:

    ```bash
    docker-compose up
    ```

5. The following services will be available:

   - **Nginx Proxy Manager**: Accessible on port 81 (to configure routing between services).
   - **Production API**: Accessible through the configured Nginx Proxy Manager.
   - **Production Admin Panel**: Accessible via the configured Nginx Proxy Manager routing.

   **Note**: When you first run this setup, Docker will pull all the necessary images, which may take some time.

## Configuration of Nginx Proxy Manager

The environment includes [Nginx Proxy Manager](https://nginxproxymanager.com/) to manage routing between the services. After starting the containers, you need to configure routing for the `production-api` and other services using the Nginx Proxy Manager UI.

## Test Services

The test services (`test-api`, `test-admin-panel`, and `test-database`) are used specifically for creating test accounts for services like Google and Apple, which require accounts to be created in the testing environment. These accounts are needed for tester-specific tasks (e.g., Google Play or Apple App Store testing).

## Privacy Policy

Place the privacy policy (or policies in different languages) in the `./privacy_policy` folder. It will be accessible under the same path in the `privacy-policy` service. Then, you can configure the redirection accordingly in the Nginx Proxy Manager.


### Test Environment Setup

You can access the test admin panel and API as follows:

- **Test API**: Accessible through the `test-api` service.
- **Test Admin Panel**: Accessible via the `test-admin-panel` service.

These services are isolated from the production environment, but they mirror the production API and database, allowing you to test specific actions, such as account creation, without impacting live data.

## Additional Configuration Notes

- **Volumes**: The services use Docker volumes for persistent data storage. These volumes are defined for the Nginx Proxy Manager, SQL Server databases, and API image uploads.
  
- **Nginx Proxy Manager Ports**: The Nginx Proxy Manager is configured to listen on the following ports:
  - **80**: HTTP
  - **443**: HTTPS
  - **81**: Admin interface for configuring routing.

  After starting the containers, you will need to log in to the Nginx Proxy Manager UI at `http://localhost:81` to configure the necessary proxy routes for your production and test APIs.

## Conclusion

This setup allows you to run both production and test environments for the project using Docker. You can configure routing for your services using Nginx Proxy Manager and easily switch between production and test APIs based on your needs.

For further details on how to use Nginx Proxy Manager, refer to the official [documentation](https://nginxproxymanager.com/).
