#!/bin/bash

# Variables
DOMAIN="billing.arialnodes.in"
DB_NAME="paymenter"
DB_USER="paymenter"
DB_PASSWORD="rishabh"
INSTALL_DIR="/var/www/paymenter"
PHP_VERSION="8.2"
MARIADB_VERSION="mariadb-10.11"

# Update and install dependencies
apt update -y
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

# Add PHP repository
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

# Add MariaDB repository
curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="$MARIADB_VERSION"

# Install PHP, MariaDB, Nginx, and other necessary packages
apt update
apt -y install php$PHP_VERSION php$PHP_VERSION-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Install Composer
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Set up Paymenter directory
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR
curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
tar -xzvf paymenter.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Set up MariaDB database and user
mysql -u root -p <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Configure environment
cp .env.example .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env

# Install PHP dependencies and set application key
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan storage:link

# Run database migrations and seeders
php artisan migrate --force --seed

# Create admin user
php artisan p:user:create

# Configure Nginx
cat <<NGINX_CONF >/etc/nginx/sites-available/paymenter.conf
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $INSTALL_DIR/public;

    index index.php;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
    }
}
NGINX_CONF

# Enable Nginx site and restart service
ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
systemctl restart nginx

# Set correct permissions
chown -R www-data:www-data $INSTALL_DIR/*

# Set up cron job for Paymenter
(crontab -l ; echo "* * * * * php $INSTALL_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -

# Create systemd service for Paymenter queue worker
cat <<SYSTEMD_CONF >/etc/systemd/system/paymenter.service
[Unit]
Description=Paymenter Queue Worker

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $INSTALL_DIR/artisan queue:work
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SYSTEMD_CONF

# Enable and start the Paymenter queue worker service
systemctl enable --now paymenter.service

echo "Paymenter installation is complete. Please visit http://$DOMAIN to access your Paymenter instance."
