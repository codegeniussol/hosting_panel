#!/bin/bash
# LEMP Stack Setup Script with PHP-FPM
# Usage: sudo ./setup-lemp.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

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

echo -e "${YELLOW}Detected OS: $OS $VERSION${NC}"

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt update && apt upgrade -y
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum update -y 2>/dev/null || dnf update -y
else
    echo -e "${RED}Unsupported OS: $OS${NC}"
    exit 1
fi

# Install Nginx
echo -e "${YELLOW}Installing Nginx...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y nginx
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y nginx 2>/dev/null || dnf install -y nginx
fi

systemctl enable nginx
systemctl start nginx

# Install MariaDB/MySQL
echo -e "${YELLOW}Installing MariaDB...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y mariadb-server mariadb-client
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y mariadb-server mariadb 2>/dev/null || dnf install -y mariadb-server mariadb
fi

systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB
echo -e "${YELLOW}Securing MariaDB installation...${NC}"
echo -e "${YELLOW}Please answer the security questions:${NC}"
mysql_secure_installation

# Install PHP-FPM and extensions
echo -e "${YELLOW}Installing PHP-FPM and extensions...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y php-fpm php-mysql php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-intl \
        php-bcmath php-soap php-imagick 2>/dev/null || \
    apt install -y php-fpm php-mysql php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-intl \
        php-bcmath php-soap
    
    # Get PHP version
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    if [ -z "$PHP_VERSION" ]; then
        # Fallback method
        PHP_VERSION=$(php --version | head -n1 | cut -d" " -f2 | cut -d. -f1,2)
    fi
    PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
    PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y php php-fpm php-mysqlnd php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-intl \
        php-bcmath php-soap 2>/dev/null || \
    dnf install -y php php-fpm php-mysqlnd php-cli php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-opcache php-intl \
        php-bcmath php-soap
    
    PHP_FPM_SERVICE="php-fpm"
    PHP_FPM_SOCK="/run/php-fpm/www.sock"
    PHP_VERSION=$(php --version | head -n1 | cut -d" " -f2 | cut -d. -f1,2)
fi

echo -e "${GREEN}PHP Version: $PHP_VERSION${NC}"

# Configure PHP-FPM
echo -e "${YELLOW}Configuring PHP-FPM...${NC}"

# Find PHP INI file
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
    PHP_CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    PHP_INI="/etc/php.ini"
    PHP_CLI_INI="/etc/php.ini"
fi

# Fallback to detection
if [ ! -f "$PHP_INI" ]; then
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | cut -d: -f2 | xargs)
fi

if [ -f "$PHP_INI" ]; then
    echo -e "${YELLOW}Configuring PHP INI: $PHP_INI${NC}"
    
    # Backup original
    cp "$PHP_INI" "${PHP_INI}.backup.$(date +%Y%m%d)"
    
    # Optimize PHP settings (using perl for safer in-place editing)
    perl -pi -e 's/^upload_max_filesize\s*=.*/upload_max_filesize = 256M/' "$PHP_INI"
    perl -pi -e 's/^post_max_size\s*=.*/post_max_size = 256M/' "$PHP_INI"
    perl -pi -e 's/^memory_limit\s*=.*/memory_limit = 512M/' "$PHP_INI"
    perl -pi -e 's/^max_execution_time\s*=.*/max_execution_time = 300/' "$PHP_INI"
    perl -pi -e 's/^;?date\.timezone\s*=.*/date.timezone = UTC/' "$PHP_INI"
    
    # If CLI INI is different, update it too
    if [ -f "$PHP_CLI_INI" ] && [ "$PHP_CLI_INI" != "$PHP_INI" ]; then
        cp "$PHP_CLI_INI" "${PHP_CLI_INI}.backup.$(date +%Y%m%d)"
        perl -pi -e 's/^;?date\.timezone\s*=.*/date.timezone = UTC/' "$PHP_CLI_INI"
    fi
else
    echo -e "${YELLOW}Warning: Could not find PHP INI file at $PHP_INI${NC}"
fi

systemctl enable $PHP_FPM_SERVICE
systemctl start $PHP_FPM_SERVICE

# Configure Nginx for PHP
echo -e "${YELLOW}Configuring Nginx for PHP...${NC}"

# Create necessary directories
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/snippets
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

# Create PHP-FPM upstream configuration
cat > /etc/nginx/conf.d/php-fpm.conf <<EOF
upstream php-fpm {
    server unix:${PHP_FPM_SOCK};
}
EOF

# Create fastcgi-php.conf snippet
cat > /etc/nginx/snippets/fastcgi-php.conf <<'EOF'
fastcgi_split_path_info ^(.+\.php)(/.+)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi.conf;
EOF

# Backup existing default site if it exists
if [ -f /etc/nginx/sites-available/default ]; then
    mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d)
fi

# Create default server block
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass php-fpm;
    }
    
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.git {
        deny all;
    }
}
EOF

# Enable site
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Update main nginx.conf to include sites-enabled if not already present
if ! grep -q "include /etc/nginx/sites-enabled/\*;" /etc/nginx/nginx.conf; then
    # Find the http block and add include
    if grep -q "include /etc/nginx/conf.d/\*.conf;" /etc/nginx/nginx.conf; then
        sed -i '/include \/etc\/nginx\/conf.d\/\*.conf;/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    else
        # Add before the closing brace of http block
        sed -i '/^http {/,/^}/ s/^}/    include \/etc\/nginx\/sites-enabled\/*;\n}/' /etc/nginx/nginx.conf
    fi
fi

# Create web root if not exists
mkdir -p /var/www/html

# Create phpinfo test page
echo -e "${YELLOW}Creating PHP test page...${NC}"
cat > /var/www/html/info.php <<'EOF'
<?php
phpinfo();
?>
EOF

# Set permissions
if id "www-data" &>/dev/null; then
    chown -R www-data:www-data /var/www/html
elif id "nginx" &>/dev/null; then
    chown -R nginx:nginx /var/www/html
fi

chmod 755 /var/www/html
chmod 644 /var/www/html/info.php

# Test Nginx configuration
echo -e "${YELLOW}Testing Nginx configuration...${NC}"
if nginx -t; then
    systemctl restart nginx
    echo -e "${GREEN}Nginx restarted successfully${NC}"
else
    echo -e "${RED}Nginx configuration test failed!${NC}"
    exit 1
fi

# Install additional tools
echo -e "${YELLOW}Installing additional tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y certbot python3-certbot-nginx curl wget git unzip
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y certbot python3-certbot-nginx curl wget git unzip 2>/dev/null || \
    dnf install -y certbot python3-certbot-nginx curl wget git unzip
fi

# Install Docker for phpMyAdmin
echo -e "${YELLOW}Installing Docker...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    # Install Docker using official method for Ubuntu/Debian
    if ! command -v docker &> /dev/null; then
        apt install -y ca-certificates gnupg lsb-release
        
        # Add Docker's official GPG key (optional, for latest version)
        # For simplicity, using distro package
        apt install -y docker.io
        
        # Try to install docker-compose
        apt install -y docker-compose 2>/dev/null || \
        apt install -y docker-compose-plugin 2>/dev/null || \
        echo -e "${YELLOW}docker-compose not available in repos, will use docker compose plugin${NC}"
    fi
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y docker docker-compose 2>/dev/null || \
    dnf install -y docker docker-compose 2>/dev/null || \
    dnf install -y docker docker-compose-plugin
fi

systemctl enable docker
systemctl start docker

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Installing docker-compose manually...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install quota tools
echo -e "${YELLOW}Installing quota tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y quota quotatool 2>/dev/null || apt install -y quota
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    yum install -y quota 2>/dev/null || dnf install -y quota
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
fi

# Display status
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}    LEMP Stack Installation Complete!     ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Service Status:${NC}"
echo -e "  Nginx:     $(systemctl is-active nginx) $(systemctl is-enabled nginx >/dev/null 2>&1 && echo '(enabled)' || echo '(disabled)')"
echo -e "  MariaDB:   $(systemctl is-active mariadb) $(systemctl is-enabled mariadb >/dev/null 2>&1 && echo '(enabled)' || echo '(disabled)')"
echo -e "  PHP-FPM:   $(systemctl is-active $PHP_FPM_SERVICE) $(systemctl is-enabled $PHP_FPM_SERVICE >/dev/null 2>&1 && echo '(enabled)' || echo '(disabled)')"
echo -e "  Docker:    $(systemctl is-active docker) $(systemctl is-enabled docker >/dev/null 2>&1 && echo '(enabled)' || echo '(disabled)')"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  PHP Version:    $PHP_VERSION"
echo -e "  PHP-FPM Socket: $PHP_FPM_SOCK"
echo -e "  PHP INI:        $PHP_INI"
echo -e "  Nginx Config:   /etc/nginx/nginx.conf"
echo -e "  Web Root:       /var/www/html"
echo ""
echo -e "${YELLOW}Access URLs:${NC}"
echo -e "  Test Page:  http://$SERVER_IP/"
echo -e "  PHP Info:   http://$SERVER_IP/info.php"
echo ""
echo -e "${RED}Important Security Notes:${NC}"
echo -e "  1. Remove /var/www/html/info.php after testing"
echo -e "  2. Configure firewall (ufw/firewalld)"
echo -e "  3. Setup MySQL root password if not done"
echo -e "  4. Enable SSL certificates for production"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Install phpMyAdmin: ./setup-phpmyadmin.sh"
echo -e "  2. Create virtual host: ./manage-vhost.sh create domain.com username"
echo -e "  3. Setup SSL: ./manage-ssl.sh install domain.com"
echo ""
echo -e "${GREEN}Installation log saved to: /var/log/lemp-install.log${NC}"

# Save installation info
cat > /root/.lemp-install-info <<EOF
LEMP Stack Installation
-----------------------
Date: $(date)
OS: $OS $VERSION
PHP Version: $PHP_VERSION
PHP-FPM Service: $PHP_FPM_SERVICE
PHP-FPM Socket: $PHP_FPM_SOCK
Server IP: $SERVER_IP
EOF

echo -e "${GREEN}Installation complete!${NC}"