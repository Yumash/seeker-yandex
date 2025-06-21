# Установка Seeker на Ubuntu 24.04

Это руководство поможет вам установить и настроить Seeker на Ubuntu 24.04 с Apache2 и Let's Encrypt. Все настройки выполняются через переменные окружения в файле `.env`.

## 📋 Выбор шаблона

Seeker поддерживает несколько шаблонов для привлечения пользователей:

### 🎯 **Рекомендуемый для России: Telegram (шаблон #4)**
- Имитирует страницу группы Telegram
- Высокое доверие пользователей
- Популярность Telegram в России
- Настраиваемые параметры: название группы, описание, количество участников

### 📱 **Другие доступные шаблоны:**
- **[0] NearYou** - "Найди людей рядом" (платформа знакомств)
- **[1] Google Drive** - имитация документа Google Drive  
- **[2] WhatsApp** - страница WhatsApp чата
- **[3] WhatsApp Redirect** - WhatsApp с редиректом
- **[4] Telegram** - страница группы Telegram ⭐ **РЕКОМЕНДУЕТСЯ**
- **[5] Zoom** - приглашение на видеоконференцию
- **[6] Google ReCaptcha** - имитация Google капчи
- **[7] Custom Link Preview** - кастомный предпросмотр ссылки

**По умолчанию:** Установочный скрипт использует шаблон Telegram (#4).

## Предварительные требования

1. **Ubuntu 24.04 LTS** с правами root/sudo
2. **Домен** который указывает на ваш сервер
3. **Открытые порты**: 80 (HTTP), 443 (HTTPS), 22 (SSH)
4. **Минимум 1GB RAM** и 10GB свободного места на диске

## Быстрая установка

### 1. Клонирование репозитория

```bash
git clone <repository_url>
cd seeker-yandex
```

### 2. Настройка конфигурации

```bash
# Создайте файл .env из примера
cp .env.example .env

# Отредактируйте .env файл, указав ваш домен и email
nano .env
```

Пример содержимого `.env`:
```bash
# Основные настройки
DOMAIN=your-domain.com
LETSENCRYPT_EMAIL=admin@your-domain.com
SEEKER_PATH=/opt/seeker-yandex
SEEKER_PORT=8080
DEBUG_HTTP=false

# Настройки Telegram шаблона (опционально)
TITLE=Интересная группа
DESC=Присоединяйтесь к обсуждению интересных тем
MEM_NUM=1250
ONLINE_NUM=89
IMAGE=https://example.com/group-avatar.jpg
```

### 🔧 **Настройка Telegram шаблона**

Если используете Telegram шаблон, можете настроить его через переменные окружения в `.env`:

- **TITLE** - название группы (по умолчанию: запросит интерактивно)
- **DESC** - описание группы  
- **MEM_NUM** - количество участников (например: 1250)
- **ONLINE_NUM** - количество онлайн (например: 89)
- **IMAGE** - ссылка на аватар группы или путь к файлу

### 3. Предоставление прав на выполнение

```bash
chmod +x ubuntu_setup.sh seeker_service.sh
```

### 4. Полная установка

```bash
sudo ./ubuntu_setup.sh install
```

Этот скрипт выполнит:
- Обновление системы
- Установку всех зависимостей (Python, Apache2, PHP, Certbot)
- Создание пользователя `seeker`
- Копирование файлов в `/opt/seeker-yandex`
- Создание виртуального окружения Python
- Установку Python зависимостей в venv
- Настройку Apache2 с конфигурацией из `.env`
- Получение SSL сертификата от Let's Encrypt
- Создание systemd сервиса
- Настройку файрвола UFW
- Запуск всех сервисов

## Пошаговая установка

### 1. Обновление системы

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Установка зависимостей

```bash
sudo apt install -y \
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
```

### 3. Настройка Apache2

```bash
# Включение модулей
sudo a2enmod rewrite ssl headers proxy proxy_http

# Копирование конфигурации
sudo cp apache2_config.conf /etc/apache2/sites-available/domain.com

# Включение сайта
sudo a2ensite domain.com
sudo a2dissite 000-default

# Проверка конфигурации
sudo apache2ctl configtest
```

### 4. Настройка Seeker

```bash
# Создание пользователя
sudo useradd -r -s /bin/false -d /opt/seeker-yandex seeker

# Создание директорий
sudo mkdir -p /opt/seeker-yandex

# Копирование файлов (исключая ненужные)
sudo rsync -av --exclude='venv' --exclude='.git' --exclude='__pycache__' --exclude='logs' --exclude='db' --exclude='.env' . /opt/seeker-yandex/

# Копирование .env файла
sudo cp .env /opt/seeker-yandex/

# Создание виртуального окружения Python
sudo python3 -m venv /opt/seeker-yandex/venv
sudo /opt/seeker-yandex/venv/bin/pip install --upgrade pip
sudo /opt/seeker-yandex/venv/bin/pip install -r /opt/seeker-yandex/requirements.txt

# Установка прав
sudo chown -R seeker:www-data /opt/seeker-yandex
sudo chmod -R 755 /opt/seeker-yandex
sudo chmod -R 775 /opt/seeker-yandex/logs
sudo chmod -R 775 /opt/seeker-yandex/db
sudo chown -R seeker:seeker /opt/seeker-yandex/venv
```

### 5. Получение SSL сертификата

```bash
sudo systemctl restart apache2

# Замените your-domain.com и admin@your-domain.com на ваши данные
sudo certbot --apache -d your-domain.com --email admin@your-domain.com --agree-tos --non-interactive --redirect
```

### 6. Создание systemd сервиса

```bash
sudo tee /etc/systemd/system/seeker.service > /dev/null <<EOF
[Unit]
Description=Seeker Location Tracker
After=network.target

[Service]
Type=simple
User=seeker
Group=seeker
WorkingDirectory=/opt/seeker-yandex
Environment=PATH=/opt/seeker-yandex/venv/bin
EnvironmentFile=/opt/seeker-yandex/.env
ExecStart=/opt/seeker-yandex/venv/bin/python3 /opt/seeker-yandex/seeker.py -p 8080 --template 4
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable seeker
sudo systemctl start seeker
```

### 7. Настройка файрвола

```bash
sudo ufw --force enable
sudo ufw allow ssh
sudo ufw allow 'Apache Full'
sudo ufw status
```

## Управление сервисом

### Использование скрипта управления

```bash
# Запуск сервисов
./seeker_service.sh start

# Остановка сервисов
./seeker_service.sh stop

# Перезапуск сервисов
./seeker_service.sh restart

# Проверка статуса
./seeker_service.sh status

# Просмотр логов
./seeker_service.sh logs

# Тестирование конфигурации
./seeker_service.sh test

# Создание резервной копии
./seeker_service.sh backup
```

### Прямое управление через systemctl

```bash
# Управление Seeker
sudo systemctl start seeker
sudo systemctl stop seeker
sudo systemctl restart seeker
sudo systemctl status seeker

# Управление Apache2
sudo systemctl start apache2
sudo systemctl stop apache2
sudo systemctl restart apache2
sudo systemctl status apache2
```

## Мониторинг и логи

### Логи Seeker

```bash
# Реальное время
sudo journalctl -u seeker -f

# Последние записи
sudo journalctl -u seeker -n 100

# Логи за определенный период
sudo journalctl -u seeker --since "1 hour ago"
```

### Логи Apache

```bash
# Ошибки SSL (замените your-domain.com на ваш домен)
sudo tail -f /var/log/apache2/your-domain.com_ssl_error.log

# Доступ SSL
sudo tail -f /var/log/apache2/your-domain.com_ssl_access.log

# Общие ошибки
sudo tail -f /var/log/apache2/error.log
```

### Проверка портов

```bash
sudo netstat -tlnp | grep -E ':80|:443|:8080'
```

## Обслуживание

### Обновление SSL сертификата

```bash
# Тест обновления
sudo certbot renew --dry-run

# Автоматическое обновление уже настроено через cron
sudo crontab -l | grep certbot
```

### Резервное копирование

```bash
# Создание резервной копии
./seeker_service.sh backup

# Ручное создание
sudo mkdir -p /var/backups/seeker_$(date +%Y%m%d)
sudo cp -r /opt/seeker-yandex /var/backups/seeker_$(date +%Y%m%d)/
sudo cp /etc/apache2/sites-available/your-domain.com.conf /var/backups/seeker_$(date +%Y%m%d)/
sudo cp /etc/systemd/system/seeker.service /var/backups/seeker_$(date +%Y%m%d)/
```

### Обновление приложения

```bash
# Остановка сервиса
sudo systemctl stop seeker

# Обновление кода
cd /opt/seeker-yandex
sudo git pull origin master

# Обновление зависимостей в виртуальном окружении
sudo /opt/seeker-yandex/venv/bin/pip install -r requirements.txt

# Перезапуск сервиса
sudo systemctl start seeker
```

## Устранение неполадок

### Проверка статуса сервисов

```bash
./seeker_service.sh status
```

### Проверка конфигурации Apache

```bash
sudo apache2ctl configtest
```

### Проверка SSL сертификата

```bash
sudo certbot certificates
```

### Проверка доступности портов

```bash
sudo ss -tlnp | grep -E ':80|:443|:8080'
```

### Тестирование HTTPS

```bash
# Замените your-domain.com на ваш домен
curl -I https://your-domain.com
```

## Безопасность

1. **Регулярно обновляйте систему**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Мониторьте логи**:
   ```bash
   sudo tail -f /var/log/apache2/your-domain.com_ssl_error.log
   ```

3. **Настройте автоматические обновления безопасности**:
   ```bash
   sudo apt install unattended-upgrades
   sudo dpkg-reconfigure unattended-upgrades
   ```

4. **Регулярно создавайте резервные копии**:
   ```bash
   ./seeker_service.sh backup
   ```

## Контакты и поддержка

- **Логи**: `/var/log/apache2/` и `journalctl -u seeker`
- **Конфигурация**: `/etc/apache2/sites-available/your-domain.com.conf`
- **Сервис**: `/etc/systemd/system/seeker.service`
- **Приложение**: `/opt/seeker-yandex/`
- **Виртуальное окружение**: `/opt/seeker-yandex/venv/`
- **Конфигурация**: `/opt/seeker-yandex/.env`

В случае проблем проверьте логи и статус сервисов через `./seeker_service.sh status` и `./seeker_service.sh test`.

## 🔄 Смена шаблона

Чтобы изменить используемый шаблон после установки:

### Способ 1: Через systemd сервис

```bash
# Отредактируйте сервис
sudo systemctl edit --full seeker

# Измените строку ExecStart, заменив --template 4 на нужный номер
# ExecStart=/opt/seeker-yandex/venv/bin/python3 /opt/seeker-yandex/seeker.py -p 8080 --template 0

# Перезагрузите конфигурацию и перезапустите
sudo systemctl daemon-reload
sudo systemctl restart seeker
```

### Способ 2: Через переменные окружения

```bash
# Добавьте в /opt/seeker-yandex/.env
echo "TEMPLATE=0" | sudo tee -a /opt/seeker-yandex/.env

# Перезапустите сервис
sudo systemctl restart seeker
```

### Доступные номера шаблонов:
- **0** - NearYou
- **1** - Google Drive  
- **2** - WhatsApp
- **3** - WhatsApp Redirect
- **4** - Telegram (по умолчанию)
- **5** - Zoom
- **6** - Google ReCaptcha
- **7** - Custom Link Preview

## Важные замечания по безопасности

- Файл `.env` содержит конфиденциальную информацию и не должен попадать в публичный репозиторий
- Убедитесь что `.env` добавлен в `.gitignore`
- Регулярно обновляйте систему и SSL сертификаты
- Мониторьте логи на предмет подозрительной активности
