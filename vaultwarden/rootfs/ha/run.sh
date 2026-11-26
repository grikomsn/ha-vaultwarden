#!/bin/sh
# Home Assistant wrapper for the official Vaultwarden image.
#
# Reads the app options written by the Supervisor, exports the environment
# variables documented in Vaultwarden's .env.template, starts the optional
# cloudflared / Tailscale helpers in the background, then execs the upstream
# /start.sh unchanged.
set -eu

OPTIONS=/data/options.json
RUN_DIR=/tmp/ha

log() { echo "[ha-vaultwarden] $*"; }
die() { echo "[ha-vaultwarden] ERROR: $*" >&2; exit 1; }

# opt NAME -> value as text; empty when unset or null. Booleans print true/false.
opt() {
  jq -r --arg k "$1" 'if has($k) and .[$k] != null then .[$k] | tostring else "" end' "$OPTIONS"
}

# forever NAME COMMAND... -> run COMMAND in the background, restarting it
# whenever it exits. The delay doubles (10s up to 5 min) while it keeps failing
# quickly, e.g. with a bad token or no network yet. Vaultwarden itself runs in
# the foreground, so the app stops (and the watchdog restarts it) only when
# Vaultwarden does.
forever() {
  name="$1"
  shift
  (
    delay=10
    while :; do
      started="$(date +%s)"
      "$@" || true
      [ "$(($(date +%s) - started))" -ge 60 ] && delay=10
      log "$name exited; restarting in ${delay}s"
      sleep "$delay"
      delay=$((delay * 2))
      [ "$delay" -gt 300 ] && delay=300
    done
  ) &
}

[ -f "$OPTIONS" ] || die "$OPTIONS not found. Is this running as a Home Assistant app?"

# --- Domain --------------------------------------------------------------------
domain="$(opt domain)"
[ -n "$domain" ] || die "Set the 'domain' option to the hostname clients will use, e.g. vault.example.com or vault.tail1234.ts.net."
case "$domain" in
  http://* | https://*) url="$domain" ;;
  *) url="https://$domain" ;;
esac
url="${url%/}"
host="$(printf '%s' "$url" | sed -E 's#^[A-Za-z]+://##; s#[/:].*$##')"
case "$url" in
  http://*) log "WARNING: 'domain' uses http://. The web vault and the Bitwarden apps need HTTPS." ;;
esac
export DOMAIN="$url"

# --- Fixed choices for running inside Home Assistant -------------------------
# SQLite and keys in /data (the app data folder). TLS is terminated by
# Cloudflare or Tailscale in front, so Vaultwarden serves plain HTTP on 8080.
export DATA_FOLDER=/data
export ROCKET_PORT=8080
# cloudflared and Tailscale Serve connect from localhost and set
# X-Forwarded-For. Only they are trusted to set it, so a LAN client using the
# optional host port can't fake its IP for rate limits and logs.
export IP_HEADER=X-Forwarded-For
export IP_HEADER_TRUSTED_PROXIES="127.0.0.1,::1"

log_level="$(opt log_level)"
export LOG_LEVEL="${log_level:-info}"

signups="$(opt signups_allowed)"
export SIGNUPS_ALLOWED="${signups:-true}"
if [ "$SIGNUPS_ALLOWED" = "true" ]; then
  log "Sign-ups are open: anyone who can reach the vault can create an account. Turn off 'signups_allowed' once your accounts exist."
fi

admin_token="$(opt admin_token)"
if [ -n "$admin_token" ]; then
  export ADMIN_TOKEN="$admin_token"
  # shellcheck disable=SC2016 # a literal "$argon2" prefix, not a variable
  case "$admin_token" in
    '$argon2'*) log "Admin panel: enabled at $url/admin (Argon2 token)" ;;
    *) log "Admin panel: enabled at $url/admin (plain-text token; an Argon2 hash is safer, see DOCS)" ;;
  esac
else
  log "Admin panel: disabled (no admin_token)"
fi

# --- SMTP (optional) ---------------------------------------------------------
smtp_host="$(opt smtp_host)"
if [ -n "$smtp_host" ]; then
  smtp_port="$(opt smtp_port)"
  smtp_security="$(opt smtp_security)"
  if [ -z "$smtp_security" ]; then
    if [ "$smtp_port" = "465" ]; then smtp_security=force_tls; else smtp_security=starttls; fi
  fi
  if [ -z "$smtp_port" ]; then
    case "$smtp_security" in
      force_tls) smtp_port=465 ;;
      starttls) smtp_port=587 ;;
      *) smtp_port=25 ;;
    esac
  fi
  smtp_from="$(opt smtp_from)"
  smtp_from_name="$(opt smtp_from_name)"
  export SMTP_HOST="$smtp_host"
  export SMTP_PORT="$smtp_port"
  export SMTP_SECURITY="$smtp_security"
  export SMTP_FROM="${smtp_from:-vaultwarden@$host}"
  export SMTP_FROM_NAME="${smtp_from_name:-Vaultwarden}"
  smtp_username="$(opt smtp_username)"
  if [ -n "$smtp_username" ]; then
    smtp_password="$(opt smtp_password)"
    export SMTP_USERNAME="$smtp_username"
    export SMTP_PASSWORD="$smtp_password"
  fi
  log "SMTP: $smtp_host:$smtp_port ($smtp_security), from $SMTP_FROM"
else
  log "SMTP not configured: email verification, invitations, emergency access and email 2FA will not work."
fi

# --- Mobile push notifications (optional) -------------------------------------
push_id="$(opt push_installation_id)"
push_key="$(opt push_installation_key)"
if [ -n "$push_id" ] && [ -n "$push_key" ]; then
  export PUSH_ENABLED=true
  export PUSH_INSTALLATION_ID="$push_id"
  export PUSH_INSTALLATION_KEY="$push_key"
  if [ "$(opt push_region)" = "eu" ]; then
    export PUSH_RELAY_URI=https://api.bitwarden.eu
    export PUSH_IDENTITY_URI=https://identity.bitwarden.eu
  fi
  log "Push notifications: enabled ($(opt push_region | sed 's/^$/us/') region)"
elif [ -n "$push_id$push_key" ]; then
  die "Set both 'push_installation_id' and 'push_installation_key', or neither."
fi

# --- Extra environment variables (applied last, so they override) ------------
count="$(jq '(.env_vars // []) | length' "$OPTIONS")"
i=0
while [ "$i" -lt "$count" ]; do
  name="$(jq -r ".env_vars[$i].name" "$OPTIONS")"
  value="$(jq -r ".env_vars[$i].value" "$OPTIONS")"
  case "$name" in
    "" | [0-9]* | *[!A-Za-z0-9_]*) die "env_vars: invalid variable name '$name'" ;;
  esac
  export "$name=$value"
  log "env_vars: set $name"
  i=$((i + 1))
done

if [ -f /data/config.json ]; then
  log "Note: settings saved in the admin panel (/data/config.json) override these options."
fi

# --- Optional helper programs ------------------------------------------------
mkdir -p "$RUN_DIR"
chmod 0700 "$RUN_DIR"
rm -f "$RUN_DIR"/cloudflared.token "$RUN_DIR"/tailscale.authkey

tunnel_token="$(opt cloudflare_tunnel_token)"
if [ -n "$tunnel_token" ]; then
  (umask 077 && printf '%s' "$tunnel_token" > "$RUN_DIR/cloudflared.token")
  forever cloudflared /usr/local/bin/cloudflared tunnel --no-autoupdate run --token-file "$RUN_DIR/cloudflared.token"
  log "Cloudflare Tunnel: enabled (point the tunnel's public hostname at http://localhost:8080)"
else
  log "Cloudflare Tunnel: disabled"
fi

if [ "$(opt tailscale)" = "true" ]; then
  mkdir -p /data/tailscale
  ts_auth_key="$(opt tailscale_auth_key)"
  if [ -n "$ts_auth_key" ]; then
    (umask 077 && printf '%s' "$ts_auth_key" > "$RUN_DIR/tailscale.authkey")
  fi
  ts_hostname="$(opt tailscale_hostname)"
  ts_funnel="$(opt tailscale_funnel)"
  # tailscaled is chatty; its own log only goes to the Log tab when debugging.
  case "$LOG_LEVEL" in
    trace | debug) ts_log=/proc/self/fd/1 ;;
    *) ts_log=/dev/null ;;
  esac
  # shellcheck disable=SC2016 # $1 is expanded by the inner sh
  forever tailscaled sh -c 'exec /usr/local/bin/tailscaled --tun=userspace-networking --statedir=/data/tailscale --socket=/tmp/ha/tailscaled.sock >"$1" 2>&1' tailscaled "$ts_log"
  (
    until TS_HOSTNAME="${ts_hostname:-vault}" TS_FUNNEL="${ts_funnel:-false}" VW_HOST="$host" /ha/tailscale-up.sh; do
      log "Tailscale setup failed; retrying in 30s"
      sleep 30
    done
  ) &
  log "Tailscale: enabled as '${ts_hostname:-vault}' (funnel: ${ts_funnel:-false})"
else
  log "Tailscale: disabled"
fi

log "Starting Vaultwarden for $url"
exec /start.sh
