#!/bin/bash

echo "=========================================="
echo "     MikRadius Auto Installer (Nginx)"
echo "=========================================="

# Input manual domain
read -p "Masukkan domain untuk DaloRADIUS (contoh: radius.domain.com): " DOMAIN
read -p "Masukkan email untuk SSL Certbot: " EMAIL
read -p "Masukkan password DB Radius (Enter untuk default: radius123): " DBPASS

DBPASS=${DBPASS:-radius123}

echo "Domain      : $DOMAIN"
echo "Email SSL   : $EMAIL"
echo "DB Password : $DBPASS"
echo "------------------------------------------"
sleep 2

# Update & dependencies
apt update -y
apt install -y nginx mariadb-server php php-fpm php-mysql php-xml php-gd php-curl php-mbstring php-pear php-db git unzip freeradius freeradius-mysql freeradius-utils certbot python3-certbot-nginx ufw

# Firewall (hindari duplikasi)
ufw allow OpenSSH >/dev/null 2>&1
ufw allow http >/dev/null 2>&1
ufw allow https >/dev/null 2>&1
echo "y" | ufw enable

# Database
mysql -u root <<EOF
DROP DATABASE IF EXISTS radius;
CREATE DATABASE radius;
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost' IDENTIFIED BY '$DBPASS';
FLUSH PRIVILEGES;
EOF

# Lokasi schema FreeRADIUS benar (Ubuntu 22.04/24.04)
mysql -u root radius < /usr/share/freeradius/sql/mysql/schema.sql

# Enable SQL module dengan cara baru
cp /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

# Edit config SQL
sed -i "s|driver = \"rlm_sql_null\"|driver = \"rlm_sql_mysql\"|g" /etc/freeradius/3.0/mods-enabled/sql
sed -i "s|dialect = \"sqlite\"|dialect = \"mysql\"|g" /etc/freeradius/3.0/mods-enabled/sql

sed -i "s|login = \"radius\"|login = \"radius\"|g" /etc/freeradius/3.0/mods-enabled/sql
sed -i "s|password = \"radpass\"|password = \"$DBPASS\"|g" /etc/freeradius/3.0/mods-enabled/sql

# Restart Radius
systemctl restart freeradius

# Install DaloRADIUS
cd /var/www/
if [ -d "daloradius" ]; then
    rm -rf daloradius
fi

git clone https://github.com/lirantal/daloradius.git
cd daloradius

# Konfigurasi DaloRADIUS
cp library/daloradius.conf.php.sample library/daloradius.conf.php

sed -i "s|\$configValues\['CONFIG_DB_PASS'\] = ''|\$configValues['CONFIG_DB_PASS'] = '$DBPASS'|g" library/daloradius.conf.php

# Permission
chown -R www-data:www-data /var/www/daloradius

# Nginx config
cat >/etc/nginx/sites-available/mikradius.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root /var/www/daloradius;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
    }
}
EOF

# Replace if exists
ln -sf /etc/nginx/sites-available/mikradius.conf /etc/nginx/sites-enabled/

# Restart Nginx
systemctl restart nginx

# HTTPS Non-Interactive
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email --redirect --non-interactive

echo "=========================================="
echo "  Instalasi MikRadius Selesai!"
echo "=========================================="
echo "Login DaloRADIUS: https://$DOMAIN"
echo "User: administrator"
echo "Pass: radius"
