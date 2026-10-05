# Development

How the Solidtime app is put together, and how to test a change before it reaches users.

## Repository layout

```text
repository.yaml              App repository definition, read by the Supervisor
solidtime/
  config.yaml                App definition: version, port, options and schema
  Dockerfile                 Upstream Solidtime image plus jq and PostgreSQL 17
  run.sh                     Starts PostgreSQL and Solidtime, and stops them in order
  supervisord.conf           The web server, scheduler and queue worker
  postgresql.conf            PostgreSQL settings, tuned for small devices
  DOCS.md                    User documentation, shown on the Documentation tab
  README.md                  Short description, shown in the app store
  CHANGELOG.md               Release notes, shown when an update is available
  icon.png, logo.png         Artwork, taken from Solidtime's own favicon and logo
  translations/              Option names and descriptions (en, nl)
.devcontainer/, .vscode/     Home Assistant development environment
.docs/                       Documentation for contributors
scripts/update-solidtime.sh  Bumps the app to a new Solidtime release
```

## How the app works

The image extends the official [`solidtime/solidtime`](https://hub.docker.com/r/solidtime/solidtime)
image, pinned to an exact release, and adds PostgreSQL 17 from Debian. The upstream image is
a Laravel application served by Octane on FrankenPHP, and its Docker Compose setup runs the
same image three times, in `http`, `scheduler` and `worker` mode, next to a PostgreSQL
container. This app runs all of that in one container.

The Dockerfile switches back to `root` (upstream runs as `laravel`) and clears the upstream
`start-container` entrypoint. `run.sh` is the container command; Docker's `init` (enabled with
`init: true`) runs it as a child of a minimal init process, which forwards signals and reaps
zombies.

On start, `run.sh`:

1. Reads the options from `/data/options.json` with `jq`, and validates `app_url`, the
   administrator email and password length, and the sender address.
2. Generates the secrets on first start and keeps them in `/data/secrets`: Laravel's
   `APP_KEY`, the RSA key pair Passport signs API and OAuth tokens with, and the database
   password.
3. Replaces Solidtime's `storage/app` with a link to `/data/solidtime/storage/app`, so
   uploads such as profile pictures persist. Caches and compiled views stay in the
   container and are rebuilt on every start.
4. Starts PostgreSQL on `127.0.0.1:5432` with its data in `/data/postgres`, running
   `initdb` on first start. PostgreSQL runs in its own session (`setsid`), so a stop signal
   sent to the whole process group cannot stop it before Solidtime.
5. Creates the `solidtime` role and database, and rebuilds the indexes when the ICU
   collation version changed (see [Design decisions](#design-decisions)).
6. Exports Solidtime's configuration as environment variables. Real environment variables
   win over the `.env` file baked into the image.
7. Runs the steps the upstream entrypoint runs: `migrate --force --isolated`, then
   `storage:link`, `optimize:clear` and `optimize`. `optimize` caches the configuration,
   which is why commands run later with `docker exec` work without the exported
   environment.
8. Refuses to continue when Solidtime has no users, no administrator credentials are set
   and registration is not `on`. Otherwise it creates the first account with
   `admin:user:create`, piping the password into `--ask-for-password` (`SHELL_INTERACTIVE=1`
   makes the command ask although no terminal is attached), and sets its time zone to the
   `TZ` that the Supervisor passes in.
9. Creates the OAuth clients that the upstream guide has you create by hand: a personal
   access client for API tokens, and public clients for the desktop app and the browser
   extensions. It logs the public client IDs on every start.
10. Starts `supervisord` in the background. Its programs (`web`, `scheduler`, `queue`) run as
    `laravel`; supervisord itself runs as root, because only root can open the container's
    stdout for their logs.
11. Waits. On `SIGTERM` or `SIGINT` it stops supervisord, which stops all three programs,
    then shuts PostgreSQL down with a fast shutdown (`SIGINT`). If either supervisord or
    PostgreSQL exits on its own, it stops the other and exits with an error, so the
    Supervisor watchdog restarts the app.

The Dockerfile defines a health check on `/health-check/up`. The web server only starts
once migrations have run, so the Supervisor shows the app as *starting* until Solidtime is
ready, and its watchdog restarts the app if the check fails after the 10-minute start
period. The health-check routes are exempt from Solidtime's trusted host check, so the
check works whatever `app_url` is. `timeout: 90` in `config.yaml` gives the queue worker
and PostgreSQL time to finish before Docker kills the container.

### Storage

| Path in the container          | Contents                                      | In backups |
| ------------------------------ | --------------------------------------------- | ---------- |
| `/data/postgres`               | PostgreSQL data directory                     | Yes        |
| `/data/secrets`                | `APP_KEY`, Passport keys, database password   | Yes        |
| `/data/solidtime/storage/app`  | Solidtime `storage/app`: uploads, exports     | Yes        |
| `/data/options.json`           | App options, written by the Supervisor        | Yes        |

`backup: cold` stops the app during a backup so the PostgreSQL files are consistent.

### Design decisions

**PostgreSQL inside the container.** Solidtime only supports PostgreSQL. A separate
database app would make installation a two-app job and tie Solidtime's data to a database
that other apps share. Bundling keeps the app self-contained and its backup complete.

**One container, three programs.** Upstream runs the web server, the scheduler and the
queue worker as separate containers. A Home Assistant app is one container, so
supervisord, which the upstream image already includes, runs all three.

**Two web workers.** Octane starts one worker per CPU core by default, which used close to
1 GB of memory on a 32-core test machine. Two workers (`--workers=2`) bring the whole app
to around 400 MB and are plenty for a household or small team. Each worker restarts after
500 requests to keep memory in check.

**No Gotenberg.** Solidtime renders PDF reports through Gotenberg, which bundles Chromium
and LibreOffice and would more than double the image size. The `gotenberg_url` option lets
users point at a Gotenberg they run elsewhere.

**ICU collation.** The database uses ICU's root collation (`und`), which sorts text the way
people expect independent of the container locale. A new ICU library can change sort order,
which PostgreSQL detects; `run.sh` then runs `REINDEX DATABASE` and
`REFRESH COLLATION VERSION`, the fix the upstream guide documents as a manual step.

**PostgreSQL major version pinned.** The Dockerfile installs `postgresql-17` by name. A new
major version cannot read an older data directory without `pg_upgrade`, so `run.sh` refuses
to start when `PG_VERSION` does not match, rather than letting PostgreSQL fail with a
cryptic error. See [Releasing](releasing.md#changes-to-watch-for).

**`registration` defaults to `invite-only`.** With `off`, invited team members cannot create
an account at all; with `on`, anyone who can reach the server can. `invite-only` is the
safe setting that still lets teams grow.

**`app_url` is required.** Solidtime rejects requests on host names other than the
`APP_URL` host and `TRUSTED_HOSTS`, and uses `APP_URL` in emails. `APP_FORCE_HTTPS`, which
also marks the session cookie secure, follows the scheme of `app_url`.

**No ingress.** Home Assistant's ingress serves an app under a per-session sub-path
(`/api/hassio_ingress/<token>/`). Solidtime is an Inertia single-page application with
absolute routes and asset paths, so it breaks under that prefix. The app publishes port
8000 and sets `webui` instead, which gives the **Open web UI** button. `DOCS.md` explains
how to add a sidebar entry with a Webpage dashboard.

**Cold backups.** A hot backup would need a `backup_pre` dump and a restore path that
imports it. Solidtime's database is small, so a short stop is the simpler and safer trade.

**Locally built image.** The Supervisor builds the Dockerfile on the user's device; there is
no `image` key in `config.yaml`. Publishing prebuilt images to a container registry from CI
would make installation faster and is a possible improvement.

**Upstream versioned tags.** `solidtime/solidtime:<version>` is published for `amd64` and
`arm64`, which map to the Supervisor's `amd64` and `aarch64`.

## Testing a change

Work through these in order. Each catches problems the previous one cannot.

### 1. Lint

```bash
docker run --rm -v "$PWD/solidtime:/mnt" koalaman/shellcheck:stable /mnt/run.sh
docker run --rm -v "$PWD/scripts:/mnt" koalaman/shellcheck:stable /mnt/update-solidtime.sh
```

In Git Bash on Windows, prefix these with `MSYS_NO_PATHCONV=1` so `/mnt` is not rewritten
into a Windows path.

### 2. Build and run with Docker

This checks the image and `run.sh` without Home Assistant. It needs Docker Desktop or any
Docker Engine.

```bash
docker build -t local/solidtime-app solidtime
docker volume create solidtime-test-data

echo '{
  "app_url": "http://localhost:8000",
  "trusted_hosts": "127.0.0.1",
  "registration": "invite-only",
  "admin_name": "Test",
  "admin_email": "admin@example.com",
  "admin_password": "changeme123",
  "super_admins": "admin@example.com"
}' | docker run --rm -i -v solidtime-test-data:/data --entrypoint sh local/solidtime-app \
  -c 'cat > /data/options.json'

docker run --rm --init --name solidtime-test -p 8000:8000 -e TZ=Europe/Amsterdam \
  -v solidtime-test-data:/data local/solidtime-app
```

Use a named volume rather than a folder bind mount: PostgreSQL refuses to start on a data
directory whose owner and permissions it cannot set, which is the case for Docker Desktop
bind mounts on Windows.

Open <http://localhost:8000> and log in as `admin@example.com` / `changeme123`. Stop with
`docker stop solidtime-test`; the log should end with `database system is shut down`.
Remove the data with `docker volume rm solidtime-test-data`.

To check the `aarch64` build on an `amd64` machine (slow, uses emulation):

```bash
docker buildx build --platform linux/arm64 -t local/solidtime-app:arm64 solidtime
```

Things worth checking after a change to `run.sh`:

- A fresh start without `admin_email` stops with the *No Solidtime users exist yet*
  message.
- A second start with the admin options cleared still works, and logs *Nothing to migrate*.
- The log shows both OAuth client IDs, and the IDs stay the same across restarts.
- `docker stop` shuts PostgreSQL down cleanly, and after
  `docker exec solidtime-test pkill -KILL -x postgres` the app exits with code 1 and the
  next start recovers.
- A request with an unlisted `Host` header returns 400.
- `docker stats` shows around 400 MB of memory once Solidtime is idle.

### 3. Run in a development Home Assistant

The repository includes the official Home Assistant development container, which runs a
complete Home Assistant with a Supervisor inside Docker. This tests the parts plain Docker
cannot: `config.yaml`, the options form, translations, the **Open web UI** button and the
watchdog.

1. Install the VS Code *Dev Containers* extension and start Docker Desktop.
2. Open the repository in VS Code and select **Reopen in Container**.
3. Run the task **Start Home Assistant** (**Terminal** > **Run Task**).
4. Open <http://localhost:7123>, complete onboarding, and go to **Settings** > **Apps** >
   **Install app**. Solidtime is listed under **Local apps**.

Port 8000 is forwarded from the development container, so **Open web UI** works from the
same computer when `app_url` is `http://localhost:8000`.

### 4. Install on a real Home Assistant

1. Install the **Samba share** or **Advanced SSH & Web Terminal** app.
2. Copy the `solidtime/` folder into the `local_apps` share (the `/addons` folder over SSH).
3. Go to **Settings** > **Apps** > **Install app**, open the three-dots menu and select
   **Check for updates**. Solidtime appears under **Local apps**.
4. Install, configure and start it as described in `DOCS.md`.

A local copy is a separate app from the one installed from GitHub, with its own data, so
both can be installed side by side. After changing files, rebuild from the app's three-dots
menu (**Rebuild**).
