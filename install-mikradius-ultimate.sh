#!/usr/bin/env bash
# install-mikradius-ultimate.sh
# Ultimate All-in-One installer:
# FreeRADIUS + MariaDB + DaloRADIUS + Certbot(HTTPS) + UFW + helpers for multi-domain & multi-radius
# Author: Hendri (customized)
# Date: 2025-11-20
set -euo pipefail
IFS=$'\n\t'

### =======================
### CONFIG — edit only if needed
### =======================
DOMAIN="mikradius.hendri.site"
CERTBOT_EMAIL="heruu2004@gmail.com"
RADIUS_DB_USER="radius"
RADIUS_DB_PASS="${RADIUS_DB_PASS:-radius123}"   # default radius123
WEBROOT="/var/www/html"
DALORADIUS_DIR="${WEBROOT}/daloradius"
FREERADIUS_VERSION_DIR="/etc/freeradius/3.0"
UFW_ALLOWED_PORTS=(22 80 443)                  # 1812/1813 added for UDP later

### =======================
### Helpers
### =======================
info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m   $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
fatal()   { echo -e "\e[31m[FATAL]\e[0m $*"; exit 1; }

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fatal "Script must be run as root. Use: sudo bash $0"
  fi
}

apt_install() {
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

### =======================
### Start
### =======================
check_root
export DEBIAN_FRONTEND=noninteractive

info "Mulai instalasi MikRadius (FreeRADIUS + MariaDB + DaloRADIUS + HTTPS + UFW)"
info "Domain: ${DOMAIN}"
info "Certbot email: ${CERTBOT_EMAIL}"

# Update
info "Updating apt repositories..."
apt-get update -y
apt-get upgrade -y

# Install required packages
info "Install prerequisites..."
apt_install software-properties-common curl wget unzip git lsb-release apt-transport-https ca-certificates gnupg

# Add Certbot (snap) if not available and ensure snapd
if ! command -v snap >/dev/null 2>&1; then
  info "Installing snapd..."
  apt_install snapd
  systemctl enable --now snapd
fi
if ! snap list certbot >/dev/null 2>&1; then
  info "Installing certbot via snap..."
  snap install core; snap refresh core
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot || true
fi

# Install MariaDB, FreeRADIUS, Apache2, PHP, Certbot dependencies
info "Installing MariaDB, FreeRADIUS, Apache2, PHP and utilities..."
apt_install mariadb-server mariadb-client freeradius freeradius-mysql apache2 php php-mysqli php-gd php-pear php-xml php-mbstring php-curl unzip

# Ensure services enabled
systemctl enable --now mariadb
systemctl enable --now apache2

# Setup MariaDB - create database & user
info "Configuring MariaDB: creating database and user"
mysql -e "CREATE DATABASE IF NOT EXISTS radius;"
# create user with password (works on MariaDB 10.x)
mysql -e "CREATE USER IF NOT EXISTS '${RADIUS_DB_USER}'@'localhost' IDENTIFIED BY '${RADIUS_DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON radius.* TO '${RADIUS_DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

success "Database radius dan user ${RADIUS_DB_USER} dibuat."

# Import FreeRADIUS schema
SCHEMA_PATH="${FREERADIUS_VERSION_DIR}/mods-config/sql/main/mysql/schema.sql"
if [ -f "${SCHEMA_PATH}" ]; then
  info "Importing FreeRADIUS SQL schema into radius DB..."
  mysql -u "${RADIUS_DB_USER}" -p"${RADIUS_DB_PASS}" radius < "${SCHEMA_PATH}"
  success "Schema FreeRADIUS berhasil di-import."
else
  warn "Schema FreeRADIUS tidak ditemukan di ${SCHEMA_PATH}. Pastikan paket freeradius-mysql terpasang."
fi

# Configure FreeRADIUS SQL module
info "Mencatat konfigurasi SQL FreeRADIUS..."
SQL_MOD_AVAILABLE="/etc/freeradius/3.0/mods-available/sql"
SQL_MOD_ENABLED="/etc/freeradius/3.0/mods-enabled/sql"

if [ -f "${SQL_MOD_AVAILABLE}" ]; then
  # backup
  cp -n "${SQL_MOD_AVAILABLE}" "${SQL_MOD_AVAILABLE}.bak" || true

  # Replace minimal set of parameters (sed)
  sed -e "s|server = .*|server = \"localhost\"|g" \
      -e "s|login = .*|login = \"${RADIUS_DB_USER}\"|g" \
      -e "s|password = .*|password = \"${RADIUS_DB_PASS}\"|g" \
      -i "${SQL_MOD_AVAILABLE}" || true

  # enable sql
  ln -sf "${SQL_MOD_AVAILABLE}" "${SQL_MOD_ENABLED}"
  success "Module SQL FreeRADIUS dikonfigurasi dan di-enable."
else
  warn "File ${SQL_MOD_AVAILABLE} tidak ditemukan — lewati pengaturan SQL FreeRADIUS otomatis."
fi

# Install DaloRADIUS
info "Mengunduh & menginstal DaloRADIUS di ${DALORADIUS_DIR}..."
mkdir -p "${WEBROOT}"
cd "${WEBROOT}"
if [ -d "${DALORADIUS_DIR}" ]; then
  warn "Direktori ${DALORADIUS_DIR} sudah ada — membuat backup..."
  mv "${DALORADIUS_DIR}" "${DALORADIUS_DIR}-backup-$(date +%s)"
fi

# get latest daloradius from GitHub
TMP_ZIP="/tmp/daloradius-master.zip"
wget -q -O "${TMP_ZIP}" "https://github.com/lirantal/daloradius/archive/refs/heads/master.zip"
unzip -q "${TMP_ZIP}"
mv daloradius-master daloradius
rm -f "${TMP_ZIP}"

# copy sample config and set credentials
cd "${DALORADIUS_DIR}"
if [ -f library/daloradius.conf.php.sample ]; then
  cp -n library/daloradius.conf.php.sample library/daloradius.conf.php
fi

# set DB credentials in daloradius.conf.php
php_conf_file="library/daloradius.conf.php"
if [ -f "${php_conf_file}" ]; then
  sed -i "s/'DB_USER', '.*'/'DB_USER', '${RADIUS_DB_USER}'/g" "${php_conf_file}" || true
  sed -i "s/'DB_PASS', '.*'/'DB_PASS', '${RADIUS_DB_PASS}'/g" "${php_conf_file}" || true
  sed -i "s/'RADIUS_DB', '.*'/'RADIUS_DB', 'radius'/g" "${php_conf_file}" || true
fi

# import daloradius SQL
DALORADIUS_SQL="${DALORADIUS_DIR}/contrib/db/fr2-mysql-daloradius-and-freeradius.sql"
if [ -f "${DALORADIUS_SQL}" ]; then
  info "Importing DaloRADIUS SQL schema..."
  mysql -u "${RADIUS_DB_USER}" -p"${RADIUS_DB_PASS}" radius < "${DALORADIUS_SQL}"
  success "DaloRADIUS schema di-import."
else
  warn "File SQL DaloRADIUS tidak ditemukan di ${DALORADIUS_SQL}. Kamu bisa import manual nanti."
fi

# set permissions
chown -R www-data:www-data "${DALORADIUS_DIR}"
chmod -R 755 "${DALORADIUS_DIR}"

# Configure Apache for Daloradius (simple Alias)
APACHE_CONF="/etc/apache2/sites-available/000-default.conf"
if ! grep -q "Alias /daloradius" "${APACHE_CONF}"; then
  info "Menambahkan Alias /daloradius ke konfigurasi Apache..."
  cat >> "${APACHE_CONF}" <<EOF

# DaloRADIUS alias
Alias /daloradius ${DALORADIUS_DIR}
<Directory ${DALORADIUS_DIR}>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
  systemctl reload apache2
fi

# Enable PHP modules recommended
info "Mengaktifkan module PHP (if required) and restarting Apache..."
phpenmod mysqli mbstring
systemctl restart apache2

# Firewall (UFW)
info "Setting up UFW firewall..."
apt_install ufw
ufw --force reset
for p in "${UFW_ALLOWED_PORTS[@]}"; do ufw allow "${p}"; done
# Allow FreeRADIUS ports (UDP)
ufw allow 1812/udp
ufw allow 1813/udp
ufw allow 3799/udp   # optional (coa)
ufw --force enable
success "UFW aktif dengan rule dasar."

# Obtain SSL certificate with Certbot (Apache plugin)
info "Menjalankan Certbot untuk domain ${DOMAIN}..."
if certbot --version >/dev/null 2>&1; then
  # create Apache virtualhost if domain points to VPS
  SITE_CONF="/etc/apache2/sites-available/${DOMAIN}.conf"
  if [ ! -f "${SITE_CONF}" ]; then
    cat > "${SITE_CONF}" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${WEBROOT}
    # ensure daloradius alias works
    Alias /daloradius ${DALORADIUS_DIR}
    <Directory ${DALORADIUS_DIR}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    a2ensite "${DOMAIN}.conf" || true
    systemctl reload apache2
  fi

  # run certbot non-interactive
  certbot --apache --non-interactive --agree-tos --email "${CERTBOT_EMAIL}" -d "${DOMAIN}" || warn "Certbot gagal. Pastikan DNS A record mengarah ke VPS dan port 80 terbuka."
  success "Certbot di-request (periksa status)."
else
  warn "Certbot tidak tersedia. SSL tidak dibuat."
fi

# Restart services
info "Restart services..."
systemctl restart mariadb || true
systemctl restart freeradius || true
systemctl restart apache2 || true

success "Instalasi dasar selesai."

# Output info & quick tests
echo "==========================================="
echo "MikRadius installer finished."
echo "DaloRADIUS URL: https://${DOMAIN}/daloradius   (atau http://${DOMAIN}/daloradius jika cert belum aktif)"
echo "DB user: ${RADIUS_DB_USER}"
echo "DB pass: ${RADIUS_DB_PASS}"
echo ""
echo "To add extra domains (multi-domain), run this script with EXTRA_DOMAINS env:"
echo "  EXTRA_DOMAINS=\"sub1.example.com,sub2.example.com\" bash $0 --add-domains"
echo ""
echo "To add another FreeRADIUS instance (multi-radius), see function add_radius_instance in script."
echo "==========================================="

### =======================
### Multi-domain mode (optional): add virtualhosts & certs for comma separated domains
### =======================
if [ "${1:-}" = "--add-domains" ] || [ "${1:-}" = "add-domains" ]; then
  EXTRA="${EXTRA_DOMAINS:-}"
  if [ -z "${EXTRA}" ]; then
    warn "Tidak ada EXTRA_DOMAINS. Set env EXTRA_DOMAINS before menjalankan."
    exit 0
  fi
  IFS=',' read -r -a arr <<< "${EXTRA}"
  for d in "${arr[@]}"; do
    d=$(echo "${d}" | xargs)
    if [ -z "${d}" ]; then continue; fi
    cat > "/etc/apache2/sites-available/${d}.conf" <<EOF
<VirtualHost *:80>
    ServerName ${d}
    DocumentRoot ${WEBROOT}
    Alias /daloradius ${DALORADIUS_DIR}
    <Directory ${DALORADIUS_DIR}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    a2ensite "${d}.conf" || true
    systemctl reload apache2
    certbot --apache --non-interactive --agree-tos --email "${CERTBOT_EMAIL}" -d "${d}" || warn "Certbot gagal untuk ${d}"
  done
  success "Tambah domain selesai."
fi

### =======================
### Function: add_radius_instance (helper)
### =======================
cat <<'EOF_FUNC'
# Untuk menambah instance FreeRADIUS baru (multi-radius) -- contoh manual:
# 1) Salin folder konfigurasi radius:
#    cp -a /etc/freeradius/3.0 /etc/freeradius-INSTANCE/
# 2) Edit port/paths & systemd service file agar menggunakan nama service baru.
# 3) Buat database terpisah atau shared DB dengan prefix tabel untuk instance.
# Karena langkah ini sensitif, script hanya menyediakan petunjuk; jalankan manual atau minta saya buatkan skrip tambahan.
EOF_FUNC

exit 0
