#!/bin/bash

# Простой скрипт для быстрой установки WireGuard
# Использование: curl -sSL https://raw.githubusercontent.com/EasyVanilla2023/WG-API/main/install.sh | bash

set -e

REPO_URL="https://raw.githubusercontent.com/EasyVanilla2023/WG-API/main"

echo "📥 Загрузка скрипта установки WireGuard..."
curl -fsSL "${REPO_URL}/setup-wireguard.sh" -o setup-wireguard.sh
curl -fsSL "${REPO_URL}/env.example" -o env.example

chmod +x setup-wireguard.sh

echo "✅ Файлы загружены!"
echo ""
echo "📝 Следующие шаги:"
echo "1. Настройте переменные окружения:"
echo "   export WG_HOST=your_server_ip"
echo "   export AUTH_TOKEN=your_secure_token"
echo ""
echo "2. Запустите установку:"
echo "   ./setup-wireguard.sh"
echo ""
echo "Или запустите одной командой:"
echo "   WG_HOST=your_ip AUTH_TOKEN=your_token ./setup-wireguard.sh"

