#!/bin/bash

# Скрипт управления сервисом Seeker
# Использование: ./seeker_service.sh {start|stop|restart|status|logs|install}

# Загрузка переменных из .env файла
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Установка значений по умолчанию
DOMAIN=${DOMAIN:-"your-domain.com"}
SEEKER_PATH=${SEEKER_PATH:-"/opt/seeker-yandex"}
SERVICE_NAME="seeker"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

case "$1" in
    start)
        print_status "Запуск сервиса Seeker..."
        sudo systemctl start $SERVICE_NAME
        sudo systemctl status $SERVICE_NAME --no-pager
        ;;
    stop)
        print_status "Остановка сервиса Seeker..."
        sudo systemctl stop $SERVICE_NAME
        sudo systemctl status $SERVICE_NAME --no-pager
        ;;
    restart)
        print_status "Перезапуск сервисов..."
        sudo systemctl restart $SERVICE_NAME
        sudo systemctl restart apache2
        print_status "Статус сервисов:"
        sudo systemctl status $SERVICE_NAME --no-pager
        sudo systemctl status apache2 --no-pager
        ;;
    status)
        print_status "Статус сервисов:"
        echo "=== Seeker Service ==="
        sudo systemctl status $SERVICE_NAME --no-pager
        echo ""
        echo "=== Apache2 Service ==="
        sudo systemctl status apache2 --no-pager
        echo ""
        echo "=== Listening Ports ==="
        sudo netstat -tlnp | grep -E ':80|:443|:8080'
        ;;
    logs)
        print_status "Логи Seeker (нажмите Ctrl+C для выхода):"
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    apache-logs)
        print_status "Логи Apache для домена $DOMAIN:"
        sudo tail -f /var/log/apache2/${DOMAIN}_ssl_error.log
        ;;
    test)
        print_status "Тестирование конфигурации..."
        echo "=== Проверка конфигурации Apache ==="
        sudo apache2ctl configtest
        echo ""
        echo "=== Проверка SSL сертификата ==="
        sudo certbot certificates | grep $DOMAIN
        echo ""
        echo "=== Проверка портов ==="
        sudo netstat -tlnp | grep -E ':80|:443|:8080'
        ;;
    install)
        print_status "Запуск полной установки..."
        sudo ./ubuntu_setup.sh install
        ;;
    ssl-renew)
        print_status "Обновление SSL сертификата..."
        sudo certbot renew --dry-run
        ;;
    backup)
        print_status "Создание резервной копии..."
        BACKUP_DIR="/var/backups/seeker_$(date +%Y%m%d_%H%M%S)"
        sudo mkdir -p $BACKUP_DIR
        sudo cp -r $SEEKER_PATH $BACKUP_DIR/
        sudo cp /etc/apache2/sites-available/${DOMAIN}.conf $BACKUP_DIR/
        sudo cp /etc/systemd/system/seeker.service $BACKUP_DIR/
        print_status "Резервная копия создана: $BACKUP_DIR"
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|apache-logs|test|install|ssl-renew|backup}"
        echo ""
        echo "Команды управления:"
        echo "  start        - Запуск сервиса Seeker"
        echo "  stop         - Остановка сервиса Seeker"
        echo "  restart      - Перезапуск всех сервисов"
        echo "  status       - Показать статус всех сервисов"
        echo "  logs         - Показать логи Seeker в реальном времени"
        echo "  apache-logs  - Показать логи Apache для домена"
        echo "  test         - Тестирование конфигурации и SSL"
        echo "  install      - Полная установка системы"
        echo "  ssl-renew    - Тест обновления SSL сертификата"
        echo "  backup       - Создание резервной копии"
        echo ""
        echo "Примеры:"
        echo "  $0 start     # Запустить Seeker"
        echo "  $0 logs      # Посмотреть логи"
        echo "  $0 test      # Проверить конфигурацию"
        exit 1
        ;;
esac
