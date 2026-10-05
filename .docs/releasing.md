# Releasing

The app version always equals the Solidtime version it contains, so users see the Solidtime
version in Home Assistant.

## Updating to a new Solidtime release

This repository does not contain Solidtime's source code. The app is built from the official
Solidtime Docker image, so updating Solidtime means pointing the app at a newer image tag.

### With the update script

From the repository root, in Git Bash or any other Bash shell, with Docker running:

```bash
scripts/update-solidtime.sh          # latest Solidtime release
scripts/update-solidtime.sh 0.22.0   # a specific release
```

The script checks that the image exists for both architectures, refuses downgrades,
updates the version in all files, adds a changelog entry and builds the image. It does not
commit anything. Then do steps 2, 5 and 6 below: read the release notes, test the upgrade,
and commit, tag and push.

### By hand

1. Check the new release on [Docker Hub](https://hub.docker.com/r/solidtime/solidtime/tags),
   for example `0.22.0`, and confirm it lists both `linux/amd64` and `linux/arm64`:

   ```bash
   docker buildx imagetools inspect solidtime/solidtime:0.22.0
   ```

   Docker Hub tags have no `v` prefix; GitHub release tags do (`v0.22.0`).

2. Read the [Solidtime release notes](https://github.com/solidtime-io/solidtime/releases)
   for changes to the Docker image, especially new environment variables, a changed
   `start-container` script or supervisord configuration, or a new base Debian version.
3. Update the version in three places:
   - the `FROM` line in `solidtime/Dockerfile`
   - `version` in `solidtime/config.yaml`
   - the Solidtime badge in `README.md`
4. Add an entry at the top of `solidtime/CHANGELOG.md` that links to the Solidtime release
   notes.
5. Test as described in [Development](development.md). Always test an upgrade from the
   previous release, not only a fresh install: start the old version with data, then the new
   version on the same volume.
6. Commit, tag the commit with the version (`git tag 0.22.0`), and push both. Home Assistant
   offers the update to users the next time it checks the repository.

## App-only changes

For a change to the app itself without a new Solidtime release, add a fourth version
segment: `0.21.0` becomes `0.21.0.1`, then `0.21.0.2`. The next Solidtime release resets it.

## Changes to watch for

- **New base Debian release.** The upstream image is based on Debian 13 (trixie), which
  ships PostgreSQL 17. If a new base no longer has `postgresql-17`, the build fails. Do not
  just change the version number: the existing data directories need `pg_upgrade`, which
  needs both the old and the new PostgreSQL binaries. Install both versions from the
  [PostgreSQL apt repository](https://wiki.postgresql.org/wiki/Apt), run `pg_upgrade` in
  `run.sh` when `PG_VERSION` is older, and test it on real data first.
- **New ICU library.** `run.sh` rebuilds the indexes automatically. Check the log of the
  first start for *The collation library changed*.
- **Changes to the upstream processes.** `supervisord.conf` copies the web server command
  from the upstream `supervisord.frankenphp.conf`, the scheduler from
  `supervisord.scheduler.conf`, and the queue worker from the upstream Compose example.
  Compare them with `/etc/supervisor/conf.d/` in the new image.
- **New required environment variables.** Compare the upstream `laravel.env.example` in
  [self-hosting-examples](https://github.com/solidtime-io/self-hosting-examples) with
  `export_environment` in `run.sh`.
- **Changed console commands.** `run.sh` relies on `admin:user:create` with
  `--ask-for-password` and `--verify-email`, and on `passport:client` with `--personal`,
  `--public`, `--name` and `--redirect_uri`.
- **Supervisor changes.** Check the
  [app configuration reference](https://developers.home-assistant.io/docs/apps/configuration)
  for deprecations, and watch the Supervisor log for warnings about this app.
