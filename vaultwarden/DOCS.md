# Vaultwarden

This app runs [Vaultwarden](https://github.com/dani-garcia/vaultwarden), an
unofficial, lightweight server for the official Bitwarden apps (browser
extensions, desktop, iOS, Android and the web vault). Vaultwarden itself uses
about 30 MB of RAM, and it includes the features Bitwarden sells as Premium,
such as TOTP codes, YubiKey and Duo login, attachments and emergency access.

It can also publish the vault over HTTPS without opening router ports, using
either or both of:

- **Cloudflare Tunnel** on a domain or subdomain of your choice
  (`vault.example.com`).
- **Tailscale** as its own tailnet node (`vault.tail1234.ts.net`), with Serve
  for tailnet devices only, or Funnel for the public internet.

> Vaultwarden is not made or supported by Bitwarden, Inc. Report problems with
> this app here, not to Bitwarden.

## Before you start

**Pick a hostname.** Clients need HTTPS, because the web vault's cryptography
doesn't run on plain HTTP and the mobile apps refuse it. Use a Cloudflare
hostname, a Tailscale name, or both (see below).

## Install

1. In Home Assistant go to **Settings → Apps → Install app**, open the
   three-dot menu, choose **Repositories** and add
   `https://github.com/grikomsn/ha-vaultwarden`.
2. Install **Vaultwarden**. Home Assistant downloads the prebuilt image
   (`ghcr.io/grikomsn/ha-vaultwarden`, signed with Cosign).
3. Fill in the options below, then start the app and watch the **Log** tab.

## Options

| Option | Required | Description |
| --- | --- | --- |
| `domain` | yes | Hostname clients use, for example `vault.example.com`. `https://` is added for you. Used for links in emails, attachments and passkey (WebAuthn) login. |
| `signups_allowed` | | On by default so you can create your first account. Turn it off afterwards. |
| `admin_token` | | Turns on the admin panel at `/admin`. See [Admin panel](#admin-panel). |
| `log_level` | | `info` by default. `debug` and `trace` also show the Tailscale daemon's log. |
| `smtp_*` | | Outgoing mail, needed for email verification, invitations, emergency access, email 2FA and new-device alerts. |
| `push_installation_id`, `push_installation_key`, `push_region` | | Instant sync for the mobile apps. See [Push notifications](#push-notifications). |
| `cloudflare_tunnel_token` | | Turns on the built-in Cloudflare Tunnel. |
| `tailscale`, `tailscale_auth_key`, `tailscale_hostname`, `tailscale_funnel` | | Turn on the built-in Tailscale node. |
| `env_vars` | | Any other [Vaultwarden setting](https://github.com/dani-garcia/vaultwarden/blob/main/.env.template), applied last. |

The vault is stored as SQLite in this app's data folder. To use MySQL/MariaDB
or PostgreSQL instead, set `DATABASE_URL` in `env_vars`.

Settings you save in the admin panel are written to `config.json` in the data
folder and **override these options**, including `domain` and SMTP. If an
option seems to have no effect, check the admin panel, or reset a setting
there.

### SMTP

| Provider style | `smtp_security` | `smtp_port` |
| --- | --- | --- |
| Implicit TLS | `force_tls` | 465 |
| STARTTLS | `starttls` | 587 |

If you only set `smtp_port: 465`, `force_tls` is picked for you. `smtp_from`
defaults to `vaultwarden@<domain>`; most providers only accept a sender on a
domain you have verified with them. For example, Resend uses host
`smtp.resend.com`, port 465, username `resend` and an API key as the
password. Check the Log tab for mail errors after using **Send test email** in
the admin panel.

### Admin panel

The admin panel manages users, invitations and server settings. It stays off
until you set `admin_token`.

A plain-text token works, but Vaultwarden logs a warning at every start. An
Argon2 hash is safer, because the token itself is then never stored. Generate
one on any computer with Docker:

```sh
docker run --rm -it docker.io/vaultwarden/server:latest /vaultwarden hash
```

Paste the whole `$argon2id$...` line into `admin_token`, and log in to `/admin`
with the password you typed. If you only need the panel occasionally, remove
the token again afterwards.

### Push notifications

Without push, the mobile apps sync when you open them or pull to refresh.
Browser extensions and desktop apps sync instantly either way (over a
WebSocket).

1. Request an installation ID and key at <https://bitwarden.com/host/>. Pick
   the US or EU region.
2. Set `push_installation_id`, `push_installation_key` and `push_region`.
3. Log out of the mobile app and log in again, so it registers for push.

## Option A: Cloudflare Tunnel on your own domain

Needs a domain whose DNS is on Cloudflare.

1. In the Cloudflare dashboard open **Zero Trust → Networks → Connectors
   (Tunnels) → Create a tunnel**, choose **Cloudflared**, and name it.
2. Copy the token from the install command (the long string after
   `--token`). Skip the install step; this app runs cloudflared itself.
3. Add a **published application** (public hostname) route:
   - Subdomain and domain: whatever you want, e.g. `vault` + `example.com`.
   - Service: `HTTP` and `localhost:8080`.
   Cloudflare creates the DNS record for you.
4. In the app, set `cloudflare_tunnel_token` to the token and `domain` to the
   hostname from step 3, then (re)start the app. The log should show
   `Registered tunnel connection`.

Each tunnel token should be used by one running app only. If two apps run
with the same token, Cloudflare splits requests between them.

Cloudflare settings that break Bitwarden clients on this hostname:

- **Cloudflare Access** in front of the whole hostname: the mobile and desktop
  apps can't complete the Access login. If you want Access, protect only
  `/admin`.
- **Bot Fight Mode** or WAF challenges: apps can't solve challenges. Skip the
  vault hostname in those rules.
- **WebSockets** must stay enabled (they are by default). Live sync uses
  `/notifications/hub`.

### Using the Cloudflared app instead

If you already run the community **Cloudflared** app for Home Assistant, you
can leave `cloudflare_tunnel_token` empty and add an entry to its
`additional_hosts`:

```yaml
- hostname: vault.example.com
  service: http://homeassistant:7277
```

For that, enable this app's `8080/tcp` port in **Network** and set it to the
host port you used (7277 above). Keep in mind that this also opens the vault
over plain HTTP on your LAN at that port, and that Vaultwarden then logs the
Cloudflared app's address instead of each client's IP, unless you add it to
`IP_HEADER_TRUSTED_PROXIES` in `env_vars`.

## Option B: Tailscale Serve or Funnel

The app joins your tailnet as a separate machine (default name `vault`), so the
vault gets its own `https://vault.<tailnet>.ts.net` address on port 443. This is
independent of the Tailscale app you may already run for Home Assistant.

1. In the Tailscale admin console under **DNS**, enable **MagicDNS** and
   **HTTPS Certificates**.
2. For Funnel (public internet), allow it in the tailnet policy file, for
   example:

   ```json
   "nodeAttrs": [{ "target": ["autogroup:member"], "attr": ["funnel"] }]
   ```

3. In the app, turn on `tailscale` and optionally set `tailscale_hostname`
   and `tailscale_funnel`. Either paste an auth key into `tailscale_auth_key`,
   or leave it empty and open the login URL that appears in the **Log** tab.
4. In the Tailscale admin console, disable key expiry for the new machine so
   it doesn't drop off the tailnet.

If a machine with the same name already exists in your tailnet, the new one
gets a suffix like `vault-1`. Remove the old machine first to keep the name.

If Tailscale is your only way in, set `domain` to the full name, e.g.
`vault.tail1234.ts.net`. The log prints it once the node is up.

The first Funnel request can take a few minutes while Tailscale provisions the
certificate and public DNS.

## Using both

Cloudflare and Tailscale can run at the same time. Clients can log in through
either hostname. `domain` should be the one you treat as primary: links in
emails and passkey (WebAuthn) login only work on that hostname.

## First run

1. Open `https://<domain>` and create your account.
2. Turn off `signups_allowed` and restart the app. To add people later,
   invite them from the admin panel or from an organization.
3. In each Bitwarden app, choose **Self-hosted** on the login screen and enter
   `https://<domain>`.
4. Turn on two-step login in the web vault under **Settings → Security**.

## Moving an existing vault here

- **From Bitwarden (cloud or self-hosted):** in the old web vault, use
  **Tools → Export vault** with the **.json (Password protected)** format.
  Import it in this vault under **Tools → Import data**. Attachments are not
  part of the export, so download and upload them again. Organizations are
  exported and imported separately.
- **From the community Vaultwarden app** (`hassio-addons`): it keeps the same
  files in its data folder. Copy `db.sqlite3`, the `rsa_key*` files,
  `attachments/`, `sends/` and `config.json` into this app's data folder while
  both apps are stopped, or use the export and import above.

## Backups and updates

- Home Assistant backups include this app's data folder: the SQLite vault,
  RSA keys, attachments, sends and Tailscale state. The app is stopped briefly
  while it is backed up (`backup: cold`) so SQLite is copied consistently. The
  icon cache is left out.
- The data folder holds the keys that sign login sessions. Treat backups that
  include this app as sensitive, and set a backup password.
- The app version follows the Vaultwarden release it is built on, with a
  fourth number for packaging-only changes (`1.37.5.1`). Updates download a
  new prebuilt image. Vaultwarden releases often contain security fixes, so
  install updates promptly. Release notes:
  <https://github.com/grikomsn/ha-vaultwarden/releases>.

## Troubleshooting

- **App stops right after start:** the log says which option is missing or
  wrong. Since Vaultwarden 1.37.5, invalid values in `env_vars` also stop it.
- **Logs:** the Log tab shows Vaultwarden, cloudflared and the Tailscale
  login/serve steps. Set `log_level` to `debug` for the Tailscale daemon too.
- **`tailscale serve failed`:** enable HTTPS certificates for the tailnet.
  **`tailscale funnel failed`:** add the `funnel` node attribute.
- **Apps say the server is unreachable through Cloudflare:** check the Access,
  Bot Fight Mode and WAF notes above.
- **No emails:** check the SMTP settings, then look for mail errors in the log
  and in your provider's dashboard. Settings saved in the admin panel override
  the app's SMTP options.
