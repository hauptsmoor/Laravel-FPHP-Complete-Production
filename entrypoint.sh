#!/bin/bash
set -e

echo "[entrypoint] Configuring services..."

# --- Create required Laravel storage directories ---
# These must exist even when /app/storage is an empty volume mount
mkdir -p /app/storage/app/public
mkdir -p /app/storage/logs
mkdir -p /app/storage/framework/cache/data
mkdir -p /app/storage/framework/sessions
mkdir -p /app/storage/framework/views
mkdir -p /app/bootstrap/cache

# --- Clean conf.d and assemble supervisord config ---
rm -f /etc/supervisor/conf.d/*.conf

# Always enable FrankenPHP web server
cp /etc/supervisor/available/frankenphp.conf /etc/supervisor/conf.d/

# Conditionally enable Valkey (starts first due to priority=50)
if [ "${VALKEY,,}" = "true" ]; then
    echo "[entrypoint] Enabling Valkey cache server"
    cp /etc/supervisor/available/valkey.conf /etc/supervisor/conf.d/
fi

# Conditionally enable scheduler
if [ "${SCHEDULER,,}" = "true" ]; then
    echo "[entrypoint] Enabling scheduler"
    cp /etc/supervisor/available/scheduler.conf /etc/supervisor/conf.d/
fi

# Conditionally enable queue worker
if [ "${QUEUE,,}" = "true" ]; then
    echo "[entrypoint] Enabling queue worker"
    cp /etc/supervisor/available/queue.conf /etc/supervisor/conf.d/
fi

# Conditionally enable Horizon
if [ "${HORIZON,,}" = "true" ]; then
    echo "[entrypoint] Enabling Horizon"
    cp /etc/supervisor/available/horizon.conf /etc/supervisor/conf.d/
fi

# Horizon manages queues itself - disable standalone queue worker if both are set
if [ "${QUEUE,,}" = "true" ] && [ "${HORIZON,,}" = "true" ]; then
    echo "[entrypoint] WARNING: Both QUEUE and HORIZON are enabled. Horizon already manages queue workers. Disabling standalone QUEUE worker."
    rm -f /etc/supervisor/conf.d/queue.conf
fi

# Conditionally enable Reverb WebSocket server
if [ "${REVERB,,}" = "true" ]; then
    echo "[entrypoint] Enabling Reverb WebSocket server"
    cp /etc/supervisor/available/reverb.conf /etc/supervisor/conf.d/
fi

# Conditionally enable Pulse health check
if [ "${PULSE_CHECK,,}" = "true" ]; then
    echo "[entrypoint] Enabling Pulse check"
    cp /etc/supervisor/available/pulse.conf /etc/supervisor/conf.d/
fi

# --- Set defaults for configurable values ---
export QUEUE_WORKERS="${QUEUE_WORKERS:-1}"
export REVERB_PORT="${REVERB_PORT:-6001}"

# --- Startup hooks ---
if [ -f /app/artisan ]; then
    # Run migrations if requested
    if [ "${AUTO_MIGRATE,,}" = "true" ]; then
        echo "[entrypoint] Running migrations..."
        php /app/artisan migrate --force
    fi

    # Always run optimizations unless explicitly skipped
    if [ "${SKIP_OPTIMIZE,,}" != "true" ]; then
        echo "[entrypoint] Optimizing application..."
        php /app/artisan optimize
    fi
fi

echo "[entrypoint] Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
