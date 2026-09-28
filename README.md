# Reverse proxy на Caddy

Репозиторий содержит конфигурацию Caddy 2.11.4 для VPS. Caddy принимает HTTP/HTTPS
и HTTP/3 и направляет трафик к сервисам в Docker-сети `proxy`. Маршруты живут
в отдельных файлах: новый сервис — это DNS, один файл в `sites/` и тег на `main`.

Развёртывание на VPS идёт через GitHub Actions при создании тега `v*`, который
указывает на коммит из ветки `main`.

## Состав

- `docker-compose.yaml` — контейнер `caddy:2.11.4`, порты, тома, сеть `proxy`.
- `Caddyfile` — глобальные настройки TLS и общие сниппеты.
- `sites/*.caddy` — маршруты сервисов (один файл на сервис).
- `sites/app.caddy.example` — шаблон маршрута.
- `.env` на сервере — домен, email и учетные данные OpenHands (в git не коммитится).
- `scripts/remote-deploy.sh` — обновление контейнера на VPS без удаления сертификатов.
- `.github/workflows/validate.yml` — проверка Compose и Caddyfile.
- `.github/workflows/deploy.yml` — выкладка по тегу.

С хоста опубликованы только `80/tcp`, `443/tcp` и `443/udp`. Admin API Caddy
слушает `127.0.0.1:2019` внутри контейнера и наружу не выставлен.

Сертификаты и состояние Caddy хранятся в томах `caddy_data` и `caddy_config`.
Контейнер перезапускается после сбоя (`restart: unless-stopped`), файловая
система контейнера только для чтения, лишние Linux capabilities сняты.

## Требования

- VPS с Docker Engine и Docker Compose v2.
- DNS `A` (и при необходимости `AAAA`) для каждого поддомена на адрес VPS.
- В firewall открыты `80/tcp`, `443/tcp`, `443/udp`.
- Репозиторий на GitHub и SSH-доступ деплоя к VPS.

## Первичная подготовка VPS

Один раз на сервере:

```sh
sudo mkdir -p /opt/reverse-proxy
sudo chown "$USER:$USER" /opt/reverse-proxy
cd /opt/reverse-proxy
```

Создайте `.env` из примера репозитория и заполните значения:

```dotenv
DOMAIN=example.com
ACME_EMAIL=ops@example.com
OPENHANDS_USER=your-login
OPENHANDS_PASSWORD='your-password'
```

Пароль хранится в `.env` в открытом виде, но Caddy перед запуском преобразует
его в bcrypt-хеш. После первого ввода браузер обычно отправляет данные Basic
авторизации автоматически. Срок их кэширования определяет браузер: протокол
HTTP Basic не позволяет серверу установить точный срок в один час.

Пользователь деплоя должен уметь вызывать `docker` без интерактивного sudo
(группа `docker` или эквивалент). Каталог деплоя должен совпадать с секретом
`VPS_DEPLOY_PATH`.

Скрипт деплоя создаёт сеть `proxy` и тома `caddy_data` / `caddy_config`, если
их ещё нет. Compose использует их как внешние ресурсы, поэтому уже созданные
сеть и тома переиспользуются независимо от имени Compose project, а `down`
или `down -v` их не удаляет. Приложения подключайте к сети `proxy` как к
внешней (`external: true`).

## Подключение сервиса

1. Поднимите приложение в отдельном Compose-проекте в сети `proxy`. Порт
   приложения на хост публиковать не нужно.

```yaml
services:
  app:
    image: your-app:latest
    networks:
      proxy:
        aliases:
          - app

networks:
  proxy:
    external: true
    name: proxy
```

2. Добавьте DNS: например `app.example.com` → IP VPS.

3. Скопируйте шаблон и поправьте поддомен, имя контейнера и порт:

```sh
cp sites/app.caddy.example sites/app.caddy
```

```caddy
app.{$DOMAIN} {
	import upstream app:3000
}
```

Сниппет `upstream` включает сжатие, базовые заголовки безопасности и
`reverse_proxy`. Если нужны свои заголовки или health-check бэкенда, опишите
блок сайта явно вместо `import upstream`.

4. Закоммитьте файл в `main` и поставьте новый тег `v…`. Actions синхронизирует
   файлы на VPS и перезагрузит Caddy. Невалидная конфигурация не применяется:
   предыдущие маршруты продолжают работать.

Несколько сервисов — несколько файлов в `sites/`. Имя файла должно заканчиваться
на `.caddy`.

## Секреты GitHub

В Settings → Secrets and variables → Actions:

| Секрет | Назначение |
| --- | --- |
| `VPS_HOST` | Хост SSH (IP или DNS). |
| `VPS_USER` | Пользователь SSH на VPS. |
| `VPS_SSH_KEY` | Приватный ключ (без пароля) для этого пользователя. |
| `VPS_SSH_KNOWN_HOSTS` | Строка `ssh-keyscan` для хоста, чтобы не отключать проверку ключа. |
| `VPS_DEPLOY_PATH` | Каталог на VPS, например `/opt/reverse-proxy`. |
| `VPS_SSH_PORT` | Необязательно, по умолчанию `22`. |

Пример отпечатка хоста:

```sh
ssh-keyscan -p 22 YOUR_VPS_HOST
```

Публичную часть ключа добавьте в `~/.ssh/authorized_keys` пользователя деплоя.
Не коммитьте `.env`, ключи и сертификаты.

## Деплой с помощью тега

1. Изменения маршрутов попали в `main`.
2. Создайте аннотированный или легковесный тег вида `v1.2.0` на этом коммите.
3. `git push origin v1.2.0`.

Workflow проверяет, что коммит тега уже есть в `main`, валидирует конфиг,
копирует файлы через `rsync` (`.env` на сервере не затирается) и запускает
`scripts/remote-deploy.sh`: проверяет конфигурацию, создаёт недостающие общие
ресурсы, обновляет контейнер с ожиданием healthcheck, затем выполняет
`caddy reload`. Существующие сеть и тома переиспользуются, тома с сертификатами
не удаляются.

Тег с коммита вне `main` деплой отклонит.

## Ручная проверка на VPS

```sh
docker compose -f docker-compose.yaml config
docker compose -f docker-compose.yaml ps
docker compose -f docker-compose.yaml logs -f caddy
```

После успешного деплоя откройте `https://app.example.com` (или ваш поддомен).
Caddy сам получает и продлевает сертификаты Let's Encrypt.

## Остановка

```sh
docker compose -f docker-compose.yaml down
```

Сеть `proxy` и тома с сертификатами сохраняются и после `down -v`, поскольку
они объявлены как внешние ресурсы. Для полного сброса TLS-состояния остановите
проект и удалите тома явно: `docker volume rm caddy_data caddy_config`.
