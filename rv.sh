#!/bin/bash

set -e

DOMAIN="status.arialnodes.in"
SERVER_IP="178.128.54.237"
TARGET_PORT="3001"
TARGET_PATH="/status/uptime"
EMAIL="forrishabh667@gmail.com"

# Function to install required packages
install_packages() {
    echo "Installing necessary packages..."
    sudo apt update && sudo apt install -y nginx certbot python3-certbot-nginx
}

# Function to configure Nginx reverse proxy
setup_nginx() {
    echo "Setting up Nginx reverse proxy..."
    
    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://$SERVER_IP:$TARGET_PORT$TARGET_PATH;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

    # Enable the configuration
    sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

    # Restart Nginx
    sudo systemctl restart nginx
}

# Function to set up SSL with Let's Encrypt
setup_ssl() {
    echo "Installing SSL certificate..."
    sudo certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

    # Auto-renew SSL
    sudo certbot renew --dry-run
}

# Run functions
install_packages
setup_nginx
setup_ssl

echo "Reverse proxy setup complete! Visit: https://$DOMAIN"
