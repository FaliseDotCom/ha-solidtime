#!/usr/bin/env bash
# Starts the Solidtime app: PostgreSQL first, then the database migrations,
# then the Solidtime web server, scheduler and queue worker under supervisord.
# On SIGTERM or SIGINT, Solidtime is stopped before PostgreSQL so the database
# always shuts down cleanly.

set -euo pipefail

readonly OPTIONS_FILE=/data/options.json
readonly PG_BIN=/usr/lib/postgresql/17/bin
readonly PG_DATA_DIR=/data/postgres
readonly PG_SOCKET_DIR=/run/postgresql
readonly PG_CONFIG=/etc/solidtime/postgresql.conf
readonly PG_WAIT_SECONDS=60
readonly DB_NAME=solidtime
readonly DB_USER=solidtime
readonly SECRETS_DIR=/data/secrets
readonly APP_DIR=/var/www/html
readonly APP_STORAGE_DIR=/data/solidtime/storage
readonly APP_USER=laravel
readonly SUPERVISOR_CONFIG=/etc/solidtime/supervisord.conf
readonly MIN_PASSWORD_LENGTH=8
readonly DEFAULT_TRUSTED_PROXIES=127.0.0.1,172.30.32.0/23
readonly API_CLIENT_NAME=API
readonly DESKTOP_CLIENT_NAME=desktop
readonly DESKTOP_REDIRECT_URI=solidtime://oauth/callback
readonly EXTENSION_CLIENT_NAME=browser-extension
# The Firefox and Chrome extension IDs, from the upstream self-hosting guide.
readonly EXTENSION_REDIRECT_URIS=https://3369f72567118d8c03fb34880e9d6378d3b0c569.extensions.allizom.org/,https://hpanifeankiobmgbemnhjmhpjeebdhdd.chromiumapp.org/

PG_PID=0
APP_PID=0

log()
{
  echo "[solidtime-app] $*"
}

fatal()
{
  log "ERROR: $*" >&2
  exit 1
}

# Prints one option from the app configuration, or nothing when it is unset.
option()
{
  jq -r --arg key "$1" '.[$key] // empty' "$OPTIONS_FILE"
}

# Runs a command as the `laravel` user, keeping the exported environment.
as_app()
{
  HOME="$APP_DIR" setpriv --reuid="$APP_USER" --regid="$APP_USER" --init-groups -- "$@"
}

as_postgres()
{
  HOME="$PG_DATA_DIR" setpriv --reuid=postgres --regid=postgres --init-groups -- "$@"
}

artisan()
{
  ( cd "$APP_DIR" && as_app php artisan --no-interaction "$@" )
}

# Runs SQL as the PostgreSQL superuser over the local socket and prints the
# result unaligned, one row per line.
sql()
{
  local database="${2:-postgres}"
  as_postgres "$PG_BIN/psql" --host="$PG_SOCKET_DIR" --dbname="$database" \
    --no-psqlrc --quiet --tuples-only --no-align --set=ON_ERROR_STOP=1 --command="$1"
}

# Prints a quoted SQL string literal.
sql_literal()
{
  printf "'%s'" "${1//\'/\'\'}"
}

is_valid_email()
{
  [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]]
}

read_options()
{
  if [ ! -f "$OPTIONS_FILE" ]
  then
    fatal "$OPTIONS_FILE not found. This image must run as a Home Assistant app."
  fi

  APP_URL=$(option app_url)
  APP_URL="${APP_URL%/}"
  TRUSTED_HOSTS=$(option trusted_hosts)
  TRUSTED_PROXIES=$(option trusted_proxies)
  TRUSTED_PROXIES="${TRUSTED_PROXIES:-$DEFAULT_TRUSTED_PROXIES}"
  REGISTRATION=$(option registration)
  REGISTRATION="${REGISTRATION:-invite-only}"
  ADMIN_NAME=$(option admin_name)
  ADMIN_EMAIL=$(option admin_email)
  ADMIN_PASSWORD=$(option admin_password)
  SUPER_ADMINS=$(option super_admins)
  MAIL_HOST=$(option mail_host)
  MAIL_PORT=$(option mail_port)
  MAIL_ENCRYPTION=$(option mail_encryption)
  MAIL_USERNAME=$(option mail_username)
  MAIL_PASSWORD=$(option mail_password)
  MAIL_FROM_ADDRESS=$(option mail_from_address)
  GOTENBERG_URL=$(option gotenberg_url)

  if ! [[ "$APP_URL" =~ ^https?://[^/[:space:]]+$ ]]
  then
    fatal "app_url '$APP_URL' must be an address such as http://homeassistant.local:8000, without a path."
  fi

  if [ -n "$ADMIN_EMAIL" ] && ! is_valid_email "$ADMIN_EMAIL"
  then
    fatal "admin_email '$ADMIN_EMAIL' is not a valid email address."
  fi

  if [ -n "$ADMIN_PASSWORD" ] && [ "${#ADMIN_PASSWORD}" -lt "$MIN_PASSWORD_LENGTH" ]
  then
    fatal "admin_password must be at least $MIN_PASSWORD_LENGTH characters long."
  fi

  if [ -n "$MAIL_FROM_ADDRESS" ] && ! is_valid_email "$MAIL_FROM_ADDRESS"
  then
    fatal "mail_from_address '$MAIL_FROM_ADDRESS' is not a valid email address."
  fi
}

# Prints a secret, generating it with the given command on first start.
# Secrets live in /data, so they never have to appear in the app options.
secret()
{
  local file="$SECRETS_DIR/$1"
  shift

  if [ ! -s "$file" ]
  then
    ( umask 077 && "$@" > "$file.tmp" && mv "$file.tmp" "$file" )
  fi

  cat "$file"
}

# shellcheck disable=SC2329 # Invoked through secret.
generate_app_key()
{
  echo "base64:$( openssl rand -base64 32 )"
}

prepare_secrets()
{
  mkdir -p "$SECRETS_DIR"
  chmod 0700 "$SECRETS_DIR"

  # Laravel's encryption key; changing it would log everybody out and make
  # encrypted values unreadable.
  APP_KEY=$(secret app_key generate_app_key)
  # Signing keys for the API and OAuth tokens used by the desktop app and the
  # browser extension.
  PASSPORT_PRIVATE_KEY=$(secret oauth-private.key openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:4096)
  PASSPORT_PUBLIC_KEY=$(secret oauth-public.key openssl pkey -pubout -in "$SECRETS_DIR/oauth-private.key")
}

# Points Solidtime's file storage (avatars, imports, exports) at persistent
# storage. Caches and compiled views stay in the container.
prepare_storage()
{
  mkdir -p "$APP_STORAGE_DIR/app/public"
  chown -R "$APP_USER:$APP_USER" "$APP_STORAGE_DIR"

  rm -rf "$APP_DIR/storage/app"
  ln -s "$APP_STORAGE_DIR/app" "$APP_DIR/storage/app"
}

start_database()
{
  mkdir -p "$PG_DATA_DIR" "$PG_SOCKET_DIR"
  chown postgres:postgres "$PG_DATA_DIR" "$PG_SOCKET_DIR"
  chmod 0700 "$PG_DATA_DIR"

  if [ ! -s "$PG_DATA_DIR/PG_VERSION" ]
  then
    log "Initialising a new PostgreSQL data directory."
    # ICU's root collation sorts names the way people expect, independent of
    # the container's locale settings.
    as_postgres "$PG_BIN/initdb" --pgdata="$PG_DATA_DIR" --username=postgres \
      --encoding=UTF8 --locale-provider=icu --icu-locale=und --locale=C.UTF-8 \
      --auth-local=peer --auth-host=scram-sha-256 > /dev/null
  fi

  local data_version
  data_version=$(cat "$PG_DATA_DIR/PG_VERSION")
  if [ "$data_version" != "$("$PG_BIN/postgres" --version | sed -E 's/.* ([0-9]+)\..*/\1/')" ]
  then
    fatal "The database was created by PostgreSQL $data_version, which this app version cannot read. Restore a backup made with the previous app version, or see the Updates section of the documentation."
  fi

  # A stale lock file from a crash stops PostgreSQL from starting; nothing else
  # can be running on this data directory inside a fresh container.
  rm -f "$PG_DATA_DIR/postmaster.pid"

  log "Starting PostgreSQL."
  # A separate session keeps PostgreSQL out of the process group, so a stop
  # signal sent to the whole group cannot stop it before Solidtime.
  # It is started directly rather than through as_postgres, so that $! is the
  # PostgreSQL process itself and not a subshell.
  HOME="$PG_DATA_DIR" setsid setpriv --reuid=postgres --regid=postgres --init-groups --     "$PG_BIN/postgres" -D "$PG_DATA_DIR" -c config_file="$PG_CONFIG" &
  PG_PID=$!

  local waited=0
  until "$PG_BIN/pg_isready" --host="$PG_SOCKET_DIR" --username=postgres --quiet
  do
    if ! kill -0 "$PG_PID" 2> /dev/null
    then
      fatal "PostgreSQL failed to start. See the log above."
    fi

    if [ "$waited" -ge "$PG_WAIT_SECONDS" ]
    then
      fatal "PostgreSQL did not become ready within $PG_WAIT_SECONDS seconds."
    fi

    sleep 1
    waited=$(( waited + 1 ))
  done
}

stop_database()
{
  if [ "$PG_PID" -eq 0 ]
  then
    return
  fi

  log "Stopping PostgreSQL."
  # SIGINT is PostgreSQL's "fast" shutdown: it ends open sessions and writes a
  # clean checkpoint.
  kill -INT "$PG_PID" 2> /dev/null || true
  wait "$PG_PID" 2> /dev/null || true
  PG_PID=0
}

# Creates the Solidtime database and user on first start. The password is
# generated once and kept in /data.
prepare_database()
{
  DB_PASSWORD=$(secret db_password openssl rand -hex 24)

  if [ -z "$(sql "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER';")" ]
  then
    sql "CREATE ROLE $DB_USER LOGIN;"
  fi

  sql "ALTER ROLE $DB_USER PASSWORD $(sql_literal "$DB_PASSWORD");"

  if [ -z "$(sql "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME';")" ]
  then
    log "Creating the Solidtime database."
    sql "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  fi

  refresh_collation
}

# After an update that brings a new ICU library, indexes on text columns may
# sort differently than before. Rebuilding them and recording the new version
# is the fix PostgreSQL recommends, and is quick for a database this size.
refresh_collation()
{
  local mismatch
  mismatch=$(sql "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME' AND datcollversion IS DISTINCT FROM pg_database_collation_actual_version( oid );")

  if [ -z "$mismatch" ]
  then
    return
  fi

  log "The collation library changed; rebuilding the database indexes."
  sql "REINDEX DATABASE $DB_NAME;" "$DB_NAME"
  sql "ALTER DATABASE $DB_NAME REFRESH COLLATION VERSION;" > /dev/null
}

# Exports the Solidtime configuration. Everything in /var/www/html/.env from
# the image is overridden here, because real environment variables win.
export_environment()
{
  local force_https=false
  if [[ "$APP_URL" == https://* ]]
  then
    force_https=true
  fi

  export APP_URL APP_KEY PASSPORT_PRIVATE_KEY PASSPORT_PUBLIC_KEY TRUSTED_PROXIES SUPER_ADMINS
  export APP_ENV=production APP_DEBUG=false APP_FORCE_HTTPS="$force_https"
  export APP_ENABLE_REGISTRATION="$REGISTRATION"
  export TRUSTED_HOSTS="${TRUSTED_HOSTS// /}"
  export LOG_CHANNEL=stderr LOG_LEVEL=warning
  export DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_PORT=5432 DB_SSLMODE=disable
  export DB_DATABASE="$DB_NAME" DB_USERNAME="$DB_USER" DB_PASSWORD
  export QUEUE_CONNECTION=database FILESYSTEM_DISK=local PUBLIC_FILESYSTEM_DISK=public
  export MAIL_FROM_NAME=Solidtime MAIL_FROM_ADDRESS="${MAIL_FROM_ADDRESS:-solidtime@localhost}"

  if [ -n "$MAIL_HOST" ]
  then
    export MAIL_MAILER=smtp MAIL_HOST MAIL_PORT="${MAIL_PORT:-587}"
    export MAIL_USERNAME MAIL_PASSWORD
    if [ "${MAIL_ENCRYPTION:-tls}" = none ]
    then
      export MAIL_ENCRYPTION=null
    else
      export MAIL_ENCRYPTION="${MAIL_ENCRYPTION:-tls}"
    fi
  else
    # Without a mail server, emails such as invitations end up in the log.
    export MAIL_MAILER=log
  fi

  if [ -n "$GOTENBERG_URL" ]
  then
    export GOTENBERG_URL
  fi
}

# Brings the database schema up to date and rebuilds Laravel's caches, the same
# steps the upstream image runs on start.
prepare_app()
{
  log "Running database migrations."
  artisan migrate --force --isolated
  artisan storage:link --force > /dev/null
  artisan optimize:clear > /dev/null
  artisan optimize > /dev/null
}

user_count()
{
  sql "SELECT COUNT(*) FROM users WHERE is_placeholder = false;" "$DB_NAME"
}

# Solidtime does not allow sign-up by default, so a fresh install without
# administrator credentials would leave nobody able to log in.
create_admin_on_first_start()
{
  if [ "$(user_count)" -gt 0 ]
  then
    return
  fi

  if [ "$REGISTRATION" = on ] && { [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; }
  then
    log "No users exist yet. Registration is on: create the first account on the sign-up page."
    return
  fi

  if [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]
  then
    stop_database
    fatal "No Solidtime users exist yet. Set admin_email and admin_password in the app configuration, then start the app again."
  fi

  log "First start: creating the account '$ADMIN_EMAIL'."
  # The command reads the password from standard input; SHELL_INTERACTIVE lets
  # it ask although no terminal is attached.
  printf '%s\n' "$ADMIN_PASSWORD" | ( cd "$APP_DIR" && SHELL_INTERACTIVE=1 as_app php artisan admin:user:create \
    "${ADMIN_NAME:-Administrator}" "$ADMIN_EMAIL" --ask-for-password --verify-email > /dev/null )

  apply_admin_timezone
}

# The create command always uses UTC; switch the new account to the Home
# Assistant time zone (passed in as TZ) so its times show correctly right away.
apply_admin_timezone()
{
  if [ -z "${TZ:-}" ]
  then
    return
  fi

  if ! php -r 'exit( in_array( getenv( "TZ" ), timezone_identifiers_list(), true ) ? 0 : 1 );'
  then
    log "Ignoring unknown time zone '$TZ'; the account keeps using UTC."
    return
  fi

  sql "UPDATE users SET timezone = $(sql_literal "$TZ") WHERE email = $(sql_literal "$ADMIN_EMAIL") AND is_placeholder = false;" "$DB_NAME" > /dev/null
  log "Time zone of '$ADMIN_EMAIL': $TZ"
}

# Prints the ID of the OAuth client with the given name, or nothing.
oauth_client_id()
{
  sql "SELECT id FROM oauth_clients WHERE name = $(sql_literal "$1") AND revoked = false ORDER BY created_at LIMIT 1;" "$DB_NAME"
}

# Creates a public OAuth client on first start, and logs its ID on every start
# so it can be entered in the client's instance settings.
ensure_public_client()
{
  local name="$1"
  local redirect_uris="$2"
  local label="$3"

  if [ -z "$(oauth_client_id "$name")" ]
  then
    log "Creating the OAuth client for the $label."
    artisan passport:client --public --name="$name" --redirect_uri="$redirect_uris" > /dev/null
  fi

  log "Client ID for the $label: $(oauth_client_id "$name")"
}

# Creates the OAuth clients that the upstream guide has you create by hand: one
# for API tokens on the profile page, and one each for the desktop app and the
# browser extensions.
ensure_oauth_clients()
{
  if [ -z "$(oauth_client_id "$API_CLIENT_NAME")" ]
  then
    log "Creating the OAuth client for API tokens."
    artisan passport:client --personal --name="$API_CLIENT_NAME" > /dev/null
  fi

  ensure_public_client "$DESKTOP_CLIENT_NAME" "$DESKTOP_REDIRECT_URI" "desktop app"
  ensure_public_client "$EXTENSION_CLIENT_NAME" "$EXTENSION_REDIRECT_URIS" "browser extension"
}

start_app()
{
  log "Starting Solidtime at $APP_URL"
  /usr/bin/supervisord --configuration "$SUPERVISOR_CONFIG" &
  APP_PID=$!
}

# shellcheck disable=SC2329 # Invoked through the trap set in main.
shutdown()
{
  # Ignore repeated stop signals so the shutdown runs only once.
  trap '' TERM INT
  log "Shutting down."

  if [ "$APP_PID" -ne 0 ]
  then
    kill -TERM "$APP_PID" 2> /dev/null || true
    wait "$APP_PID" 2> /dev/null || true
  fi

  stop_database
  exit 0
}

# Waits until either process exits. If one of them stops on its own, the other
# is stopped too and the app exits with an error, so the watchdog can restart it.
supervise()
{
  wait -n "$APP_PID" "$PG_PID" || true

  if ! kill -0 "$PG_PID" 2> /dev/null
  then
    PG_PID=0
    log "PostgreSQL stopped unexpectedly."
  else
    log "Solidtime stopped unexpectedly."
  fi

  kill -TERM "$APP_PID" 2> /dev/null || true
  wait "$APP_PID" 2> /dev/null || true
  stop_database
  exit 1
}

main()
{
  read_options
  prepare_secrets
  prepare_storage
  trap shutdown TERM INT
  start_database
  prepare_database
  export_environment
  prepare_app
  create_admin_on_first_start
  ensure_oauth_clients
  start_app
  supervise
}

main "$@"
