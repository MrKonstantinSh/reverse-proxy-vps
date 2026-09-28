#!/bin/sh
# Запускается на VPS после синхронизации репозитория. Не удаляет тома
# с сертификатами и не перезаписывает .env.
set -eu

cd "$(dirname "$0")/.."

compose() {
	docker compose --project-name reverse-proxy -f docker-compose.yaml "$@"
}

if [ ! -f .env ]; then
	echo "На VPS нет файла .env. Скопируйте .env.example и заполните все переменные." >&2
	exit 1
fi

compose config --quiet

# Эти ресурсы могут уже принадлежать другому Compose project.
if ! docker network inspect proxy >/dev/null 2>&1; then
	docker network create --driver bridge proxy >/dev/null
fi
docker volume create caddy_data >/dev/null
docker volume create caddy_config >/dev/null

compose pull
compose up -d --wait --remove-orphans
compose exec -T caddy \
	/bin/sh /usr/local/bin/caddy-entrypoint.sh \
	caddy validate --config /etc/caddy/Caddyfile
compose exec -T caddy \
	/bin/sh /usr/local/bin/caddy-entrypoint.sh \
	caddy reload --config /etc/caddy/Caddyfile
compose ps
