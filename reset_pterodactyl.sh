#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting Pterodactyl removal process..."

# Remove Pterodactyl files
echo "Removing Pterodactyl files..."
sudo rm -rf /var/www/pterodactyl

# Remove NGINX configuration
echo "Removing NGINX configuration..."
sudo rm -f /etc/nginx/sites-enabled/pterodactyl
sudo rm -f /etc/nginx/sites-available/pterodactyl
sudo systemctl restart nginx

echo "Ensuring MySQL service is running..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl restart mariadb

# Remove database
echo "Removing MySQL database..."
sudo mysql -u root -e "DROP DATABASE IF EXISTS pterodactyl;"
sudo mysql -u root -e "DROP USER IF EXISTS 'ptero'@'localhost';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

sudo rm -f /usr/share/keyrings/redis-archive-keyring.gpg

# Stop services
echo "Stopping services..."
sudo systemctl stop nginx redis-server mariadb
sudo systemctl disable nginx redis-server mariadb

# Uninstall dependencies
echo "Removing dependencies..."
sudo apt purge -y php8.1-cli php8.1-curl php8.1-mbstring php8.1-xml php8.1-bcmath php8.1-json php8.1-fpm mariadb-server redis-server nginx composer certbot python3-certbo>sudo apt autoremove -y
sudo apt autoclean

# Optionally remove ondrej/php repository (if added during installation)
echo "Removing ondrej/php repository..."
sudo add-apt-repository -r ppa:ondrej/php -y
sudo apt update

# Cleanup
echo "Cleaning up residual files..."
sudo rm -rf /var/log/nginx/pterodactyl_*

echo "Pterodactyl and its dependencies have been successfully removed. System reset to default state."
