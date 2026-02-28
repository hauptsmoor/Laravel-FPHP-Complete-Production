# Laravel FrankenPHP Production Container

A production-ready, single-container Docker image for Laravel applications using [FrankenPHP](https://frankenphp.dev/). Includes optional services (scheduler, queue worker, Horizon, Valkey cache, Reverb, Pulse) managed by supervisord and configurable through environment variables. Designed for read-only root filesystem operation.

## Quick Start

```yaml
# docker-compose.yml
services:
  app:
    image: ghcr.io/hauptsmoor/laravel-fphp:latest
    ports:
      - "8080:8080"
    volumes:
      - ./:/app:ro
      - app_storage:/app/storage
      - app_cache:/app/bootstrap/cache
    environment:
      VALKEY: "true"
      SCHEDULER: "true"
      QUEUE: "true"
      AUTO_MIGRATE: "true"

volumes:
  app_storage:
  app_cache:
```

```bash
docker compose up -d
```

## Available Images

| Tag | PHP Version | Notes |
|-----|------------|-------|
| `ghcr.io/hauptsmoor/laravel-fphp:latest-php8.3` | 8.3 | LTS |
| `ghcr.io/hauptsmoor/laravel-fphp:latest-php8.4` | 8.4 | Current stable |
| `ghcr.io/hauptsmoor/laravel-fphp:latest-php8.5` | 8.5 | Latest |
| `ghcr.io/hauptsmoor/laravel-fphp:latest` | 8.4 | Alias for latest-php8.4 |

Tagged releases are also available as `v1.0.0-php8.4`, etc.

## What's Included

### Base Image
- **FrankenPHP** (Debian Bookworm) as the web server
- **Supervisord** for process management
- **Valkey** binary (extracted from official image, runs only when enabled)
- **OPcache** tuned for production (256MB, file timestamp validation disabled)

### Pre-installed PHP Extensions

All extensions required by Laravel and its ecosystem:

`pcntl` `pdo_mysql` `pdo_pgsql` `pdo_sqlite` `redis` `gd` `imagick` `intl` `zip` `bcmath` `soap` `exif` `opcache` `sockets` `ev` `excimer`

Plus the extensions bundled with the FrankenPHP image: `mbstring` `openssl` `curl` `xml` `ctype` `tokenizer` `fileinfo` `dom` `phar` `iconv` `sodium`

## Environment Variables

### Service Activation

Set to `"true"` to enable. All services are **disabled by default**.

| Variable | Service | Command |
|----------|---------|---------|
| `SCHEDULER` | Laravel Scheduler | `php artisan schedule:work` |
| `QUEUE` | Queue Worker | `php artisan queue:work --sleep=3 --tries=3` |
| `HORIZON` | Laravel Horizon | `php artisan horizon` |
| `VALKEY` | Valkey Cache Server | `valkey-server` on port 6379 |
| `REVERB` | Laravel Reverb | `php artisan reverb:start` |
| `PULSE_CHECK` | Laravel Pulse | `php artisan pulse:check` |

> **Note:** If both `QUEUE` and `HORIZON` are set to `"true"`, the standalone queue worker is automatically disabled since Horizon manages queue workers itself.

### Startup Behavior

On every boot, the container automatically runs `php artisan optimize` (caches config, routes, views, events) for best performance.

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTO_MIGRATE` | (unset) | Set to `"true"` to run `php artisan migrate --force` on startup |
| `SKIP_OPTIMIZE` | (unset) | Set to `"true"` to skip `php artisan optimize` on startup |

### Tuning

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_PORT` | `8080` | HTTP port for FrankenPHP |
| `QUEUE_WORKERS` | `1` | Number of queue worker processes |
| `REVERB_PORT` | `6001` | Port for Reverb WebSocket server |

## Directory Layout

| Path | Purpose | Writable |
|------|---------|----------|
| `/app` | Laravel application root | No (read-only) |
| `/app/public` | Web root served by FrankenPHP | No |
| `/app/storage` | Laravel storage (logs, cache, sessions, views) | **Yes (volume)** |
| `/app/bootstrap/cache` | Laravel bootstrap cache | **Yes (volume)** |
| `/data/valkey` | Valkey data directory | **Yes (volume)** |
| `/tmp` | Temp files (symlink to /dev/shm) | **Yes (tmpfs)** |
| `/etc/caddy/Caddyfile` | FrankenPHP/Caddy configuration | No |
| `/etc/supervisor/available/` | Available supervisord service configs | No |
| `/etc/supervisor/conf.d/` | Active supervisord configs (populated at startup) | **Yes (tmpfs)** |
| `/etc/valkey/valkey.conf` | Valkey configuration | No |

## Usage

This image supports two usage patterns:

### Option A: Mount your code (development / volume-based)

Mount your Laravel project read-only into `/app` with writable volumes for storage:

```bash
docker run -p 8080:8080 \
  -v ./my-laravel-app:/app:ro \
  -v app_storage:/app/storage \
  -v app_cache:/app/bootstrap/cache \
  ghcr.io/hauptsmoor/laravel-fphp:latest
```

### Option B: Use as a base image (production / baked-in)

Create your own `Dockerfile` that copies your Laravel code into the image:

```dockerfile
FROM ghcr.io/hauptsmoor/laravel-fphp:latest

COPY . /app

RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache
```

Or with a Composer install step using a multi-stage build:

```dockerfile
FROM composer:latest AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist

FROM ghcr.io/hauptsmoor/laravel-fphp:latest
COPY --from=vendor /app/vendor /app/vendor
COPY . /app
RUN chown -R www-data:www-data /app/storage /app/bootstrap/cache
```

Then in your `docker-compose.yml`:

```yaml
services:
  app:
    build: .
    read_only: true
    ports:
      - "8080:8080"
    volumes:
      - app_storage:/app/storage
      - app_cache:/app/bootstrap/cache
    tmpfs:
      - /tmp:size=64M
      - /var/run:size=1M
      - /data/caddy:size=1M
      - /config/caddy:size=1M
      - /etc/supervisor/conf.d:size=1M
    environment:
      VALKEY: "true"
      SCHEDULER: "true"

volumes:
  app_storage:
  app_cache:
```

## Read-Only Root Filesystem

This image is designed to run with `read_only: true` in Docker Compose. The following writable paths must be provided:

### Required Volumes
| Mount Point | Type | Purpose |
|-------------|------|---------|
| `/app/storage` | volume | Laravel storage (logs, sessions, cache, views) |
| `/app/bootstrap/cache` | volume | Laravel compiled services and packages |

### Required tmpfs Mounts
| Mount Point | Size | Purpose |
|-------------|------|---------|
| `/tmp` | 64M | PHP uploads, temp files (symlinked to /dev/shm) |
| `/var/run` | 1M | Runtime PID files |
| `/data/caddy` | 1M | Caddy state |
| `/config/caddy` | 1M | Caddy config state |
| `/etc/supervisor/conf.d` | 1M | Active supervisor configs (assembled at startup) |

### Optional Volumes
| Mount Point | Type | Purpose |
|-------------|------|---------|
| `/data/valkey` | volume | Valkey data (only needed if `VALKEY=true`) |

The entrypoint automatically creates the required Laravel storage subdirectories (`storage/app/public`, `storage/logs`, `storage/framework/cache/data`, `storage/framework/sessions`, `storage/framework/views`) on startup.

### Full docker-compose example

See [docker-compose.example.yml](docker-compose.example.yml) for a complete example with MariaDB.

## Valkey Configuration

When `VALKEY=true`, an embedded Valkey server runs inside the container with these defaults:

- **Bind:** `127.0.0.1` (container-local only)
- **Port:** `6379`
- **Max memory:** `256mb`
- **Eviction policy:** `allkeys-lru`
- **Persistence:** Disabled (cache-only mode)
- **Data directory:** `/data/valkey`

Set `REDIS_HOST=127.0.0.1` in your Laravel `.env` to use it.

## OPcache Configuration

OPcache is pre-configured for production with these settings:

- `memory_consumption=256` (256 MB for compiled scripts)
- `interned_strings_buffer=64` (64 MB for interned strings)
- `max_accelerated_files=32531` (max cached scripts)
- `validate_timestamps=0` (files are never rechecked - best for production)

Since `validate_timestamps=0`, file changes are only picked up after restarting the container (or running `php artisan optimize`).

## Building Locally

```bash
# Build for PHP 8.4
docker build --build-arg PHP_VERSION=8.4 -t laravel-fphp:test .

# Build for PHP 8.3
docker build --build-arg PHP_VERSION=8.3 -t laravel-fphp:php83 .
```

## CI/CD

Images are automatically built and pushed to `ghcr.io` via GitHub Actions on:
- Push to `main` branch
- Git tag push (e.g., `v1.0.0`)
- Manual workflow dispatch

The workflow builds images for PHP 8.3, 8.4, and 8.5 in parallel.

## License

[MIT](LICENSE)
