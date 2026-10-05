# Solidtime

[Solidtime](https://www.solidtime.io/) is a modern, open-source time tracker. Track time
against clients, projects and tasks, set billable rates, and turn it into reports. This app
runs Solidtime on your Home Assistant server, together with its own PostgreSQL database, so
there is nothing else to install.

## Requirements

- Home Assistant OS or a Supervised installation, version 2026.7 or later.
- A 64-bit system: `amd64` (most PCs and NUCs) or `aarch64` (Raspberry Pi 4 or 5, and
  most other ARM boards).
- Around 2.5 GB of free disk space for the app, plus room for your data.
- Around 400 MB of free memory while Solidtime is running.

The first installation builds the app on your own device. Expect it to take a few minutes,
or longer on a Raspberry Pi.

## Installation

1. Add this repository to Home Assistant. Go to **Settings** > **Apps** > **Install app**,
   open the three-dots menu in the top-right corner, select **Repositories**, then add:

   ```text
   https://github.com/FaliseDotCom/ha-solidtime
   ```

2. Find **Solidtime** in the app store and select **Install**.
3. Open the **Configuration** tab. Check `app_url`, and set `admin_email` and
   `admin_password`. See [First start](#first-start).
4. Go back to the **Info** tab, turn on **Watchdog**, and select **Start**.
5. Open the **Log** tab. The first start takes a minute or two while the database is
   created. Solidtime is ready when the log shows `success: web entered RUNNING state`.

## First start

Solidtime does not let visitors sign up by default, so the app creates the first account
for you. Before the very first start, fill in:

| Option           | Value                                             |
| ---------------- | ------------------------------------------------- |
| `app_url`        | The address you open Solidtime on; see below      |
| `admin_name`     | Your name                                         |
| `admin_email`    | Your email address; you log in with it            |
| `admin_password` | A password of 8+ characters                       |
| `super_admins`   | Your email address again, to get the admin panel  |

The account is created with its own organization, in the Home Assistant time zone, and its
email address is marked as verified.

`admin_name`, `admin_email` and `admin_password` are only read while Solidtime has no users.
Once you have logged in, change the password on your profile page in Solidtime, then clear `admin_password` in the app configuration so it is
no longer stored there. Changing these options later does **not** change the existing
account.

If you start the app without these options on a fresh install, it stops with a message in
the log asking you to set them.

## Opening Solidtime

Solidtime runs on its own port, **8000**, separate from the Home Assistant interface.

### The Solidtime address

Solidtime needs to know the address you open it on. It uses that address in emails and
links, and refuses requests on any other host name, which protects against host header
attacks on, for example, password reset links. Set `app_url` to the address you type in the
browser:

```yaml
app_url: http://homeassistant.local:8000
```

If you also reach Solidtime on other names, such as its IP address, list them in
[`trusted_hosts`](#option-trusted_hosts). On a host name that is in neither, Solidtime shows
*This hostname is not configured for this instance*.

### From the app page

Select **Open web UI** on the app's **Info** tab. This opens
`http://<your-home-assistant-address>:8000` in a new tab. It works on any device on your
home network, including the Home Assistant Companion app on Android and iOS, as long as the
host name in that address is in `app_url` or `trusted_hosts`.

### On your phone

In the Companion app, go to **Settings** > **Apps** > **Solidtime** and select **Open web
UI**. Solidtime opens in your phone's browser. To keep it one tap away, use your browser's
**Add to home screen** option.

When you are away from home and connect through Home Assistant Cloud or another remote URL,
port 8000 is usually not reachable. Set up [remote access](#remote-access) if you want to use
Solidtime away from home.

### In the Home Assistant sidebar (optional)

This app does not use Home Assistant's built-in sidebar integration (called *ingress*),
because Solidtime cannot run under the changing sub-path that ingress uses. You can still add
Solidtime to the sidebar with a **Webpage** dashboard:

1. Go to **Settings** > **Dashboards** and select **Add dashboard**.
2. Choose **Webpage** and enter Solidtime's address, the same as `app_url`.
3. Give it a title such as *Solidtime*, pick an icon such as `mdi:timer-outline`, and keep
   **Show in sidebar** turned on.

Two things to keep in mind:

- The browser loads Solidtime directly, so the sidebar entry only works where Solidtime's
  address is reachable, normally on your home network.
- If you open Home Assistant over `https://`, the address of the dashboard must use
  `https://` too, or the browser blocks the page. Use your [remote access](#remote-access)
  address in that case.

### Desktop app and browser extensions

The [Solidtime desktop app](https://github.com/solidtime-io/solidtime-desktop) and the
Solidtime browser extensions for
[Chrome](https://chromewebstore.google.com/detail/solidtime/hpanifeankiobmgbemnhjmhpjeebdhdd)
and [Firefox](https://addons.mozilla.org/en-US/firefox/addon/solidtime/) work with this app.
Each needs its own OAuth client, which the app creates on first start. Their IDs are printed
in the log on every start:

```text
[solidtime-app] Client ID for the desktop app: 01a10bee-d92d-72c6-b1af-7e69e684dd9c
[solidtime-app] Client ID for the browser extension: 01a10bee-e0b2-7310-9a4c-2f1d6d0c4a77
```

Start the desktop app or open the extension, select **Instance Settings**, and enter your
`app_url` as the API URL and the matching ID as the client ID. Then log in.

### API tokens

API tokens for scripts and integrations are created on your profile page in Solidtime, under
**API Tokens**. The app creates the OAuth client that Solidtime needs for this on first start.

## Configuration

Example configuration:

```yaml
app_url: http://homeassistant.local:8000
trusted_hosts: 192.168.1.10
trusted_proxies: 127.0.0.1,172.30.32.0/23
registration: invite-only
admin_name: Alex
admin_email: you@example.com
admin_password: a-long-random-password
super_admins: you@example.com
```

Restart the app after changing any option.

### Option: `app_url`

The address you open Solidtime on, without a path, for example
`http://homeassistant.local:8000` or `https://time.example.com`. See
[The Solidtime address](#the-solidtime-address).

When it starts with `https://`, Solidtime builds every link with `https://` and marks its
cookies as secure, so logging in only works over HTTPS. Use an `https://` address only when
Solidtime sits behind a proxy that provides HTTPS; see [Remote access](#remote-access).

### Option: `trusted_hosts`

A comma-separated list of extra host names Solidtime may be reached on, besides the one in
`app_url`. Subdomains of the `app_url` host are always allowed. Use `*.example.com` to allow
every subdomain of another domain:

```yaml
trusted_hosts: 192.168.1.10,homeassistant,time.example.com
```

Emails and links always use `app_url`, whichever host name you used.

### Option: `trusted_proxies`

A comma-separated list of IP addresses or ranges (CIDR) of reverse proxies that sit in
front of Solidtime. Solidtime only trusts the `X-Forwarded-*` headers from these addresses,
which it needs to know the visitor's real IP address and whether the original request used
HTTPS.

The default, `127.0.0.1,172.30.32.0/23`, covers proxies that run as another Home Assistant
app, such as NGINX Proxy Manager or Cloudflared. Add the address of any proxy that runs
elsewhere on your network.

### Option: `registration`

Who may create a Solidtime account:

| Value         | Meaning                                                                |
| ------------- | ---------------------------------------------------------------------- |
| `invite-only` | Only people who were invited to an organization. The default.          |
| `off`         | Nobody. Only the accounts that already exist can log in.               |
| `on`          | Anyone who can reach Solidtime. Only use this on your home network.    |

To add someone to your team, invite them from **Members** in Solidtime. Invitations are sent
by email, so set up a [mail server](#option-mail_host) first.

With `on`, you may leave `admin_email` and `admin_password` empty and create the first
account on the sign-up page instead.

### Option: `admin_name`, `admin_email` and `admin_password`

The name, email address and password (at least 8 characters) of the first account. Only
used while Solidtime has no users. See [First start](#first-start).

### Option: `super_admins`

A comma-separated list of email addresses. These accounts can open Solidtime's instance
administration panel at `/admin`, which lists every user and organization on the server.
Normal time tracking does not need it.

### Option: `mail_host`

The SMTP server Solidtime uses to send email, such as invitations, password reset links and
reminders, for example `smtp.example.com`. Optional; without it Solidtime sends no email and
writes each message to the log instead.

The other mail options set how Solidtime connects:

| Option              | Meaning                                                    | Default             |
| ------------------- | ---------------------------------------------------------- | ------------------- |
| `mail_port`         | Port of the SMTP server                                    | `587`               |
| `mail_encryption`   | `tls` (STARTTLS, port 587), `ssl` (port 465), or `none`    | `tls`               |
| `mail_username`     | User name, if the server requires one                      | none                |
| `mail_password`     | Password, if the server requires one                       | none                |
| `mail_from_address` | Address Solidtime sends from                               | `solidtime@localhost` |

The mail options are hidden until you select **Show unused optional configuration options**
on the **Configuration** tab.

### Option: `gotenberg_url`

Solidtime exports reports as PDF through [Gotenberg](https://gotenberg.dev/), a separate
document conversion server. It is not included in this app, because it needs a full web
browser and office suite and would more than double the app's size. Without it, every other
export format still works.

To enable PDF exports, run Gotenberg somewhere on your network, for example with Docker:

```bash
docker run -d --restart unless-stopped -p 3000:3000 gotenberg/gotenberg:8
```

and set `gotenberg_url` to its address, for example `http://192.168.1.10:3000`.

### Port

The **Network** section of the **Configuration** tab sets the port Solidtime is published on.
Change it if port 8000 is already in use on your server, and update `app_url` to match. Clear
it to stop publishing Solidtime on your network entirely, for example when a proxy app is the
only way in.

## Remote access

To use Solidtime away from home, put it behind a reverse proxy that provides HTTPS, such as
the **Cloudflared** or **NGINX Proxy Manager** app, and point the proxy at:

```text
http://<your-home-assistant-ip>:8000
```

Then:

1. Set `app_url` to the public address, for example `https://time.example.com`. From then on,
   use that address at home too: Solidtime only accepts logins over HTTPS once `app_url`
   uses `https://`.
2. Make sure the proxy's address is in [`trusted_proxies`](#option-trusted_proxies). If
   Solidtime shows the proxy's IP address as the visitor's, the proxy is not trusted yet.
3. Turn on two-factor authentication for every account, on each user's profile page.

Never expose port 8000 directly to the internet without HTTPS.

## Backups

The app is included in Home Assistant backups. Solidtime is stopped while the backup is made,
so that the database is copied in a consistent state, and starts again afterwards. For a
small database this takes well under a minute.

A backup contains everything: the database, uploaded files such as profile pictures, the
generated keys and the options. Restoring the app from a backup restores all of it.

Uninstalling the app **deletes the database**. Create a backup first if you might want your
data back.

## Updates

The app's version number is the Solidtime version it contains. Before you update:

1. Create a backup that includes Solidtime. Database changes during an update cannot be
   undone, and Solidtime cannot be downgraded without restoring a backup.
2. Read the [Solidtime release notes](https://github.com/solidtime-io/solidtime/releases) for
   the versions you are skipping.

Solidtime upgrades its database automatically on the first start after an update.

## Troubleshooting

Start with the **Log** tab of the app. Solidtime and PostgreSQL both write to it, and
messages from the app itself start with `[solidtime-app]`.

**"No Solidtime users exist yet"**
: Set `admin_email` and `admin_password` and start the app again. See
  [First start](#first-start).

**"This hostname is not configured for this instance"**
: The host name in your browser's address bar is not in `app_url` or `trusted_hosts`. Add
  it to `trusted_hosts`, or open Solidtime on the `app_url` address.

**Logging in does nothing, or shows "Page expired"**
: `app_url` starts with `https://`, but you opened Solidtime over `http://`. Open it on the
  `https://` address, or change `app_url` back to `http://`.

**The app fails to start right after installation**
: Check that port 8000 is not used by another app, or pick a different port in the
  **Network** section.

**"The database was created by PostgreSQL …"**
: A new app version contains a newer PostgreSQL that cannot read the old database directly.
  Restore the backup you made before updating and check the release notes of this app for
  the upgrade steps.

**Forgotten password**
: If email is configured, use **Forgot password** on the login page. Otherwise, set a new
  password from the command line. This needs the **Advanced SSH & Web Terminal** app with
  *Protection mode* turned off. Replace the email address and the password, and keep the
  quotes:

  ```bash
  docker exec --user laravel --workdir /var/www/html "$(docker ps --quiet --filter name=solidtime)" \
    php -r 'require "vendor/autoload.php"; $app = require "bootstrap/app.php";
      $app->make( Illuminate\Contracts\Console\Kernel::class )->bootstrap();
      App\Models\User::where( "email", "you@example.com" )->where( "is_placeholder", false )
        ->firstOrFail()->forceFill( [ "password" => Hash::make( "a-new-password" ) ] )->save();'
  ```

  Turn *Protection mode* back on afterwards.

## Security

- Use a long, unique password and turn on two-factor authentication.
- Keep `registration` at `invite-only` or `off` when Solidtime is reachable from outside
  your home network.
- Only reach Solidtime over HTTPS from the internet; see [Remote access](#remote-access).
- The database is only reachable from inside the app; it is never published on your
  network. Its password and Solidtime's encryption keys are generated on first start and
  stored in the app's private data.

## Support

- Problems with this app:
  [open an issue](https://github.com/FaliseDotCom/ha-solidtime/issues).
- Questions about using Solidtime: [Solidtime documentation](https://docs.solidtime.io/) and
  [Solidtime discussions](https://github.com/solidtime-io/solidtime/discussions).
