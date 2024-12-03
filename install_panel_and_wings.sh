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
sudo rm -r /etc/nginx/sites-available/*
sudo rm -r /etc/nginx/sites-enabled/*
sudo touch /etc/nginx/sites-available/pterodactyl
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

echo "Purge unneeded packages and dependencies clearing over 100mb"
sudo apt purge thunderbird libreoffice-* rhythmbox totem cheese shotwell simple-scan aisleriot gnome-mines gnome-sudoku snapd flatpak yelp orca brltty gnome-accessibility-themes bluez gnome-bluetooth cups printer-driver-* hplip language-pack-* gnome-calendar gnome-maps gnome-characters gnome-logs gnome-contacts gnome-software gnome-system-monitor gnome-disk-utility gnome-control-center ubuntu-mono adwaita-icon-theme fonts-* nautilus gvfs avahi-daemon modemmanager wpa_supplicant qemu libvirt-* lxd lxc sane ghostscript fwupd policykit-1 zeitgeist geoclue
sudo apt autoremove --purge -y
sudo apt clean

echo "Admin user created successfully!"

echo "Pterodactyl installation completed! Access it at http://localhost or http://127.0.0.1"
echo "user: admin"
echo "pass: Admin1234"
echo "Please change user password before continueing"
echo "Note default user and password, press enter when your ready to continue install."

read  

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting Wings installation..."

# Check virtualization type
virt_type=$(systemd-detect-virt)
if [[ "$virt_type" == "openvz" || "$virt_type" == "lxc" ]]; then
    echo "Unsupported virtualization type detected ($virt_type). Exiting."
    exit 1
fi

# Update system and install dependencies
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget dmidecode software-properties-common tar unzip

# Install Docker
echo "Installing Docker..."
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
sudo systemctl enable --now docker

# Check Docker swap support
if ! docker info | grep -q "WARNING: No swap limit support"; then
    echo "Enabling Docker swap support..."
    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1"|' /etc/default/grub
    sudo update-grub
    echo "GRUB has been updated to enable swap support for Docker."
    echo "Please manually reboot your system to apply changes."
fi

# Create Pterodactyl directory structure
echo "Setting up Wings directory..."
sudo mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
sudo chmod u+x /usr/local/bin/wings

# Configure Wings (node configuration must be done manually via the Panel)
echo "Creating configuration file placeholder..."
sudo bash -c 'cat > /etc/pterodactyl/config.yml <<EOF
# Replace with the configuration from your Panel.
# Visit Nodes > [Your Node] > Configuration tab.
EOF'

# Create Wings systemd service
echo "Creating systemd service for Wings..."
sudo bash -c 'cat > /etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF'

# Reload systemd and start Wings
echo "Starting Wings service..."
sudo systemctl daemon-reload
sudo systemctl enable --now wings

echo "Wings installation complete!"
echo "Configure the node in the Panel and update /etc/pterodactyl/config.yml."
echo "ip to use for allocation"
hostname -I | awk '{print $1}'

echo "Text setup, better instructions on github:"
echo "login and go to admin area (gears in corner)"
echo "locations tab and create new location"
echo "new node, set name, location, set FQDN to 'localhost', use HTTP not SSL, set total memory and storage, set over allocation if you'd like. create node"
echo "assign allocation at ip below with unused ports (I use 27000 range)"
hostname -I | awk '{print $1}'
echo "configuration tab, generate token and paste command below:"
echo "Follow install instructions listed on github:"
read -p "> " user_command
if [[ -n "$user_command" ]]; then
    eval "$user_command"
else
    echo "No command entered. Exiting."
fi

echo "adding allowed orgins:"
echo -e "allowed_origins:\n  - http://localhost\n  - http://127.0.0.1" | sudo tee -a /etc/pterodactyl/config.yml
echo ""
echo "go to server area and configure server to your liking."

sudo systemctl restart wings
