# Changelog

All notable changes to this app are documented here. The version number is the Solidtime
version the app contains; see the
[Solidtime releases](https://github.com/solidtime-io/solidtime/releases) for changes in
Solidtime itself.

## 0.21.0.1

- Stop PostgreSQL logging a failed login on every start.

## 0.21.0

First release.

- Solidtime 0.21.0 with a bundled PostgreSQL 17 database.
- Web server, scheduler and queue worker in one app.
- Creates the first account from the app options, in the Home Assistant time zone.
- Generates the encryption and OAuth keys, and the OAuth clients for API tokens and the
  desktop app.
- Optional email through any SMTP server, and optional PDF exports through Gotenberg.
- Opens through **Open web UI**; English and Dutch option descriptions.
