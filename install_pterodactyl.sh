#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting Pterodactyl installation..."

# Update system and install required packages
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing dependencies..."
sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
sudo apt update
sudo apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Add Pterodactyl repository and install Panel
echo "Installing Pterodactyl Panel..."
cd /var/www
sudo mkdir -p pterodactyl
cd pterodactyl
sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
sudo tar -xzvf panel.tar.gz
sudo chmod -R 755 storage/* bootstrap/cache
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

echo "Configuring Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
sudo curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
sudo tar -xzvf panel.tar.gz
sudo chmod -R 755 storage/* bootstrap/cache/

cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/pterodactyl
sudo chmod -R 755 /var/www/pterodactyl

echo "Ensuring MariaDB is running..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl restart mariadb

# Database setup
echo "Setting up database..."
sudo mysql -u root -e "DROP DATABASE IF EXISTS panel;"
sudo mysql -u root -e "CREATE DATABASE panel;"
sudo mysql -u root -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
sudo mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'securepassword';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

# No user or password needed since root is used without a password.

echo "Configuring Pterodactyl environment file..."
sudo sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|" /var/www/pterodactyl/.env
sudo sed -i "s|DB_PORT=.*|DB_PORT=3306|" /var/www/pterodactyl/.env
sudo sed -i "s|DB_DATABASE=.*|DB_DATABASE=panel|" /var/www/pterodactyl/.env
sudo sed -i "s|DB_USERNAME=.*|DB_USERNAME=pterodactyl|" /var/www/pterodactyl/.env
sudo sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=securepassword|" /var/www/pterodactyl/.env

# Configure .env file with localhost and no database password
echo "Updating environment configuration..."
read -p "Enter a valid email address for the Egg Author: " email_address
sudo sed -i "s|^APP_SERVICE_AUTHOR=.*|APP_SERVICE_AUTHOR=$email_address|" /var/www/pterodactyl/.env
sudo sed -i "s|^APP_URL=.*|APP_URL=http://localhost|" /var/www/pterodactyl/.env

sudo sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=mysql|" /var/www/pterodactyl/.env
sudo sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|" /var/www/pterodactyl/.env
sudo sed -i "s|^DB_PORT=.*|DB_PORT=3306|" /var/www/pterodactyl/.env
sudo sed -i "s|^DB_DATABASE=.*|DB_DATABASE=panel|" /var/www/pterodactyl/.env
sudo sed -i "s|^DB_USERNAME=.*|DB_USERNAME=pterodactyl|" /var/www/pterodactyl/.env
sudo sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=securepassword|" /var/www/pterodactyl/.env



# Clear and cache configuration
echo "Caching environment configuration..."
cd /var/www/pterodactyl
php artisan config:clear
php artisan config:cache

# Run migrations
echo "Running database migrations..."
php artisan migrate --seed --force
# Set up nginx
echo "Configuring NGINX..."
sudo bash -c "cat > /etc/nginx/sites-available/pterodactyl << 'EOF'
server {
    listen 80;
    server_name localhost;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF"



sudo ln -s /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/pterodactyl
sudo nginx -t
sudo systemctl restart nginx

# Finish up
echo "Finalizing setup..."
sudo systemctl enable --now redis-server
sudo systemctl enable --now mariadb
sudo systemctl restart nginx

echo "Creating default admin user..."

# Install the expect tool if not already installed
sudo apt install -y expect
cd /var/www/pterodactyl

# Automate the creation of the admin user
sudo expect <<EOF
spawn sudo php artisan p:user:make
expect "Is this user an administrator? (yes/no)"
send "yes\r"
expect "Email Address"
send "example.admin@example.com\r"
expect "Username"
send "admin\r"
expect "First Name"
send "admin\r"
expect "Last Name"
send "admin\r"
expect "Password"
send "Admin1234\r"
expect eof
EOF

echo "Admin user created successfully!"

echo "Pterodactyl installation completed! Access it at http://localhost"
echo "user: admin"
echo "pass: Admin1234"
echo "Please change user password before continueing"
