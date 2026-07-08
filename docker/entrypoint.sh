#!/bin/sh
set -e

if [ -n "$DATABASE_URL" ]; then
    export DB_URL="$DATABASE_URL"
fi

php artisan config:cache
php artisan route:cache
php artisan migrate --force

exec supervisord -c /etc/supervisord.conf
