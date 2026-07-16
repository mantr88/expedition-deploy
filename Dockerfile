# syntax=docker/dockerfile:1.6

ARG BACKEND_REPO=https://github.com/mantr88/expedition-backend.git
ARG FRONTEND_REPO=https://github.com/mantr88/expedition-frontend.git
ARG BACKEND_REF=main
ARG FRONTEND_REF=main

# ---------- Stage 1: клонування репо (публічні, без авторизації) ----------
FROM alpine/git:2.45.2 AS sources
ARG BACKEND_REPO
ARG FRONTEND_REPO
ARG BACKEND_REF
ARG FRONTEND_REF

RUN git clone --depth 1 --branch "${BACKEND_REF}" "${BACKEND_REPO}" /src/backend && \
    git clone --depth 1 --branch "${FRONTEND_REF}" "${FRONTEND_REPO}" /src/frontend

# ---------- Stage 2: збірка фронтенду ----------
FROM node:20-alpine AS frontend
WORKDIR /app

ARG VITE_USE_MOCKS=false
ARG VITE_API_BASE_URL=
ARG VITE_REVERB_HOST=expedition-demo.fly.dev
ARG VITE_REVERB_APP_KEY

ENV VITE_USE_MOCKS=$VITE_USE_MOCKS
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
ENV VITE_REVERB_HOST=$VITE_REVERB_HOST
ENV VITE_REVERB_APP_KEY=$VITE_REVERB_APP_KEY

COPY --from=sources /src/frontend/package.json /src/frontend/package-lock.json ./
RUN npm ci
COPY --from=sources /src/frontend/. .
# .env.production фронтенду має вказувати на прод-адресу API/WS (див. розділ 8)
RUN npm run build

# ---------- Stage 3: PHP-залежності бекенду ----------
FROM composer:2 AS vendor
WORKDIR /app
COPY --from=sources /src/backend/composer.json /src/backend/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --optimize-autoloader --ignore-platform-reqs

# ---------- Stage 4: фінальний образ ----------
FROM php:8.4-fpm-alpine

RUN apk add --no-cache nginx supervisor postgresql-dev git \
    && docker-php-ext-install pdo pdo_pgsql opcache pcntl

WORKDIR /var/www/html

# Код бекенду
COPY --from=sources /src/backend/. .
COPY --from=vendor /app/vendor ./vendor
COPY --from=vendor /usr/bin/composer /usr/bin/composer

# Білд фронтенду кладемо в public/ як статичні файли
# Якщо у фронтенд-репо svелективний SPA (не Laravel Blade) - роздаємо як статику окремою локацією nginx
COPY --from=frontend /app/dist ./public/spa

RUN composer dump-autoload --optimize \
    && mkdir -p storage/framework/{sessions,views,cache} storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

COPY docker/nginx.conf /etc/nginx/http.d/default.conf
COPY docker/supervisord.conf /etc/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
