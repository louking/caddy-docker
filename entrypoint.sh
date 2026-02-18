#!/bin/sh
set -e
set -x

echo "Setting permissions for $WWW_DIR to caddy:caddy (uid: ${CADDY_UID}, gid: ${CADDY_GID})"

# 2. Change ownership and permissions
# -R: Recursive for all files
mkdir -p /var/log/caddy
chown -R caddy:caddy /var/log/caddy
chown -R caddy:caddy "/data"

# If DEBUG is unset or "false" (case-insensitive) -> run start_weewx.sh
# Otherwise sleep forever.

case "${DEBUG:-}" in
    ""|[Ff][Aa][Ll][Ss][Ee])
        # no "-" like su - weewx, per https://unix.stackexchange.com/a/341259/669764
        # else PATH and other env vars get reset
        su-exec caddy "$@"
        ;;
    *)
        # exec su - weewx -c 'sleep 99999999'
        su-exec caddy 'tail -f /dev/null'
        ;;
esac