#!/bin/sh
# Запускается на VPS после синхронизации репозитория. Не удаляет тома
# с сертификатами и не перезаписывает .env.
set -eu

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
	echo "На VPS нет файла .env. Скопируйте .env.example и заполните DOMAIN и ACME_EMAIL." >&2
	exit 1
fi

docker compose -f docker-compose.yaml config --quiet
docker compose -f docker-compose.yaml pull
docker compose -f docker-compose.yaml up -d --wait --remove-orphans
docker compose -f docker-compose.yaml exec -T caddy caddy validate --config /etc/caddy/Caddyfile
docker compose -f docker-compose.yaml exec -T caddy caddy reload --config /etc/caddy/Caddyfile
docker compose -f docker-compose.yaml ps
