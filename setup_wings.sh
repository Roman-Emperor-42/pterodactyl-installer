#!/bin/bash

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

echo "Follow install instructions listed on github:"
read -p "> " user_command
if [[ -n "$user_command" ]]; then
    eval "$user_command"
else
    echo "No command entered. Exiting."
fi

echo "adding allowed orgins:"
echo -e "allowed_origins:\n  - http://localhost\n  - http://127.0.0.1" | sudo tee -a /etc/pterodactyl/config.yml

sudo systemctl restart wings
