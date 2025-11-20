# Installer MikRadius – NATVPS
Auto Installer FreeRADIUS + DaloRADIUS + MariaDB + HTTPS (Certbot)  
Mendukung Multi Domain, Multi Radius, dan Firewall Security.

## ✨ Fitur
- Install FreeRADIUS 3 + Modul MySQL
- Install MariaDB & otomatis import schema
- Install DaloRADIUS + auto konfigurasi database
- Support HTTPS (Let’s Encrypt / Certbot)
- Support Multi Radius (beberapa instance radius dalam 1 VPS)
- Support Multi Domain untuk panel DaloRADIUS
- Hardening Firewall (UFW)
- Auto detect OS (Ubuntu 20/22/24)
- Fully NATVPS Compatible
- HTTPS otomatis via Certbot (Apache plugin)
- Basic UFW hardening (allow 22,80,443,1812/udp,1813/udp)
- Support multi-domain (opsional)
- Helper notes untuk menambahkan multi-radius instance (manual step)
---
## Persyaratan
- VPS dengan akses root (sudo)
- DNS A record: `(subdomain.domain)` → IP VPS
- Port 80 & 443 terbuka (untuk Certbot)
- Sistem operasi: Ubuntu 20.04 / 22.04 / 24.04 (tested)

## 🚀 Cara Install
## Cara pakai (single-command)
```bash
# clone repo lalu jalankan
git clone https://github.com/USER/REPO.git
cd REPO
sudo bash install-mikradius-ultimate.sh
````



## 📌 Default Login DaloRADIUS

* URL: `https://domainkamu.com/daloradius`
* Username: `administrator`
* Password: `radius`

---

## 📡 Direktori Penting

* **FreeRADIUS config:** `/etc/freeradius/3.0/`
* **DaloRADIUS:** `/var/www/html/daloradius/`
* **Database:** `radius`

---

## 🔐 Fitur Keamanan

Installer menyediakan:

* Firewall otomatis (UFW)
* Block semua port kecuali: `22, 80, 443, 1812, 1813`
* Auto restart & auto enable service

---

## 🛠 Perintah Berguna

Cek status FreeRADIUS:

```bash
systemctl status freeradius
```

Tes autentikasi user:

```bash
radtest admin 1234 localhost 0 testing123
```

Restart FreeRADIUS:

```bash
systemctl restart freeradius
```

---

## 👨‍💻 Kontributor

* **Hendri** — NATVPS Indonesia
* ChatGPT Assistant

---

## 📜 License

MIT License.
