# Solidtime with a bundled PostgreSQL server, packaged as a Home Assistant app.
#
# The upstream image is pinned to an exact release. Bump this tag and the
# `version` in config.yaml together (see .docs/releasing.md).
FROM solidtime/solidtime:0.21.0

# The upstream image runs as the unprivileged `laravel` user. run.sh starts as
# root to prepare /data and start PostgreSQL, then drops to `laravel` (and to
# `postgres` for the database) for everything else.
USER root

# jq reads the app options from /data/options.json. The PostgreSQL major
# version is named explicitly, so a new Debian base with a different default
# fails the build instead of silently needing a database upgrade.
RUN apt-get update \
  && apt-get install -y --no-install-recommends jq postgresql-17 \
  && rm -rf /var/lib/apt/lists/*

COPY postgresql.conf /etc/solidtime/postgresql.conf
COPY supervisord.conf /etc/solidtime/supervisord.conf
COPY run.sh /run.sh
RUN chmod 0755 /run.sh

STOPSIGNAL SIGTERM

# The Supervisor shows the app as starting until this check passes, and its
# watchdog restarts the app when the check fails. The web server only starts
# once the database is migrated, so a healthy endpoint means Solidtime is ready.
# The health-check routes are exempt from the trusted host check.
HEALTHCHECK --start-period=10m --interval=30s --timeout=10s --retries=3 \
  CMD [ "curl", "--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:8000/health-check/up" ]

ENTRYPOINT [ ]
CMD [ "/run.sh" ]
