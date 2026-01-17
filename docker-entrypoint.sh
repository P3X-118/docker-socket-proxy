#!/bin/sh
set -eu

log() { printf '%s\n' "$*" >&2; }

# Raise default nofile limit for HAProxy v3 (best-effort)
ulimit -n 10000 2>/dev/null || true

# IPv6 is ALWAYS disabled: bind IPv4 only
BIND_CONFIG=":2375"
log "IPv6 forced disabled: binding IPv4 only ($BIND_CONFIG)"

# Best-effort OS-level IPv6 disable inside the container/namespace.
# (May fail if /proc/sys is read-only or not permitted; that's ok.)
disable_ipv6_sysctl() {
  for p in \
    /proc/sys/net/ipv6/conf/all/disable_ipv6 \
    /proc/sys/net/ipv6/conf/default/disable_ipv6 \
    /proc/sys/net/ipv6/conf/lo/disable_ipv6
  do
    if [ -w "$p" ]; then
      printf '1' > "$p" 2>/dev/null || true
    fi
  done
}
disable_ipv6_sysctl

TEMPLATE=/usr/local/etc/haproxy/haproxy.cfg.template
OUT=/tmp/haproxy.cfg

if [ ! -r "$TEMPLATE" ]; then
  log "ERROR: template not found or not readable: $TEMPLATE"
  exit 1
fi

# Escape replacement for sed (&, /, \)
escape_sed_repl() {
  printf '%s' "$1" | sed 's/[\/&\\]/\\&/g'
}
BIND_ESCAPED=$(escape_sed_repl "$BIND_CONFIG")

# Fail fast if placeholder isn't present
if ! grep -q '\${BIND_CONFIG}' "$TEMPLATE"; then
  log "ERROR: template does not contain \${BIND_CONFIG} placeholder"
  exit 1
fi

# Render config
sed "s/\${BIND_CONFIG}/${BIND_ESCAPED}/g" "$TEMPLATE" > "$OUT"

# If first arg looks like an option, prepend haproxy
if [ "${1:-}" != "" ] && [ "${1#-}" != "$1" ]; then
  set -- haproxy "$@"
fi

# Default command if nothing provided
if [ "${1:-}" = "" ]; then
  set -- haproxy
fi

if [ "$1" = "haproxy" ]; then
  shift
  # master-worker, no daemon; and make sure we use the rendered config
  set -- haproxy -W -db -f "$OUT" "$@"
fi

exec "$@"
