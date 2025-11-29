#!/bin/bash

# Скрипт для установки WireGuard через Docker
# Использование: 
#   WG_HOST=your_ip AUTH_TOKEN=your_token ./setup-wireguard.sh
#   или с автоматическим созданием первого клиента:
#   WG_HOST=your_ip AUTH_TOKEN=your_token CREATE_FIRST_CLIENT=true ./setup-wireguard.sh
#   или с использованием GitHub Container Registry (для обхода лимитов Docker Hub):
#   WG_HOST=your_ip AUTH_TOKEN=your_token DOCKER_IMAGE=ghcr.io/username/wg-rest-api ./setup-wireguard.sh

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для логирования
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка переменных окружения
if [ -z "$WG_HOST" ] || [ -z "$AUTH_TOKEN" ]; then
    log_error "Необходимо установить переменные окружения:"
    log_error "  export WG_HOST=your_server_ip"
    log_error "  export AUTH_TOKEN=your_auth_token"
    exit 1
fi

log_info "Начинаем установку WireGuard..."
log_info "WG_HOST: $WG_HOST"
log_info "AUTH_TOKEN: ${AUTH_TOKEN:0:3}***"

# Определение Docker образа (по умолчанию Docker Hub, можно переключить на ghcr.io)
DOCKER_IMAGE=${DOCKER_IMAGE:-"leonovk/wg-rest-api"}
log_info "Docker образ: $DOCKER_IMAGE"

# Функция для ожидания готовности сервиса
wait_for_service() {
    local service=$1
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if systemctl is-active --quiet $service 2>/dev/null || pgrep -f $service > /dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

# Шаг 1: Обновление пакетов
log_info "Шаг 1: Обновление списка пакетов..."
apt update

# Шаг 2: Установка необходимых пакетов
log_info "Шаг 2: Установка необходимых пакетов..."
apt install -y ca-certificates curl gnupg

# Шаг 3: Настройка репозитория Docker
log_info "Шаг 3: Настройка репозитория Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Шаг 4: Добавление репозитория Docker
log_info "Шаг 4: Добавление репозитория Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

# Шаг 5: Установка Docker
log_info "Шаг 5: Установка Docker..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Шаг 6: Ожидание запуска Docker daemon
log_info "Шаг 6: Ожидание запуска Docker daemon..."
if ! wait_for_service docker; then
    log_warn "Docker daemon не запустился автоматически, запускаем вручную..."
    systemctl start docker
    systemctl enable docker
    sleep 3
fi

# Проверка, что Docker работает
if ! docker ps > /dev/null 2>&1; then
    log_error "Docker не отвечает. Проверьте статус: systemctl status docker"
    exit 1
fi

log_info "Docker daemon готов"

# Шаг 7: Проверка и загрузка модуля WireGuard (если нужно)
log_info "Шаг 7: Проверка модуля WireGuard..."
if ! lsmod | grep -q wireguard; then
    log_warn "Модуль WireGuard не загружен, пытаемся загрузить..."
    modprobe wireguard 2>/dev/null || log_warn "Не удалось загрузить модуль (может быть уже встроен в ядро)"
    sleep 2
fi

# Шаг 8: Остановка существующих контейнеров (если есть)
log_info "Шаг 8: Остановка существующих контейнеров..."
docker stop $(docker ps -q --filter ancestor=$DOCKER_IMAGE) 2>/dev/null || true
docker rm $(docker ps -aq --filter ancestor=$DOCKER_IMAGE) 2>/dev/null || true
# Также останавливаем по имени контейнера (на случай если образ изменился)
docker stop wg-rest-api 2>/dev/null || true
docker rm wg-rest-api 2>/dev/null || true

# Небольшая задержка для очистки
sleep 2

# Шаг 9: Создание директории для конфигурации
log_info "Шаг 9: Создание директории для конфигурации..."
mkdir -p ~/.wg-rest

# Шаг 10: Загрузка Docker образа (если нужно)
log_info "Шаг 10: Загрузка Docker образа..."
if ! docker image inspect "$DOCKER_IMAGE" > /dev/null 2>&1; then
    log_info "Образ не найден локально, загружаем..."
    docker pull "$DOCKER_IMAGE"
else
    log_info "Образ уже загружен"
fi

# Шаг 11: Запуск контейнера WireGuard
log_info "Шаг 11: Запуск контейнера WireGuard..."
docker run -d \
  -e WG_HOST="$WG_HOST" \
  -e AUTH_TOKEN="$AUTH_TOKEN" \
  -e ENVIRONMENT=production \
  -e WG_DEFAULT_DNS=1.1.1.1 \
  -v ~/.wg-rest:/etc/wireguard \
  -p 51820:51820/udp \
  -p 3000:3000 \
  --cap-add=NET_ADMIN \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --restart unless-stopped \
  --name wg-rest-api \
  "$DOCKER_IMAGE"

# Шаг 12: Ожидание запуска контейнера
log_info "Шаг 12: Ожидание запуска контейнера..."
sleep 5

# Проверка статуса контейнера
if ! docker ps | grep -q wg-rest-api; then
    log_error "Контейнер не запустился. Проверьте логи:"
    docker logs wg-rest-api
    exit 1
fi

log_info "Контейнер запущен успешно"

# Шаг 13: Проверка сетевых интерфейсов
log_info "Шаг 13: Проверка сетевых интерфейсов..."
sleep 3

# Проверка, что интерфейс WireGuard создан
if docker exec wg-rest-api ip link show wg0 > /dev/null 2>&1; then
    log_info "Интерфейс wg0 найден в контейнере"
else
    log_warn "Интерфейс wg0 не найден (может появиться после создания первого клиента)"
fi

# Шаг 14: Ожидание готовности API
log_info "Шаг 14: Ожидание готовности API..."
max_api_attempts=30
api_attempt=0
api_ready=false

while [ $api_attempt -lt $max_api_attempts ]; do
    if curl -s -f -H "Authorization: Bearer $AUTH_TOKEN" "http://localhost:3000/api/clients" > /dev/null 2>&1; then
        api_ready=true
        break
    fi
    api_attempt=$((api_attempt + 1))
    sleep 2
done

if [ "$api_ready" = true ]; then
    log_info "API доступен и работает"
else
    log_warn "API не отвечает после ожидания (может потребоваться больше времени)"
fi

# Шаг 15: Опциональное создание первого клиента
if [ "$CREATE_FIRST_CLIENT" = "true" ] || [ "$CREATE_FIRST_CLIENT" = "1" ]; then
    log_info "Шаг 15: Создание первого клиента..."
    
    if [ "$api_ready" = true ]; then
        # Создание клиента
        CLIENT_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer $AUTH_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"data": {"user_id": 1, "comment": "first client"}}' \
            "http://localhost:3000/api/clients")
        
        # Извлечение ID клиента из ответа
        CLIENT_ID=$(echo "$CLIENT_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
        
        if [ -n "$CLIENT_ID" ]; then
            log_info "Клиент создан с ID: $CLIENT_ID"
            
            # Получение конфига
            CONFIG_FILE="client${CLIENT_ID}.conf"
            curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
                "http://localhost:3000/api/clients/$CLIENT_ID" \
                --output "$CONFIG_FILE"
            
            if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ]; then
                log_info "Конфиг сохранен в: $CONFIG_FILE"
            fi
            
            # Получение QR кода (опционально)
            QR_FILE="client${CLIENT_ID}.png"
            curl -s -H "Authorization: Bearer $AUTH_TOKEN" \
                "http://localhost:3000/api/clients/$CLIENT_ID?format=qr" \
                --output "$QR_FILE"
            
            if [ -f "$QR_FILE" ] && [ -s "$QR_FILE" ]; then
                log_info "QR код сохранен в: $QR_FILE"
            fi
        else
            log_warn "Не удалось создать клиента. Ответ API: $CLIENT_RESPONSE"
        fi
    else
        log_warn "API не готов, пропускаем создание клиента"
    fi
else
    log_info "Шаг 15: Пропущен (для создания клиента установите CREATE_FIRST_CLIENT=true)"
fi

# Финальная информация
log_info "=========================================="
log_info "Установка завершена!"
log_info "=========================================="
log_info "IP сервера: $WG_HOST"
log_info "Порт API: 3000"
log_info "Порт WireGuard: 51820/udp"
log_info ""
log_info "Проверка статуса контейнера:"
log_info "  docker ps | grep wg-rest-api"
log_info ""
log_info "Просмотр логов:"
log_info "  docker logs wg-rest-api"
log_info ""
log_info "Создание клиента:"
log_info "  curl -X POST \\"
log_info "    -H \"Authorization: Bearer $AUTH_TOKEN\" \\"
log_info "    -H \"Content-Type: application/json\" \\"
log_info "    -d '{\"data\": {\"user_id\": 123, \"comment\": \"client\"}}' \\"
log_info "    http://$WG_HOST:3000/api/clients"
log_info ""
log_info "Для автоматического создания первого клиента при следующем запуске:"
log_info "  CREATE_FIRST_CLIENT=true ./setup-wireguard.sh"
log_info ""
log_info "Для использования GitHub Container Registry (обход лимитов Docker Hub):"
log_info "  DOCKER_IMAGE=ghcr.io/username/wg-rest-api ./setup-wireguard.sh"
log_info ""

