<img src="assets/icon.svg" width="64" height="64" alt="">

# ha-vaultwarden

A Home Assistant app repository for self-hosting
**[Vaultwarden](https://github.com/dani-garcia/vaultwarden)**, the lightweight
server for the official Bitwarden apps, on Home Assistant OS, with optional:

- **Cloudflare Tunnel** to serve it on your own domain or subdomain, and
- **Tailscale Serve/Funnel** to serve it on your tailnet or the internet.

No router ports need to be opened for either.

## Install

[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fgrikomsn%2Fha-vaultwarden)

Or add `https://github.com/grikomsn/ha-vaultwarden` under **Settings → Apps →
Install app → ⋮ → Repositories**, then install **Vaultwarden**.

## Apps

| App | Description |
| --- | --- |
| [Vaultwarden](vaultwarden/) | Vaultwarden 1.37.5 with built-in cloudflared and Tailscale. [Docs](vaultwarden/DOCS.md) |

## How it fits together

```text
Bitwarden apps ──HTTPS──> Cloudflare edge ──tunnel──> cloudflared ─┐
                                                                   ├─> Vaultwarden :8080 ─> SQLite in /data
Tailnet devices ─HTTPS──> Tailscale Serve (vault.<tailnet>.ts.net)┘   (all inside one app container)
```

The app's Dockerfile starts from the official `vaultwarden/server` Alpine
image, adds the `tailscale`, `cloudflared` and `jq` binaries from their
official images, and wraps the upstream `/start.sh` with
[`run.sh`](vaultwarden/rootfs/ha/run.sh), which turns the app's options into
Vaultwarden's environment variables.

## Releases

Versions follow Vaultwarden (`1.37.5`), with a fourth number for
packaging-only changes (`1.37.5.1`). Each release publishes Cosign-signed
`amd64`/`aarch64` images to `ghcr.io/grikomsn/ha-vaultwarden` and a
[GitHub release](https://github.com/grikomsn/ha-vaultwarden/releases).
Dependencies are kept current by Renovate. See [RELEASING.md](RELEASING.md).

## How this differs from the community Vaultwarden app

The [Home Assistant Community App](https://github.com/hassio-addons/app-vaultwarden)
runs Vaultwarden behind nginx on a Debian base, with options for logging and
TLS certificates. This app runs the official Vaultwarden image directly and
adds:

- Built-in Cloudflare Tunnel and Tailscale Serve/Funnel, so no certificates or
  open ports are needed.
- Options for the domain, sign-ups, admin token, SMTP and mobile push
  notifications, plus any other Vaultwarden setting through `env_vars`.
- The admin panel stays off until you set a token, instead of printing a
  generated token in the log.
- Signed, prebuilt images that track each Vaultwarden release.

## License and trademarks

The packaging in this repository (Dockerfile, scripts, configuration and docs)
is [MIT licensed](LICENSE). The image it builds contains Vaultwarden
(AGPL-3.0, source at <https://github.com/dani-garcia/vaultwarden>) with the
Bitwarden web vault (GPL-3.0), plus Tailscale (BSD-3-Clause), cloudflared
(Apache-2.0) and jq (MIT).

This is an unofficial community project. It is not affiliated with or endorsed
by the Vaultwarden project, Bitwarden, Inc., Tailscale Inc., Cloudflare, Inc.
or the Home Assistant project. "Bitwarden" is a trademark of Bitwarden, Inc.

Security issues: see [SECURITY.md](SECURITY.md).
