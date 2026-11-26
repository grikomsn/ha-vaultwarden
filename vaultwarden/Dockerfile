# Images are pinned by tag and multi-arch index digest; Renovate updates both
# (and `version` in config.yaml with the Vaultwarden tag). Any change here
# needs a version bump and a CHANGELOG.md entry: see RELEASING.md.

FROM docker.io/tailscale/tailscale:v1.104.7@sha256:72c1e19e0aedca96b8533bbb0b4368564410ff20b17e53b804eb6c1f04a31be4 AS tailscale
FROM docker.io/cloudflare/cloudflared:2026.11.2@sha256:55c7e3e8d89d5e8d20b75a82f3602cbf98e06db406e73e282073cfdc5a9a3af6 AS cloudflared
FROM ghcr.io/jqlang/jq:1.8.2@sha256:b9c68867e5766576263a222e91db3de422d802069c7af70440e667a95344e486 AS jq

# Official Vaultwarden image, Alpine variant (multi-arch: amd64, arm64, armv7, armv6).
FROM docker.io/vaultwarden/server:1.37.5-alpine@sha256:bbe684a02d6b0db54256ff88eac9754f4519284a7b26314afc241fd7d0918191

COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/tailscaled /usr/local/bin/
COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/
COPY --from=jq /jq /usr/local/bin/jq
COPY rootfs/ /
RUN chmod 0755 /ha/*.sh

# Also set here, not only in run.sh: the upstream HEALTHCHECK script reads it
# from the image environment.
ENV ROCKET_PORT=8080

# Wraps the upstream /start.sh: turns the app options into the environment
# variables Vaultwarden reads, starts the optional tunnels, then hands over.
ENTRYPOINT ["/ha/run.sh"]
