#!/bin/sh
set -e

if [ -n "$DATABASE_URL" ]; then
    export DB_URL="$DATABASE_URL"
fi

export PORT="${PORT:-8080}"
envsubst '${PORT}' < /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf

php artisan config:cache
php artisan route:cache
php artisan migrate --force

exec supervisord -c /etc/supervisord.conf
