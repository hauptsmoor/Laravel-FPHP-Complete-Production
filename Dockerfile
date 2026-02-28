ARG PHP_VERSION=8.4

# Stage 1: Extract Valkey binaries
FROM valkey/valkey:8-bookworm AS valkey

# Stage 2: Final image based on FrankenPHP
FROM dunglas/frankenphp:1-php${PHP_VERSION}-bookworm

LABEL org.opencontainers.image.source="https://github.com/hauptsmoor/Laravel-FPHP-Complete-Production"
LABEL org.opencontainers.image.description="Production-ready Laravel container with FrankenPHP, supervisord, and optional services"
LABEL org.opencontainers.image.licenses="MIT"

# Copy Valkey binaries from stage 1
COPY --from=valkey /usr/local/bin/valkey-server /usr/local/bin/valkey-server
COPY --from=valkey /usr/local/bin/valkey-cli /usr/local/bin/valkey-cli

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    libpq-dev \
    libzip-dev \
    libicu-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libwebp-dev \
    libfreetype6-dev \
    libmagickwand-dev \
    libsodium-dev \
    libxml2-dev \
    libexif-dev \
    libev-dev \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN install-php-extensions \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    pdo_sqlite \
    redis \
    gd \
    imagick \
    intl \
    zip \
    bcmath \
    soap \
    exif \
    opcache \
    sockets \
    ev \
    excimer

# Make /tmp writable for read-only root filesystem
ENV TMPDIR=/dev/shm
RUN rm -rf /tmp && ln -s ${TMPDIR} /tmp

# Configure OPcache for production performance
RUN cat > /usr/local/etc/php/conf.d/opcache-recommended.ini <<'EOF'
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=64
opcache.max_accelerated_files=32531
opcache.validate_timestamps=0
opcache.save_comments=1
opcache.enable_cli=0
EOF

# Configure PHP for production and read-only root filesystem
RUN cat > /usr/local/etc/php/conf.d/docker-php.ini <<'EOF'
upload_tmp_dir=/tmp
sys_temp_dir=/tmp
upload_max_filesize=64M
post_max_size=64M
memory_limit=256M
max_execution_time=60
expose_php=Off
EOF

# Create valkey user
RUN groupadd -r valkey && useradd -r -g valkey valkey

# Create directory structure
RUN mkdir -p \
    /app/public \
    /data/valkey \
    /data/caddy \
    /config/caddy \
    /etc/supervisor/available \
    /etc/supervisor/conf.d \
    /etc/valkey \
    && chown valkey:valkey /data/valkey

# Copy configuration files
COPY Caddyfile /etc/caddy/Caddyfile
COPY supervisord/frankenphp.conf /etc/supervisor/available/
COPY supervisord/scheduler.conf /etc/supervisor/available/
COPY supervisord/queue.conf /etc/supervisor/available/
COPY supervisord/horizon.conf /etc/supervisor/available/
COPY supervisord/valkey.conf /etc/supervisor/available/
COPY supervisord/reverb.conf /etc/supervisor/available/
COPY supervisord/pulse.conf /etc/supervisor/available/
COPY valkey/valkey.conf /etc/valkey/valkey.conf
COPY entrypoint.sh /entrypoint.sh

# Create base supervisord config (uses /tmp for writable paths → /dev/shm)
RUN cat > /etc/supervisor/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid
user=root

[unix_http_server]
file=/tmp/supervisor.sock

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[include]
files = /etc/supervisor/conf.d/*.conf
EOF

RUN chmod +x /entrypoint.sh

WORKDIR /app

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
