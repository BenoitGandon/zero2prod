@echo off
setlocal

REM Check if a custom parameter has been set, otherwise use default values
set "DB_PORT=%POSTGRES_PORT%"
if not defined DB_PORT set "DB_PORT=5432"
set "SUPERUSER=%SUPERUSER%"
if not defined SUPERUSER set "SUPERUSER=postgres"
set "SUPERUSER_PWD=%SUPERUSER_PWD%"
if not defined SUPERUSER_PWD set "SUPERUSER_PWD=password"
set "APP_USER=%APP_USER%"
if not defined APP_USER set "APP_USER=app"
set "APP_USER_PWD=%APP_USER_PWD%"
if not defined APP_USER_PWD set "APP_USER_PWD=secret"
set "APP_DB_NAME=%APP_DB_NAME%"
if not defined APP_DB_NAME set "APP_DB_NAME=newsletter"

REM Allow to skip Docker if a dockerized Postgres database is already running
if "%~1"=="" (
    REM Launch postgres using Docker
    set "CONTAINER_NAME=postgres"
    docker run ^
    --env POSTGRES_USER=%SUPERUSER% ^
    --env POSTGRES_PASSWORD=%SUPERUSER_PWD% ^
    --publish %DB_PORT%:5432 ^
    --detach ^
    --name "%CONTAINER_NAME%" ^
    postgres -N 1000
    REM ^ Increased maximum number of connections for testing purposes

    REM Wait for Postgres to be ready to accept connections
    :check_postgres
    for /f "tokens=*" %%i in ('docker inspect -f "{{.State.Status}}" %CONTAINER_NAME%') do (
        set "STATUS=%%i"
    )
    if "%STATUS%"=="running" (
        echo Postgres is up and running on port %DB_PORT%!
    ) else (
        >&2 echo Postgres is still unavailable - sleeping
        timeout /t 1 >nul
        goto check_postgres
    )

    REM Create the application user
    set "CREATE_QUERY=CREATE USER %APP_USER% WITH PASSWORD '%APP_USER_PWD%';"
    docker exec -it "%CONTAINER_NAME%" psql -U "%SUPERUSER%" -c "%CREATE_QUERY%"

    REM Grant create db privileges to the app user
    set "GRANT_QUERY=ALTER USER %APP_USER% CREATEDB;"
    docker exec -it "%CONTAINER_NAME%" psql -U "%SUPERUSER%" -c "%GRANT_QUERY%"
)

echo Running migrations ...
REM Create the application database
set "DATABASE_URL=postgres://%APP_USER%:%APP_USER_PWD%@localhost:%DB_PORT%/%APP_DB_NAME%"
sqlx database create
sqlx migrate run
echo "Postgres has been migrated, ready to go!"

endlocal
