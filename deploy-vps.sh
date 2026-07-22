#!/bin/bash
# Скрипт для розгортання проєкту на VPS через Docker Compose
# Цей скрипт призначений для виконання БЕЗПОСЕРЕДНЬО на вашій VPS.

set -e

echo "=== Розгортання Expedition на VPS ==="

# 1. Перевірка наявності Docker та Docker Compose
if ! command -v docker &> /dev/null; then
    echo "Docker не встановлено. Будь ласка, встановіть Docker та Docker Compose (https://docs.docker.com/engine/install/)."
    exit 1
fi

# 2. Створення .env файлу, якщо він не існує
if [ ! -f .env ]; then
    echo "Файл .env не знайдено. Створюємо шаблон..."
    cat <<EOF > .env
# Токен для доступу до приватних репозиторіїв (необхідний для збірки Docker)
# Його треба буде передати як секрет під час збірки, в Dockerfile варто використати buildkit secrets.
GIT_TOKEN=your_git_token_here

# Налаштування бази даних
DB_DATABASE=expedition
DB_USERNAME=expedition
DB_PASSWORD=$(openssl rand -hex 16)

# Налаштування Laravel
APP_KEY=base64:$(openssl rand -base64 32)
REVERB_APP_KEY=$(openssl rand -hex 16)
REVERB_APP_SECRET=$(openssl rand -base64 32)

# Домени / IP адреси для Sanctum автентифікації та CORS
# Замініть на вашу IP-адресу або домен: наприклад, http://35.207.37.166
APP_URL=http://localhost
SANCTUM_STATEFUL_DOMAINS=localhost
FRONTEND_URL=http://localhost

# Налаштування WebSocket (Reverb) для фронтенду
# Замініть на IP вашої VPS або домен (наприклад, 35.207.37.166 або expedition.com)
VITE_REVERB_HOST=35.207.37.166
# Порт для підключення клієнта (80 для HTTP, 443 для HTTPS)
VITE_REVERB_PORT=80
# Схема підключення клієнта (http для ws://, https для wss://)
VITE_REVERB_SCHEME=http
EOF
    echo "Файл .env створено. БУДЬ ЛАСКА, ВІДРЕДАГУЙТЕ .env (встановіть токен, IP/домен) І ЗАПУСТІТЬ СКРИПТ ЗНОВУ."
    exit 0
fi

# 3. Перевірка наявності DOCKER_BUILDKIT (для збірки з секретами)
export DOCKER_BUILDKIT=1

# 4. Запуск збірки та деплою
echo "Збираємо та запускаємо контейнери..."
# Якщо ви використовуєте BuildKit secrets, розкоментуйте рядок з секретами в Dockerfile
# і додайте сюди --secret id=git_token,src=.env

docker compose up -d --build

echo "=== Розгортання завершено! ==="
echo "Перевірте статуси контейнерів за допомогою 'docker compose ps'"
echo "Логи: 'docker compose logs -f'"
