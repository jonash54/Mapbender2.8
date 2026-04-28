#!/usr/bin/env bash
# Bootstraps Mapbender on first container start:
#   1. waits for postgres
#   2. creates DB + loads SQL bundle (the same files install.sh concatenates)
#   3. writes conf/mapbender.conf from -dist with env-var substitution
#   4. compiles .mo translations
#   5. fixes log/ and http/tmp/ permissions for www-data
# All steps are idempotent — re-running the container is safe.
set -euo pipefail

: "${DB_HOST:=db}"
: "${DB_PORT:=5432}"
: "${DB_NAME:=mapbender}"
: "${DB_USER:=mapbender}"
: "${DB_PASSWORD:=mapbender}"

REPO=/var/www/mapbender
CONF="$REPO/conf/mapbender.conf"
MARKER="$REPO/conf/.docker-initialised"

echo "[entrypoint] PHP $(php -r 'echo PHP_VERSION;')"

# 1. wait for postgres
echo "[entrypoint] waiting for postgres at $DB_HOST:$DB_PORT ..."
for i in $(seq 1 60); do
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c '\q' 2>/dev/null; then
        echo "[entrypoint] postgres is up"
        break
    fi
    sleep 1
done

# 2. create DB if missing and load schema/data
DB_EXISTS=$(PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" || true)

if [ "$DB_EXISTS" != "1" ]; then
    echo "[entrypoint] creating database $DB_NAME"
    PGPASSWORD="$DB_PASSWORD" createdb -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -E UTF-8 -T template0 "$DB_NAME"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS postgis;"

    echo "[entrypoint] loading schema and update chain (this can take a minute)"
    cd "$REPO/resources/db"
    DBE=UTF-8
    cat \
        pgsql/pgsql_schema_2.5.sql \
        pgsql/$DBE/pgsql_data_2.5.sql \
        pgsql/pgsql_serial_set_sequences_2.5.sql \
        pgsql/$DBE/update/update_2.5_to_2.5.1rc1_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.5.1rc1_to_2.5.1_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.5.1_to_2.6rc1_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.6rc1_to_2.6_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.6_to_2.6.1_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.6.1_to_2.6.2_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.6.2_to_2.7rc1_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.7rc1_to_2.7rc2_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.7.1_to_2.7.2_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.7.2_to_2.7.3_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.7.3_to_2.7.4_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.7.4_to_2.8_pgsql_$DBE.sql \
        pgsql/$DBE/update/update_2.8_pgsql_$DBE.sql \
        pgsql/pgsql_serial_set_sequences_2.7.sql \
        > /tmp/_install.sql
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -v ON_ERROR_STOP=0 -f /tmp/_install.sql > /tmp/install.log 2> /tmp/install.err || true
    rm -f /tmp/_install.sql
    echo "[entrypoint] SQL load finished (see /tmp/install.log and /tmp/install.err inside the container)"
else
    echo "[entrypoint] database $DB_NAME already exists - skipping schema load"
fi

# 3. mapbender.conf from -dist
if [ ! -f "$CONF" ]; then
    echo "[entrypoint] generating conf/mapbender.conf"
    sed \
        -e "s/%%DBSERVER%%/$DB_HOST/g" \
        -e "s/%%DBPORT%%/$DB_PORT/g" \
        -e "s/%%DBNAME%%/$DB_NAME/g" \
        -e "s/%%DBOWNER%%/$DB_USER/g" \
        -e "s/%%DBPASSWORD%%/$DB_PASSWORD/g" \
        "$REPO/conf/mapbender.conf-dist" > "$CONF"
fi

# 4. compile .mo translations (idempotent — overwrites in place)
if [ ! -f "$MARKER" ]; then
    echo "[entrypoint] compiling gettext .po -> .mo"
    for po in "$REPO"/resources/locale/*/LC_MESSAGES/Mapbender.po; do
        [ -f "$po" ] && msgfmt "$po" -o "${po%.po}.mo" || true
    done
fi

# 5. permissions
echo "[entrypoint] fixing permissions on log/ and http/tmp/"
mkdir -p "$REPO/log" "$REPO/http/tmp" "$REPO/http/print/tmp"
chown -R www-data:www-data "$REPO/log" "$REPO/http/tmp" "$REPO/http/print/tmp" "$REPO/conf"
chmod -R g+w "$REPO/log" "$REPO/http/tmp" "$REPO/http/print/tmp"

touch "$MARKER"

echo "[entrypoint] ready - handing off to: $*"
exec "$@"
