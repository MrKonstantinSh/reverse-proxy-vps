#!/bin/sh
set -eu

export OPENHANDS_PASSWORD_HASH="$(caddy hash-password --plaintext "$OPENHANDS_PASSWORD")"
exec "$@"
