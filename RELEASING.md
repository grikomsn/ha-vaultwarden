# Releasing

Home Assistant decides everything from `version` in
[`vaultwarden/config.yaml`](vaultwarden/config.yaml): the version users see,
the image tag the Supervisor pulls, and whether an update is offered.

## Version scheme

```text
<Vaultwarden tag>[.<revision>]
1.37.5      Vaultwarden 1.37.5
1.37.5.1    same Vaultwarden, first packaging change (scripts, Tailscale, cloudflared, jq, options)
1.37.6      next Vaultwarden release (revision resets)
```

Don't use a suffix like `1.37.5-1`: the Supervisor compares versions with
[AwesomeVersion](https://github.com/ludeeus/awesomeversion), which reads `-1`
as a pre-release, so `1.37.5-1` sorts *below* `1.37.5` and users never see the
update. The four-part form sorts correctly (checked with awesomeversion
25.8.0, the version the Supervisor pins).

## What CI enforces

`Version and changelog` in [CI](.github/workflows/ci.yaml) runs
[`check_version.py`](.github/scripts/check_version.py) on every pull request:

- `version` is the Vaultwarden tag from the Dockerfile (without `-alpine`),
  optionally plus `.<revision>`.
- `vaultwarden/CHANGELOG.md` has a `## <version>` section.
- If the Dockerfile instructions, `rootfs/`, or the options in `config.yaml`
  changed, `version` must be higher than on `main`. The error message names
  the version to use. Edits to comments, docs, translations and the `image`
  key don't need a bump.

The amd64 build also starts the image and checks that Vaultwarden answers,
uses the configured domain and refuses sign-ups when they are turned off.

## Dependency updates (Renovate)

[Renovate](renovate.json) opens PRs on Monday mornings (UTC):

| PR | What it changes | What you do |
| --- | --- | --- |
| **GitHub Actions** | Action versions and commit SHAs | Nothing. It merges itself when CI passes. |
| **Vaultwarden** | Dockerfile tag and digest, and `version` in `config.yaml` | Read the [release notes](https://github.com/dani-garcia/vaultwarden/releases) for config changes, add a `## <new version>` CHANGELOG section, then merge. |
| **Tailscale, cloudflared and jq** | Dockerfile tag and digest | Bump `version` to the next revision (CI names it), add a CHANGELOG section, then merge. |

Vaultwarden releases often fix security advisories, so merge its PRs soon
after they open.

## Publishing

Merging to `main` runs the [Release workflow](.github/workflows/release.yaml)
when `version` has no `v<version>` tag yet. It:

1. Builds `amd64` and `aarch64` images natively with Home Assistant's
   [builder actions](https://github.com/home-assistant/builder) and pushes
   `ghcr.io/grikomsn/{amd64,aarch64}-ha-vaultwarden:<version>`.
2. Publishes the multi-arch image `ghcr.io/grikomsn/ha-vaultwarden:<version>`
   (and `latest`). Every image is signed with Cosign (keyless, GitHub OIDC).
3. Creates the `v<version>` tag and a GitHub release with the CHANGELOG section.

Tags are never overwritten: if a version is already published, the build is
skipped.

The Supervisor downloads images anonymously, so the
`ghcr.io/grikomsn/ha-vaultwarden` package must be public (GitHub → package
settings → Change visibility), and so must this repository for Home Assistant
to add it.

Because `image:` is set in `config.yaml`, there is a window of a few minutes
between the merge and the end of the build where a Supervisor may already
offer the update but can't download it yet. Merge only when CI is green, so
that the release build doesn't fail.

To check a published image's signature (needs Cosign 3 or later; the builder
signs with Cosign 3, and Cosign 2 reports "no signatures found"):

```sh
cosign verify ghcr.io/grikomsn/ha-vaultwarden:<version> \
  --certificate-identity-regexp '^https://github\.com/grikomsn/ha-vaultwarden/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
