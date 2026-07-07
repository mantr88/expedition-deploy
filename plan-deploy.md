# Деплой на Fly.io — окремий deploy-репозиторій (Варіант 1)

Ситуація: backend (Laravel + Reverb) і frontend (Vue) лежать у двох окремих git-репозиторіях.
Рішення: третій, суто інфраструктурний репозиторій `messenger-deploy`, який на етапі `docker build` клонує обидва репо і збирає їх в один образ.

---

## 1. Структура репозиторію `messenger-deploy`

```
messenger-deploy/
├── Dockerfile
├── fly.toml
├── .dockerignore
└── docker/
    ├── nginx.conf
    ├── supervisord.conf
    └── entrypoint.sh
```

Це єдиний репозиторій, який трима лише деплой-конфігурацію — сам код лишається у ваших backend/frontend репо без змін.

---

## 2. Доступ до приватних репозиторіїв

Оскільки Dockerfile буде робити `git clone` приватних репо всередині build-стадії, знадобиться токен доступу (GitLab Personal/Project Access Token або GitHub PAT з правом `read_repository`).

**Критично: токен передається тільки через `--build-secret`, ніколи через `ARG`/`ENV`**, інакше він залишиться в шарах образу назавжди, навіть якщо видалити його пізніше.

```bash
fly secrets set GIT_CLONE_TOKEN=glpat-xxxxxxxxxxxx
```

Це збереже токен як Fly secret — використаємо його на деплої через `--build-secret`.

---

## 3. `.dockerignore`

```
.git
fly.toml
README.md
```

---

## 4. `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1.6

ARG BACKEND_REPO=git@gitlab.com:your-group/messenger-backend.git
ARG FRONTEND_REPO=git@gitlab.com:your-group/messenger-frontend.git
ARG BACKEND_REF=main
ARG FRONTEND_REF=main

# ---------- Stage 1: клонування репо (з приватним доступом через secret) ----------
FROM alpine/git:2.45.2 AS sources
ARG BACKEND_REPO
ARG FRONTEND_REPO
ARG BACKEND_REF
ARG FRONTEND_REF

RUN --mount=type=secret,id=git_token \
    GIT_TOKEN=$(cat /run/secrets/git_token) && \
    git clone --depth 1 --branch "${BACKEND_REF}" \
      "https://oauth2:${GIT_TOKEN}@${BACKEND_REPO#https://}" /src/backend && \
    git clone --depth 1 --branch "${FRONTEND_REF}" \
      "https://oauth2:${GIT_TOKEN}@${FRONTEND_REPO#https://}" /src/frontend

# ---------- Stage 2: збірка фронтенду ----------
FROM node:20-alpine AS frontend
WORKDIR /app
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
FROM php:8.3-fpm-alpine

RUN apk add --no-cache nginx supervisor postgresql-dev git \
    && docker-php-ext-install pdo pdo_pgsql opcache

WORKDIR /var/www/html

# Код бекенду
COPY --from=sources /src/backend/. .
COPY --from=vendor /app/vendor ./vendor

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
```

**Пояснення ключових рядків:**

- `--mount=type=secret,id=git_token` — це BuildKit-механізм, токен доступний тільки під час виконання цього конкретного `RUN`, і не потрапляє в жоден шар образу.
- `git clone https://oauth2:${GIT_TOKEN}@...` — стандартний спосіб автентифікації по HTTPS з токеном для GitLab. Для GitHub аналогічно, тільки замість `oauth2` підставляється сам токен: `https://${GIT_TOKEN}@github.com/...`.
- Фронтенд копіюється в `public/spa` — окрема піддиректорія, щоб не змішувати з Laravel `public/index.php`, `public/build` тощо. nginx нижче роздає її під окремим шляхом.

---

## 5. `docker/nginx.conf`

Тут дві задачі: роздати Laravel API + Reverb WS, і окремо — статичний SPA фронтенду.

```nginx
server {
    listen 8080;
    root /var/www/html/public;
    index index.php;

    # --- WebSocket (Reverb) ---
    location /app {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # --- Статика Vue SPA ---
    location / {
        root /var/www/html/public/spa;
        try_files $uri $uri/ /index.html;
    }

    # --- Laravel API ---
    location /api {
        try_files $uri /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME /var/www/html/public/index.php;
        include fastcgi_params;
    }
}
```

Тобто корінь `/` віддає Vue SPA (`index.html` + assets), `/api/*` іде в Laravel, `/app/*` — в Reverb. Один домен, без CORS-головного болю, все ще з двох різних кодових баз.

---

## 6. `docker/supervisord.conf`

```ini
[supervisord]
nodaemon=true

[program:php-fpm]
command=php-fpm
autorestart=true

[program:nginx]
command=nginx -g "daemon off;"
autorestart=true

[program:reverb]
command=php artisan reverb:start --host=0.0.0.0 --port=8081
autorestart=true

[program:queue]
command=php artisan queue:work --sleep=3 --tries=3
autorestart=true
```

---

## 7. `docker/entrypoint.sh`

```bash
#!/bin/sh
set -e

php artisan config:cache
php artisan route:cache
php artisan migrate --force

exec supervisord -c /etc/supervisord.conf
```

---

## 8. Налаштування фронтенду під прод (важливо!)

Оскільки тепер API і фронт на одному домені, у фронтенд-репо `.env.production` (або `vite.config.ts` defines) має вказувати відносні шляхи, а не `localhost`:

```
VITE_API_URL=/api
VITE_REVERB_HOST=messenger-demo.fly.dev
VITE_REVERB_PORT=443
VITE_REVERB_SCHEME=https
```

Це значення "запікаються" в статичний JS-бандл під час `npm run build`, тому їх треба виставити **до** білду — або через `.env.production` у фронтенд-репо, або передати як build args у Dockerfile (стадія `frontend`), якщо хочете конфігурувати з deploy-репозиторію централізовано.

---

## 9. `fly.toml`

```toml
app = "messenger-demo"
primary_region = "waw"

[build]

[env]
  APP_ENV = "production"
  APP_DEBUG = "false"
  LOG_CHANNEL = "stderr"
  BROADCAST_CONNECTION = "reverb"
  REVERB_SERVER_HOST = "0.0.0.0"
  REVERB_SERVER_PORT = "8081"
  REVERB_SCHEME = "https"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    grace_period = "30s"
    interval = "15s"
    method = "GET"
    path = "/up"
    timeout = "5s"

[[vm]]
  memory = "512mb"
  cpu_kind = "shared"
  cpus = 1
```

---

## 10. Деплой

```bash
fly launch --no-deploy    # один раз, для генерації app + прив'язки до fly.toml вище

fly postgres create --name messenger-demo-db --region waw --vm-size shared-cpu-1x --volume-size 1
fly postgres attach messenger-demo-db --app messenger-demo

fly redis create   # Upstash free tier

fly secrets set \
  APP_KEY=$(php artisan key:generate --show) \
  REVERB_APP_ID=demo-app \
  REVERB_APP_KEY=$(openssl rand -hex 16) \
  REVERB_APP_SECRET=$(openssl rand -hex 32) \
  GIT_CLONE_TOKEN=glpat-xxxxxxxxxxxx

# деплой з передачею git-токена як build secret саме на цей запуск
fly deploy --build-secret git_token=$GIT_CLONE_TOKEN
```

**Зверніть увагу:** `--build-secret` треба вказувати щоразу при деплої (він не зберігається між викликами `fly deploy`, на відміну від `fly secrets`), або прописати у CI/CD пайплайн, якщо автоматизуєте.

---

## 11. Оновлення, коли backend/frontend-репо змінились

Оскільки код клонується під час білду, а не копіюється з диска, будь-який `fly deploy` тягне свіжий `HEAD` вказаної гілки (`BACKEND_REF`/`FRONTEND_REF`). Тобто для оновлення демо після нових комітів у будь-якому з двох репо:

```bash
fly deploy --build-secret git_token=$GIT_CLONE_TOKEN --no-cache
```

`--no-cache` тут важливий — інакше Docker може перевикористати закешований шар `git clone` і не підтягнути нові коміти (BuildKit кешує `RUN`-шар за вхідними параметрами, а не за вмістом віддаленого репо).

---

## Підсумок структури

```
messenger-backend/      ← ваш існуючий Laravel-репо, без змін
messenger-frontend/     ← ваш існуючий Vue-репо, без змін
messenger-deploy/        ← НОВИЙ репо, тільки Dockerfile + fly.toml + docker/*
```

Deploy-репо не містить бізнес-логіки — лише "рецепт" збірки, тому оновлювати його треба рідко (в основному коли міняється інфраструктура, а не коли пишете фічі).