#!/bin/bash
# LEMP Stack Setup Script with PHP-FPM
# Usage: sudo ./setup-lemp.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== LEMP Stack Installation ===${NC}"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt update && apt upgrade -y
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum update -y || dnf update -y
else
    echo -e "${RED}Unsupported OS${NC}"
    exit 1
fi

# Install Nginx
echo -e "${YELLOW}Installing Nginx...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y nginx
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y nginx || dnf install -y nginx
fi

systemctl enable nginx
systemctl start nginx

# Install MariaDB/MySQL
echo -e "${YELLOW}Installing MariaDB...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y mariadb-server mariadb-client
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y mariadb-server mariadb || dnf install -y mariadb-server mariadb
fi

systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB
echo -e "${YELLOW}Securing MariaDB installation...${NC}"
mysql_secure_installation

# Install PHP-FPM and extensions
echo -e "${YELLOW}Installing PHP-FPM and extensions...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y php-fpm php-mysql php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-json php-intl \
        php-bcmath php-soap php-imagick
    
    # Get PHP version
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y php php-fpm php-mysqlnd php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-json php-intl \
        php-bcmath php-soap || \
    dnf install -y php php-fpm php-mysqlnd php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-json php-intl \
        php-bcmath php-soap
    
    PHP_FPM_SERVICE="php-fpm"
    PHP_FPM_SOCK="/run/php-fpm/www.sock"
fi

# Configure PHP-FPM
echo -e "${YELLOW}Configuring PHP-FPM...${NC}"
PHP_INI=$(php --ini | grep "Loaded Configuration File" | cut -d: -f2 | xargs)

# Optimize PHP settings
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
sed -i 's/^;date.timezone =.*/date.timezone = UTC/' "$PHP_INI"

systemctl enable $PHP_FPM_SERVICE
systemctl start $PHP_FPM_SERVICE

# Configure Nginx for PHP
echo -e "${YELLOW}Configuring Nginx for PHP...${NC}"
cat > /etc/nginx/conf.d/php-fpm.conf <<EOF
upstream php-fpm {
    server unix:${PHP_FPM_SOCK};
}
EOF

# Create default server block
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass php-fpm;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

# Create snippets directory if not exists
mkdir -p /etc/nginx/snippets

# Create fastcgi-php.conf snippet
cat > /etc/nginx/snippets/fastcgi-php.conf <<EOF
fastcgi_split_path_info ^(.+\.php)(/.+)$;
try_files \$fastcgi_script_name =404;
set \$path_info \$fastcgi_path_info;
fastcgi_param PATH_INFO \$path_info;
fastcgi_index index.php;
include fastcgi.conf;
EOF

# Create sites-available and sites-enabled directories
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Enable site
if [ ! -f /etc/nginx/sites-enabled/default ]; then
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi

# Update main nginx.conf to include sites-enabled
if ! grep -q "include /etc/nginx/sites-enabled/\*;" /etc/nginx/nginx.conf; then
    sed -i '/include \/etc\/nginx\/conf.d\/\*.conf;/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
fi

# Create phpinfo test page
echo -e "${YELLOW}Creating PHP test page...${NC}"
echo "<?php phpinfo(); ?>" > /var/www/html/info.php

# Set permissions
chown -R www-data:www-data /var/www/html 2>/dev/null || chown -R nginx:nginx /var/www/html

# Test and restart Nginx
nginx -t && systemctl restart nginx

# Install additional tools
echo -e "${YELLOW}Installing additional tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y certbot python3-certbot-nginx curl wget git unzip
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y certbot python3-certbot-nginx curl wget git unzip || \
    dnf install -y certbot python3-certbot-nginx curl wget git unzip
fi

# Install Docker for phpMyAdmin
echo -e "${YELLOW}Installing Docker...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y docker.io docker-compose
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y docker docker-compose || dnf install -y docker docker-compose
fi

systemctl enable docker
systemctl start docker

# Install quota tools
echo -e "${YELLOW}Installing quota tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y quota quotatool
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y quota || dnf install -y quota
fi

# Display status
echo -e "${GREEN}=== Installation Complete ===${NC}"
echo -e "${GREEN}Nginx:${NC} $(systemctl is-active nginx)"
echo -e "${GREEN}MariaDB:${NC} $(systemctl is-active mariadb)"
echo -e "${GREEN}PHP-FPM:${NC} $(systemctl is-active $PHP_FPM_SERVICE)"
echo -e "${GREEN}Docker:${NC} $(systemctl is-active docker)"
echo ""
echo -e "${YELLOW}PHP Version:${NC} $(php -v | head -n 1)"
echo -e "${YELLOW}PHP-FPM Socket:${NC} $PHP_FPM_SOCK"
echo ""
echo -e "${YELLOW}Test PHP: http://your-server-ip/info.php${NC}"
echo -e "${RED}Remember to remove info.php after testing!${NC}"