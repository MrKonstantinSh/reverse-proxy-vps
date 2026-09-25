# Agent Guide

## Project Purpose

Docker Compose deployment of Caddy 2.11.4 as a VPS reverse proxy. GitHub
Actions deploys tag `v*` from `main` over SSH; real `DOMAIN` / `ACME_EMAIL`
live in `.env` on the VPS (not in git).

## Repository Rules

- Keep the Caddy image pinned to `caddy:2.11.4` unless the user explicitly
  requests an upgrade.
- Keep the shared Docker network named `proxy`.
- Publish only Caddy's `80/tcp`, `443/tcp`, and `443/udp` ports. Do not expose
  upstream application ports through this Compose project.
- Store certificates and Caddy state in persistent Docker volumes.
- Never commit `.env`, credentials, certificates, or private keys. Update
  `.env.example` when a new required variable is introduced.
- Add a new upstream as a file under `sites/*.caddy`; do not fold service
  routes back into the root `Caddyfile`.
- Keep user-facing documentation and configuration comments in Russian unless
  the user requests another language.
- CI `DOMAIN` / `ACME_EMAIL` (`example.com`, `ops@example.com`) are placeholders
  for Compose interpolation and `caddy validate` only. Do not treat them as
  production values or copy them onto the VPS.

## Files

- `docker-compose.yaml` — Caddy service, ports, volumes, and the `proxy` network.
- `Caddyfile` — global options, shared snippets, and import of `sites/*.caddy`.
- `sites/` — one Caddy site file per service; `app.caddy.example` is the template.
- `.env.example` — blank example values for `DOMAIN` and `ACME_EMAIL`.
- `scripts/remote-deploy.sh` — VPS-side compose up and Caddy reload.
- `.github/workflows/` — validate on `main`/PRs; deploy on tags `v*`.
- `README.md` — deployment and integration instructions.

## Validation

Use the same placeholders as CI:

```sh
DOMAIN=example.com ACME_EMAIL=ops@example.com docker compose -f docker-compose.yaml config --quiet
docker run --rm \
  -e DOMAIN=example.com \
  -e ACME_EMAIL=ops@example.com \
  -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" \
  -v "$PWD/sites:/etc/caddy/sites:ro" \
  caddy:2.11.4 \
  caddy validate --config /etc/caddy/Caddyfile
git diff --check
```

For runtime changes on a host that already has `.env`, inspect startup logs:

```sh
docker compose -f docker-compose.yaml up -d
docker compose -f docker-compose.yaml ps
docker compose -f docker-compose.yaml logs caddy
```
