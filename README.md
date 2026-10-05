# Solidtime for Home Assistant

[![Add repository to Home Assistant][repository-badge]][repository-url]
![Solidtime 0.21.0][solidtime-shield]
![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
[![License: MIT][license-shield]](LICENSE)

Run [Solidtime](https://www.solidtime.io/), the modern open-source time tracker, as a Home
Assistant app. Solidtime and its PostgreSQL database run together in one app, so there is
nothing else to set up.

## Features

- Solidtime with a bundled database; no separate database app needed.
- The web server, scheduler and queue worker all run inside the one app.
- The first account, the encryption keys and the OAuth clients are created for you.
- All data is included in Home Assistant backups.
- Works with the Solidtime desktop app, the browser extensions and API tokens.
- Opens from the app page, the Home Assistant Companion app, or a sidebar dashboard.
- Runs on `amd64` and `aarch64` (Raspberry Pi 4 and 5).

## Installation

Select the button above, or add the repository by hand:

1. In Home Assistant, go to **Settings** > **Apps** > **Install app**.
2. Open the three-dots menu in the top-right corner and select **Repositories**.
3. Add `https://github.com/FaliseDotCom/ha-solidtime` and select **Add**.
4. Find **Solidtime** in the app store and select **Install**.

Then follow the [app documentation](solidtime/DOCS.md) to create your account and open
Solidtime. The same documentation is shown on the app's **Documentation** tab in Home
Assistant.

## Apps in this repository

| App                       | Description                                                   |
| ------------------------- | ------------------------------------------------------------- |
| [Solidtime](solidtime/)   | Modern open-source time tracking for freelancers and teams.   |

## Contributing

Bug reports and pull requests are welcome. [Development](.docs/development.md) explains how
the app works and how to test changes, and [Releasing](.docs/releasing.md) covers updating
to a new Solidtime version.

## AI coding guidelines

This project is shell, YAML, Docker and Markdown only. None of the language skills (`php`,
`phpstan`, `wordpress`, `wordpress-translations`, `javascript`, `svelte`, `css`) apply. The
global guidelines for formatting (two-space indentation, braces on their own line) and Git
still do, and shell scripts must pass [ShellCheck](https://www.shellcheck.net/).

## License

The files in this repository are released under the [MIT License](LICENSE), except for
`solidtime/icon.png` and `solidtime/logo.png`. Solidtime itself is licensed under the
[AGPL-3.0](https://github.com/solidtime-io/solidtime/blob/main/LICENSE.md) and is not
affiliated with this project.

The Solidtime name and the icon images (`solidtime/icon.png` and `solidtime/logo.png`,
resized from Solidtime's own favicon and logo) belong to the Solidtime project. They are used
only to identify the app, and remain under the Solidtime project's terms.

[repository-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repository-url]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FFaliseDotCom%2Fha-solidtime
[solidtime-shield]: https://img.shields.io/badge/Solidtime-0.21.0-blue.svg
[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[license-shield]: https://img.shields.io/badge/license-MIT-green.svg
