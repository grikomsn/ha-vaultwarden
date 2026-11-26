# Security policy

This repository packages Vaultwarden as a Home Assistant app. It holds
password vaults, so please report security problems privately.

## What to report here

Problems in this repository's own code: the [Dockerfile](vaultwarden/Dockerfile),
the wrapper scripts in [`vaultwarden/rootfs/ha/`](vaultwarden/rootfs/ha/),
and the app configuration. For example, secrets leaking into logs, wrong file
permissions, or Tailscale or Cloudflare settings that expose more than intended.

Report them through
[GitHub private vulnerability reporting](https://github.com/grikomsn/ha-vaultwarden/security/advisories/new).
Please don't open a public issue.

## What to report upstream

- Vaultwarden server: <https://github.com/dani-garcia/vaultwarden/security/policy>
- Bitwarden clients and web vault: <https://bitwarden.com/help/security/>
  (only for problems that also affect Bitwarden's own servers).
- Tailscale: <https://tailscale.com/security>
- cloudflared: <https://www.cloudflare.com/disclosure/>

## Supported versions

Only the latest release of the app gets fixes. It tracks the latest
Vaultwarden release, so security fixes from upstream reach you through normal
app updates.
