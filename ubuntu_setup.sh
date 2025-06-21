#!/bin/bash

# Скрипт установки и настройки Seeker для Ubuntu 24.04
# Поддерживает Apache2 и Let's Encrypt

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Загрузка переменных из .env файла
if [ -f .env ]; then
    # Безопасная загрузка .env файла с поддержкой кавычек
    set -a  # автоматически экспортировать переменные
    source .env
    set +a  # отключить автоэкспорт
else
    print_error "Файл .env не найден! Скопируйте .env.example в .env и заполните нужные значения."
    exit 1
fi

# Установка значений по умолчанию если переменные не заданы
DOMAIN=${DOMAIN:-"your-domain.com"}
SEEKER_PATH=${SEEKER_PATH:-"/opt/seeker-yandex"}
SEEKER_PORT=${SEEKER_PORT:-"8080"}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-"admin@${DOMAIN}"}

APACHE_CONFIG="/etc/apache2/sites-available/${DOMAIN}.conf"
SEEKER_SERVICE="/etc/systemd/system/seeker.service"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен быть запущен от имени root (sudo)"
        exit 1
    fi
}

update_system() {
    print_status "Обновление системы..."
    apt update && apt upgrade -y
}

install_dependencies() {
    print_status "Установка зависимостей..."
    apt install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-requests \
        python3-packaging \
        python3-psutil \
        apache2 \
        php \
        php-cli \
        libapache2-mod-php \
        certbot \
        python3-certbot-apache \
        ufw \
        git \
        curl \
        wget
}

setup_seeker() {
    print_status "Настройка Seeker в ${SEEKER_PATH}..."

    # Создаем пользователя для seeker
    if ! id "seeker" &>/dev/null; then
        useradd -r -s /bin/false -d $SEEKER_PATH seeker
    fi

    # Проверяем что мы находимся в директории с исходниками или уже в целевой директории
    if [ ! -f "seeker.py" ]; then
        print_error "Файл seeker.py не найден в текущей директории. Убедитесь что вы запускаете скрипт из корня проекта."
        exit 1
    fi

    # Создаем директории если они не существуют
    mkdir -p $SEEKER_PATH
    mkdir -p $SEEKER_PATH/logs
    mkdir -p $SEEKER_PATH/db

    # Копируем файлы проекта только если запускаем не из целевой директории
    if [ "$(pwd)" != "$SEEKER_PATH" ]; then
        print_status "Копирование файлов проекта из $(pwd) в $SEEKER_PATH..."
        rsync -av --exclude='venv' --exclude='.git' --exclude='__pycache__' --exclude='logs' --exclude='db' . $SEEKER_PATH/
        
        # Копируем .env файл
        if [ -f .env ]; then
            print_status "Копирование .env файла..."
            cp .env $SEEKER_PATH/
        fi
    else
        print_status "Скрипт запущен из целевой директории $SEEKER_PATH - копирование файлов не требуется"
    fi

    # Создаем виртуальное окружение Python если оно не существует
    if [ ! -d "$SEEKER_PATH/venv" ]; then
        print_status "Создание виртуального окружения Python..."
        python3 -m venv $SEEKER_PATH/venv
    else
        print_status "Виртуальное окружение Python уже существует"
    fi

    # Активируем виртуальное окружение и устанавливаем зависимости
    print_status "Установка Python зависимостей в виртуальное окружение..."
    source $SEEKER_PATH/venv/bin/activate
    pip install --upgrade pip

    # Устанавливаем зависимости из requirements.txt если он существует
    if [ -f $SEEKER_PATH/requirements.txt ]; then
        pip install -r $SEEKER_PATH/requirements.txt
    else
        # Устанавливаем базовые зависимости
        pip install requests packaging psutil
    fi

    deactivate

    # Устанавливаем права доступа
    print_status "Настройка прав доступа..."
    chown -R seeker:www-data $SEEKER_PATH
    chmod -R 755 $SEEKER_PATH
    chmod -R 775 $SEEKER_PATH/logs
    chmod -R 775 $SEEKER_PATH/db
    chmod -R 755 $SEEKER_PATH/venv

    # Устанавливаем права на виртуальное окружение
    chown -R seeker:seeker $SEEKER_PATH/venv

    print_status "Seeker установлен в ${SEEKER_PATH}"
}

configure_apache() {
    print_status "Настройка Apache2..."

    # Включаем необходимые модули
    a2enmod rewrite
    a2enmod ssl
    a2enmod headers
    a2enmod proxy
    a2enmod proxy_http

    # Создаем конфигурацию Apache из шаблона
    print_status "Создание конфигурации Apache для домена ${DOMAIN}..."

    # Копируем шаблон конфигурации и заменяем плейсхолдеры
    if [ -f "$APACHE_CONFIG" ]; then
        print_warning "Конфигурация Apache уже существует, создаем резервную копию..."
        cp $APACHE_CONFIG ${APACHE_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)
    fi
    cp apache2_config.conf $APACHE_CONFIG

    # Заменяем плейсхолдеры на реальные значения
    sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" $APACHE_CONFIG
    sed -i "s|SEEKER_PATH_PLACEHOLDER|${SEEKER_PATH}|g" $APACHE_CONFIG
    sed -i "s|SEEKER_PORT_PLACEHOLDER|${SEEKER_PORT}|g" $APACHE_CONFIG

        # Проверяем что конфигурация создана
    if [ ! -f "$APACHE_CONFIG" ]; then
        print_error "Не удалось создать конфигурацию Apache: $APACHE_CONFIG"
        exit 1
    fi

    # Включаем сайт
    a2ensite ${DOMAIN}
    a2dissite 000-default

    # Тестируем конфигурацию
    apache2ctl configtest
}

setup_ssl() {
    print_status "Настройка SSL сертификата..."

    # Перезапускаем Apache
    systemctl restart apache2

    # Получаем SSL сертификат
    print_warning "Получение SSL сертификата для домена ${DOMAIN}"
    print_warning "Убедитесь, что домен ${DOMAIN} указывает на этот сервер!"

    # Используем email из .env или запрашиваем у пользователя
    if [ "$LETSENCRYPT_EMAIL" = "admin@your-domain.com" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
        read -p "Введите ваш email для Let's Encrypt: " LETSENCRYPT_EMAIL
    fi

    print_status "Получение SSL сертификата с email: ${LETSENCRYPT_EMAIL}"
    certbot --apache -d ${DOMAIN} --email ${LETSENCRYPT_EMAIL} --agree-tos --non-interactive --redirect
}

create_systemd_service() {
    print_status "Создание systemd сервиса..."

    cat > $SEEKER_SERVICE << EOF
[Unit]
Description=Seeker Location Tracker
After=network.target

[Service]
Type=simple
User=seeker
Group=seeker
WorkingDirectory=${SEEKER_PATH}
Environment=PATH=${SEEKER_PATH}/venv/bin
EnvironmentFile=${SEEKER_PATH}/.env
ExecStart=${SEEKER_PATH}/venv/bin/python3 ${SEEKER_PATH}/seeker.py -p ${SEEKER_PORT} --template 4
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Перезагружаем systemd и включаем сервис
    systemctl daemon-reload
    systemctl enable seeker
}

configure_firewall() {
    print_status "Настройка файрвола..."

    # Включаем UFW
    ufw --force enable

    # Разрешаем SSH
    ufw allow ssh

    # Разрешаем HTTP и HTTPS
    ufw allow 'Apache Full'

    # Показываем статус
    ufw status
}

start_services() {
    print_status "Запуск сервисов..."

    # Запускаем Apache
    systemctl restart apache2
    systemctl enable apache2

    # Запускаем Seeker
    if systemctl is-active --quiet seeker; then
        print_status "Перезапуск сервиса Seeker..."
        systemctl restart seeker
    else
        print_status "Запуск сервиса Seeker..."
        systemctl start seeker
    fi
    systemctl status seeker --no-pager
}

main() {
    print_status "Начало установки Seeker для Ubuntu 24.04"

    check_root
    update_system
    install_dependencies
    setup_seeker
    configure_apache
    setup_ssl
    create_systemd_service
    configure_firewall
    start_services

    print_status "Установка завершена!"
    print_status "Seeker доступен по адресу: https://${DOMAIN}"
    print_status "Логи Seeker: journalctl -u seeker -f"
    print_status "Логи Apache: tail -f /var/log/apache2/${DOMAIN}_ssl_error.log"
    print_status "Управление сервисом: systemctl {start|stop|restart|status} seeker"
}

# Проверяем аргументы командной строки
case "$1" in
    start)
        systemctl start seeker
        ;;
    stop)
        systemctl stop seeker
        ;;
    restart)
        systemctl restart seeker
        systemctl restart apache2
        ;;
    status)
        systemctl status seeker
        systemctl status apache2
        ;;
    logs)
        journalctl -u seeker -f
        ;;
    install)
        main
        ;;
    *)
        echo "Использование: $0 {install|start|stop|restart|status|logs}"
        echo ""
        echo "  install  - Полная установка и настройка"
        echo "  start    - Запуск сервиса"
        echo "  stop     - Остановка сервиса"
        echo "  restart  - Перезапуск сервисов"
        echo "  status   - Статус сервисов"
        echo "  logs     - Просмотр логов"
        exit 1
        ;;
esac
