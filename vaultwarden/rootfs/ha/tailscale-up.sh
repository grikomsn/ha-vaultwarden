#!/bin/sh
# Joins the tailnet as its own node and publishes the vault with
# Tailscale Serve (tailnet only) or Funnel (public internet), both on
# https://<TS_HOSTNAME>.<tailnet>.ts.net -> http://127.0.0.1:8080.
# Exits 0 once serving; run.sh retries it on failure.
set -u

SOCKET=/tmp/ha/tailscaled.sock
AUTHKEY_FILE=/tmp/ha/tailscale.authkey
ts() { /usr/local/bin/tailscale --socket="$SOCKET" "$@"; }
log() { echo "[tailscale] $*"; }

i=0
until [ -S "$SOCKET" ] && ts version >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -ge 60 ] && { log "tailscaled did not start; set log_level to debug to see its log"; exit 1; }
  sleep 1
done

set -- up --reset --hostname="$TS_HOSTNAME" --accept-dns=false --accept-routes=false
if [ -s "$AUTHKEY_FILE" ]; then
  set -- "$@" --auth-key="file:$AUTHKEY_FILE"
fi

state="$(ts status --json 2>/dev/null | jq -r '.BackendState // empty')"
if [ "$state" != "Running" ] && [ ! -s "$AUTHKEY_FILE" ]; then
  log "Not logged in and no tailscale_auth_key set: open the login URL below to add this node."
fi
# Blocks until logged in; prints a login URL when interactive login is needed.
ts "$@" || { log "tailscale up failed"; exit 1; }

ts serve reset >/dev/null 2>&1 || true
if [ "$TS_FUNNEL" = "true" ]; then
  log "Enabling Funnel (public internet) on port 443"
  ts funnel --bg --yes 8080 || { log "tailscale funnel failed (is Funnel allowed for this node in the tailnet policy?)"; exit 1; }
else
  log "Enabling Serve (tailnet only) on port 443"
  ts serve --bg --yes 8080 || { log "tailscale serve failed (are HTTPS certificates enabled for the tailnet?)"; exit 1; }
fi

dns_name="$(ts status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
log "Vault reachable at https://$dns_name"
if [ -n "$dns_name" ] && [ "$dns_name" != "${VW_HOST:-}" ]; then
  log "Note: the 'domain' option is ${VW_HOST:-unset}. Clients can still use https://$dns_name,"
  log "but links in emails and passkey (WebAuthn) login use the 'domain' option."
fi
