#!/usr/bin/env bash
# MikRadius Ultimate Installer (Manual Input Version)
# FreeRADIUS + DaloRADIUS + MariaDB + Certbot + Firewall
# By Hendri

set -e
clear

echo "============================================="
echo "     MIKRADIUS ULTIMATE INSTALLER BY Hendri"
echo "============================================="
echo ""
read -p "Masukkan DOMAIN untuk DaloRADIUS (contoh: mikradius.hendri.site): " DOMAIN
read -p "Masukkan EMAIL untuk Certbot (contoh: email@domain.com): " CERTBOT_EMAIL
read -p "Password DB Radius (default = radius123): " RADIUS_DB_PASS
RADIUS_DB_PASS=${RADIUS_DB_PASS:-radius123}

echo ""
echo "---------------------------------------------"
echo " Domain         : $DOMAIN"
echo " Certbot Email  : $CERTBOT_EMAIL"
echo " DB Password    : $RADIUS_DB_PASS"
echo "---------------------------------------------"
echo ""

read -p "Tekan ENTER untuk mulai instalasi..."

apt update -y
apt upgrade -y

apt install -y mariadb-server mariadb-client apache2 php php-mysqli php-gd php-pear php-xml php-mbstring php-curl unzip wget git freeradius freeradius-mysql ufw snapd

systemctl enable --now snapd
snap install core
snap refresh core
snap install --classic certbot
ln -s /snap/bin/certbot /usr/bin/certbot || true

echo "[+] Membuat Database Radius..."
mysql -e "CREATE DATABASE IF NOT EXISTS radius;"
mysql -e "CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY '${RADIUS_DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

echo "[+] Import schema FreeRADIUS..."
mysql -u radius -p${RADIUS_DB_PASS} radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

echo "[+] Konfigurasi FreeRADIUS SQL..."
SQLFILE="/etc/freeradius/3.0/mods-available/sql"
sed -i "s|login = .*|login = \"radius\"|" $SQLFILE
sed -i "s|password = .*|password = \"${RADIUS_DB_PASS}\"|" $SQLFILE
sed -i "s|radius_db = .*|radius_db = \"radius\"|" $SQLFILE
ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

echo "[+] Install DaloRADIUS..."
cd /var/www/html
wget -q https://github.com/lirantal/daloradius/archive/master.zip -O dalo.zip
unzip -q dalo.zip
mv daloradius-master daloradius
rm dalo.zip

cp daloradius/library/daloradius.conf.php.sample daloradius/library/daloradius.conf.php
sed -i "s/'DB_USER', ''/'DB_USER', 'radius'/" daloradius/library/daloradius.conf.php
sed -i "s/'DB_PASS', ''/'DB_PASS', '${RADIUS_DB_PASS}'/" daloradius/library/daloradius.conf.php

mysql -u radius -p${RADIUS_DB_PASS} radius < daloradius/contrib/db/fr2-mysql-daloradius-and-freeradius.sql

chown -R www-data:www-data /var/www/html/daloradius
chmod -R 755 /var/www/html/daloradius

echo "[+] Konfigurasi Apache2..."
cat > /etc/apache2/sites-available/${DOMAIN}.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot /var/www/html

    Alias /daloradius /var/www/html/daloradius
    <Directory /var/www/html/daloradius>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite ${DOMAIN}.conf
a2dissite 000-default.conf
systemctl reload apache2

echo "[+] Mengambil sertifikat SSL..."
certbot --apache --agree-tos --non-interactive --email ${CERTBOT_EMAIL} -d ${DOMAIN} || echo "Gagal mengambil SSL"

echo "[+] Konfigurasi Firewall..."
ufw --force reset
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 1812/udp
ufw allow 1813/udp
ufw enable || true

systemctl restart apache2
systemctl restart mariadb
systemctl restart freeradius

clear
echo "============================================="
echo "        INSTALASI SELESAI!"
echo "============================================="
echo "URL Panel DaloRADIUS:"
echo "  https://${DOMAIN}/daloradius"
echo ""
echo "Login Default:"
echo "  Username : administrator"
echo "  Password : radius"
echo ""
echo "DB Login:"
echo "  user: radius"
echo "  pass: ${RADIUS_DB_PASS}"
echo ""
echo "Cek status FreeRADIUS:"
echo "  systemctl status freeradius"
echo ""
echo "============================================="
