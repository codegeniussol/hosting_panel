#!/bin/bash
# LEMP Stack Setup Script with Multiple PHP-FPM Versions
# Usage: sudo ./setup-lemp.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   LEMP Stack Multi-PHP Installation    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

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

# Validate OS support
case $OS in
    ubuntu|debian)
        PKG_MANAGER="apt"
        ;;
    centos|rhel|rocky|almalinux)
        if command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        else
            PKG_MANAGER="yum"
        fi
        ;;
    *)
        echo -e "${RED}Unsupported OS: $OS${NC}"
        exit 1
        ;;
esac

# PHP version selection
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     PHP Version Installation Mode      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Select PHP installation mode:${NC}"
echo ""
echo "1. Install single PHP version (choose specific version)"
echo "2. Install multiple PHP versions (7.4, 8.0, 8.1, 8.2, 8.3)"
echo "3. Install all available PHP versions"
echo "4. System default PHP only"
echo ""
read -p "Enter choice [1-4]: " PHP_MODE

# Available PHP versions
AVAILABLE_PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
SELECTED_PHP_VERSIONS=()
DEFAULT_PHP_VERSION=""

case $PHP_MODE in
    1)
        echo ""
        echo -e "${YELLOW}Select PHP version to install:${NC}"
        echo ""
        for i in "${!AVAILABLE_PHP_VERSIONS[@]}"; do
            echo "$((i+1)). PHP ${AVAILABLE_PHP_VERSIONS[$i]}"
        done
        echo ""
        read -p "Enter choice [1-${#AVAILABLE_PHP_VERSIONS[@]}]: " VERSION_CHOICE
        
        if [ "$VERSION_CHOICE" -ge 1 ] && [ "$VERSION_CHOICE" -le "${#AVAILABLE_PHP_VERSIONS[@]}" ]; then
            SELECTED_PHP_VERSIONS=("${AVAILABLE_PHP_VERSIONS[$((VERSION_CHOICE-1))]}")
            DEFAULT_PHP_VERSION="${AVAILABLE_PHP_VERSIONS[$((VERSION_CHOICE-1))]}"
        else
            echo -e "${RED}Invalid choice${NC}"
            exit 1
        fi
        ;;
    2)
        echo ""
        echo -e "${YELLOW}Select PHP versions to install (space-separated):${NC}"
        echo ""
        for i in "${!AVAILABLE_PHP_VERSIONS[@]}"; do
            echo "$((i+1)). PHP ${AVAILABLE_PHP_VERSIONS[$i]}"
        done
        echo ""
        read -p "Enter choices (e.g., 1 3 5): " -a CHOICES
        
        for choice in "${CHOICES[@]}"; do
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#AVAILABLE_PHP_VERSIONS[@]}" ]; then
                SELECTED_PHP_VERSIONS+=("${AVAILABLE_PHP_VERSIONS[$((choice-1))]}")
            fi
        done
        
        if [ ${#SELECTED_PHP_VERSIONS[@]} -eq 0 ]; then
            echo -e "${RED}No valid versions selected${NC}"
            exit 1
        fi
        
        # Set default
        echo ""
        echo -e "${YELLOW}Select default PHP version:${NC}"
        for i in "${!SELECTED_PHP_VERSIONS[@]}"; do
            echo "$((i+1)). PHP ${SELECTED_PHP_VERSIONS[$i]}"
        done
        read -p "Enter choice: " DEFAULT_CHOICE
        DEFAULT_PHP_VERSION="${SELECTED_PHP_VERSIONS[$((DEFAULT_CHOICE-1))]}"
        ;;
    3)
        SELECTED_PHP_VERSIONS=("${AVAILABLE_PHP_VERSIONS[@]}")
        DEFAULT_PHP_VERSION="8.2"
        echo -e "${GREEN}Installing all available PHP versions${NC}"
        ;;
    4)
        SELECTED_PHP_VERSIONS=()
        echo -e "${GREEN}Installing system default PHP only${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Selected PHP versions: ${SELECTED_PHP_VERSIONS[*]}${NC}"
if [ -n "$DEFAULT_PHP_VERSION" ]; then
    echo -e "${GREEN}Default PHP version: $DEFAULT_PHP_VERSION${NC}"
fi
echo ""
read -p "Continue with installation? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Installation cancelled"
    exit 0
fi

# Update system
echo ""
echo -e "${YELLOW}Updating system packages...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt update && apt upgrade -y
    
    # Add Ondrej PPA for multiple PHP versions
    if [ ${#SELECTED_PHP_VERSIONS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Adding Ondrej PHP PPA...${NC}"
        apt install -y software-properties-common
        add-apt-repository ppa:ondrej/php -y
        apt update
    fi
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER update -y
    
    # Enable EPEL and Remi repositories for multiple PHP versions
    if [ ${#SELECTED_PHP_VERSIONS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing EPEL and Remi repositories...${NC}"
        $PKG_MANAGER install -y epel-release
        $PKG_MANAGER install -y https://rpms.remirepo.net/enterprise/remi-release-${VERSION%%.*}.rpm 2>/dev/null || true
    fi
fi

# Install Nginx
echo ""
echo -e "${YELLOW}Installing Nginx...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y nginx
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER install -y nginx
fi

systemctl enable nginx
systemctl start nginx

# Install MariaDB/MySQL
echo ""
echo -e "${YELLOW}Installing MariaDB...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y mariadb-server mariadb-client
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER install -y mariadb-server mariadb
fi

systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB
echo ""
echo -e "${YELLOW}Securing MariaDB installation...${NC}"
echo -e "${YELLOW}Please answer the security questions:${NC}"
mysql_secure_installation

# PHP Extensions list
PHP_EXTENSIONS=(
    "mysql" "cli" "curl" "gd" "mbstring"
    "xml" "xmlrpc" "zip" "opcache" "intl"
    "bcmath" "soap" "readline" "common"
)

# Install PHP versions
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Installing PHP-FPM Versions       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

PHP_FPM_SERVICES=()
PHP_FPM_SOCKETS=()

# Function to install PHP version
install_php_version() {
    local version=$1
    echo ""
    echo -e "${YELLOW}Installing PHP $version and extensions...${NC}"
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # Build package list
        local packages="php${version}-fpm"
        for ext in "${PHP_EXTENSIONS[@]}"; do
            packages="$packages php${version}-${ext}"
        done
        
        # Add optional extensions
        packages="$packages php${version}-imagick"
        
        # Install packages
        apt install -y $packages 2>/dev/null || {
            echo -e "${YELLOW}Some extensions not available for PHP $version, continuing...${NC}"
            apt install -y php${version}-fpm php${version}-mysql php${version}-cli \
                php${version}-curl php${version}-gd php${version}-mbstring \
                php${version}-xml php${version}-zip php${version}-opcache
        }
        
        PHP_FPM_SERVICE="php${version}-fpm"
        PHP_FPM_SOCK="/run/php/php${version}-fpm.sock"
        
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        # Enable the specific PHP version
        $PKG_MANAGER module reset php -y 2>/dev/null || true
        $PKG_MANAGER module enable php:${version} -y 2>/dev/null || {
            # Try Remi repository
            $PKG_MANAGER install -y php${version//./}-php-fpm php${version//./}-php-mysqlnd \
                php${version//./}-php-cli php${version//./}-php-curl \
                php${version//./}-php-gd php${version//./}-php-mbstring \
                php${version//./}-php-xml php${version//./}-php-zip \
                php${version//./}-php-opcache 2>/dev/null || {
                echo -e "${RED}Failed to install PHP $version${NC}"
                return 1
            }
            PHP_FPM_SERVICE="php${version//./}-php-fpm"
            PHP_FPM_SOCK="/var/run/php-fpm/php${version//./}-fpm.sock"
        }
    fi
    
    # Configure PHP-FPM
    configure_php_fpm "$version" "$PHP_FPM_SERVICE" "$PHP_FPM_SOCK"
    
    # Store service info
    PHP_FPM_SERVICES+=("$PHP_FPM_SERVICE")
    PHP_FPM_SOCKETS+=("$PHP_FPM_SOCK")
    
    # Enable and start service
    systemctl enable $PHP_FPM_SERVICE
    systemctl start $PHP_FPM_SERVICE
    
    echo -e "${GREEN}PHP $version installed successfully${NC}"
}

# Function to configure PHP-FPM
configure_php_fpm() {
    local version=$1
    local service=$2
    local socket=$3
    
    echo -e "${YELLOW}Configuring PHP $version...${NC}"
    
    # Find PHP INI files
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        PHP_INI="/etc/php/${version}/fpm/php.ini"
        PHP_CLI_INI="/etc/php/${version}/cli/php.ini"
        PHP_FPM_POOL="/etc/php/${version}/fpm/pool.d/www.conf"
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        PHP_INI="/etc/opt/remi/php${version//./}/php.ini"
        PHP_CLI_INI="$PHP_INI"
        PHP_FPM_POOL="/etc/opt/remi/php${version//./}/php-fpm.d/www.conf"
        
        # Fallback paths
        [ ! -f "$PHP_INI" ] && PHP_INI="/etc/php.ini"
        [ ! -f "$PHP_FPM_POOL" ] && PHP_FPM_POOL="/etc/php-fpm.d/www.conf"
    fi
    
    # Configure PHP INI
    if [ -f "$PHP_INI" ]; then
        # Backup
        cp "$PHP_INI" "${PHP_INI}.backup.$(date +%Y%m%d)" 2>/dev/null || true
        
        # Optimize settings
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
        sed -i 's/^;date.timezone =.*/date.timezone = UTC/' "$PHP_INI"
        sed -i 's/^;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "$PHP_INI"
    fi
    
    # Configure PHP-FPM pool
    if [ -f "$PHP_FPM_POOL" ]; then
        cp "$PHP_FPM_POOL" "${PHP_FPM_POOL}.backup.$(date +%Y%m%d)" 2>/dev/null || true
        
        # Update socket path if needed
        sed -i "s|listen = .*|listen = $socket|" "$PHP_FPM_POOL"
    fi
}

# Install selected PHP versions
if [ ${#SELECTED_PHP_VERSIONS[@]} -gt 0 ]; then
    for version in "${SELECTED_PHP_VERSIONS[@]}"; do
        install_php_version "$version"
    done
else
    # Install system default PHP
    echo -e "${YELLOW}Installing system default PHP...${NC}"
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt install -y php-fpm php-mysql php-cli php-curl php-gd php-mbstring \
            php-xml php-zip php-opcache php-intl php-bcmath php-soap
        
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
        PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
        PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
        
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        $PKG_MANAGER install -y php php-fpm php-mysqlnd php-cli php-curl \
            php-gd php-mbstring php-xml php-zip php-opcache php-intl php-bcmath php-soap
        
        PHP_VERSION=$(php --version | head -n1 | cut -d" " -f2 | cut -d. -f1,2)
        PHP_FPM_SERVICE="php-fpm"
        PHP_FPM_SOCK="/run/php-fpm/www.sock"
    fi
    
    configure_php_fpm "$PHP_VERSION" "$PHP_FPM_SERVICE" "$PHP_FPM_SOCK"
    
    PHP_FPM_SERVICES+=("$PHP_FPM_SERVICE")
    PHP_FPM_SOCKETS+=("$PHP_FPM_SOCK")
    
    systemctl enable $PHP_FPM_SERVICE
    systemctl start $PHP_FPM_SERVICE
    
    DEFAULT_PHP_VERSION="$PHP_VERSION"
fi

# Configure Nginx for PHP
echo ""
echo -e "${YELLOW}Configuring Nginx for PHP-FPM...${NC}"

mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/snippets
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled

# Create upstream configuration for each PHP version
cat > /etc/nginx/conf.d/php-upstreams.conf <<EOF
# PHP-FPM upstream configurations
EOF

for i in "${!SELECTED_PHP_VERSIONS[@]}"; do
    version="${SELECTED_PHP_VERSIONS[$i]}"
    socket="${PHP_FPM_SOCKETS[$i]}"
    
    cat >> /etc/nginx/conf.d/php-upstreams.conf <<EOF

upstream php${version//./} {
    server unix:${socket};
}
EOF
done

# Create default upstream
if [ -n "$DEFAULT_PHP_VERSION" ]; then
    DEFAULT_SOCK="${PHP_FPM_SOCKETS[0]}"
    cat >> /etc/nginx/conf.d/php-upstreams.conf <<EOF

upstream php-fpm {
    server unix:${DEFAULT_SOCK};
}
EOF
fi

# Create fastcgi-php.conf snippet
cat > /etc/nginx/snippets/fastcgi-php.conf <<'EOF'
fastcgi_split_path_info ^(.+\.php)(/.+)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi.conf;
EOF

# Create snippets for each PHP version
for version in "${SELECTED_PHP_VERSIONS[@]}"; do
    cat > /etc/nginx/snippets/php${version//./}.conf <<EOF
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass php${version//./};
}
EOF
done

# Create default server block
[ -f /etc/nginx/sites-available/default ] && \
    mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d)

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

ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Update main nginx.conf
if ! grep -q "include /etc/nginx/sites-enabled/\*;" /etc/nginx/nginx.conf; then
    if grep -q "include /etc/nginx/conf.d/\*.conf;" /etc/nginx/nginx.conf; then
        sed -i '/include \/etc\/nginx\/conf.d\/\*.conf;/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    fi
fi

# Create web root and test pages
mkdir -p /var/www/html

# Create PHP info page
cat > /var/www/html/info.php <<'EOF'
<?php
phpinfo();
?>
EOF

# Create PHP version selector page
cat > /var/www/html/phpversions.php <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>PHP Versions</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .version-box { background: #f0f0f0; padding: 20px; margin: 10px 0; border-radius: 5px; }
        .current { background: #d4edda; border-left: 5px solid #28a745; }
        h1 { color: #333; }
        .info { color: #666; }
    </style>
</head>
<body>
    <h1>PHP Versions Information</h1>
    <div class="version-box current">
        <h2>Current PHP Version</h2>
        <p><strong>Version:</strong> <?php echo PHP_VERSION; ?></p>
        <p><strong>Server API:</strong> <?php echo php_sapi_name(); ?></p>
        <p><strong>Loaded Config:</strong> <?php echo php_ini_loaded_file(); ?></p>
    </div>
    
    <div class="version-box">
        <h2>Installed Extensions</h2>
        <p><?php echo implode(', ', get_loaded_extensions()); ?></p>
    </div>
    
    <p class="info"><a href="info.php">View Full PHP Info</a></p>
</body>
</html>
EOF

# Set permissions
if id "www-data" &>/dev/null; then
    chown -R www-data:www-data /var/www/html
elif id "nginx" &>/dev/null; then
    chown -R nginx:nginx /var/www/html
fi

chmod 755 /var/www/html
chmod 644 /var/www/html/*.php

# Test Nginx configuration
if nginx -t; then
    systemctl restart nginx
    echo -e "${GREEN}Nginx restarted successfully${NC}"
else
    echo -e "${RED}Nginx configuration test failed!${NC}"
    exit 1
fi

# Install additional tools
echo ""
echo -e "${YELLOW}Installing additional tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y certbot python3-certbot-nginx curl wget git unzip
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER install -y certbot python3-certbot-nginx curl wget git unzip
fi

# Install Docker
echo ""
echo -e "${YELLOW}Installing Docker...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y docker.io
    apt install -y docker-compose 2>/dev/null || apt install -y docker-compose-plugin 2>/dev/null || true
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER install -y docker docker-compose 2>/dev/null || $PKG_MANAGER install -y docker docker-compose-plugin 2>/dev/null || true
fi

systemctl enable docker
systemctl start docker

# Install docker-compose if not available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Installing docker-compose manually...${NC}"
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Install quota tools
echo ""
echo -e "${YELLOW}Installing quota tools...${NC}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt install -y quota quotatool 2>/dev/null || apt install -y quota
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
    $PKG_MANAGER install -y quota
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

# Create PHP version switcher script
cat > /usr/local/bin/switch-php <<'SWITCH_EOF'
#!/bin/bash
# PHP Version Switcher

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: switch-php <version>"
    echo "Example: switch-php 8.2"
    echo ""
    echo "Installed PHP versions:"
    ls /run/php/php*-fpm.sock 2>/dev/null | sed 's|/run/php/php||; s|-fpm.sock||' || \
    ls /var/run/php-fpm/php*-fpm.sock 2>/dev/null | sed 's|/var/run/php-fpm/php||; s|-fpm.sock||'
    exit 1
fi

VERSION=$1
SOCK_PATH=""

# Find socket path
if [ -S "/run/php/php${VERSION}-fpm.sock" ]; then
    SOCK_PATH="/run/php/php${VERSION}-fpm.sock"
elif [ -S "/var/run/php-fpm/php${VERSION//./}-fpm.sock" ]; then
    SOCK_PATH="/var/run/php-fpm/php${VERSION//./}-fpm.sock"
else
    echo "PHP $VERSION not found or not running"
    exit 1
fi

# Update Nginx upstream
cat > /etc/nginx/conf.d/php-fpm-default.conf <<EOF
upstream php-fpm {
    server unix:${SOCK_PATH};
}
EOF

# Test and reload
if nginx -t; then
    systemctl reload nginx
    echo "Switched to PHP $VERSION"
    echo "Socket: $SOCK_PATH"
else
    echo "Nginx configuration error"
    exit 1
fi
SWITCH_EOF

chmod +x /usr/local/bin/switch-php

# Display final status
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   LEMP Stack Installation Complete!    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Service Status:${NC}"
echo -e "  Nginx:     ${GREEN}$(systemctl is-active nginx)${NC}"
echo -e "  MariaDB:   ${GREEN}$(systemctl is-active mariadb)${NC}"
echo -e "  Docker:    ${GREEN}$(systemctl is-active docker)${NC}"
echo ""

if [ ${#SELECTED_PHP_VERSIONS[@]} -gt 0 ]; then
    echo -e "${CYAN}Installed PHP Versions:${NC}"
    for i in "${!SELECTED_PHP_VERSIONS[@]}"; do
        version="${SELECTED_PHP_VERSIONS[$i]}"
        service="${PHP_FPM_SERVICES[$i]}"
        socket="${PHP_FPM_SOCKETS[$i]}"
        status=$(systemctl is-active $service)
        
        if [ "$version" = "$DEFAULT_PHP_VERSION" ]; then
            echo -e "  ${GREEN}★ PHP $version${NC} (default) - $status"
        else
            echo -e "  ${YELLOW}  PHP $version${NC} - $status"
        fi
        echo -e "    Socket: $socket"
        echo -e "    Service: $service"
    done
else
    echo -e "${CYAN}PHP Version:${NC}"
    echo -e "  ${GREEN}PHP $DEFAULT_PHP_VERSION${NC}"
    echo -e "  Socket: ${PHP_FPM_SOCKETS[0]}"
fi

echo ""
echo -e "${CYAN}Configuration Files:${NC}"
echo -e "  Nginx Config:    /etc/nginx/nginx.conf"
echo -e "  PHP Upstreams:   /etc/nginx/conf.d/php-upstreams.conf"
echo -e "  Web Root:        /var/www/html"
echo ""
echo -e "${CYAN}Access URLs:${NC}"
echo -e "  Test Page:       http://$SERVER_IP/"
echo -e "  PHP Info:        http://$SERVER_IP/info.php"
echo -e "  PHP Versions:    http://$SERVER_IP/phpversions.php"
echo ""
echo -e "${CYAN}PHP Version Management:${NC}"
echo -e "  Switch PHP:      ${YELLOW}sudo switch-php 8.2${NC}"
echo -e "  List versions:   ${YELLOW}sudo switch-php${NC}"
echo ""
echo -e "${RED}Security Reminders:${NC}"
echo -e "  1. Remove test files: ${YELLOW}rm /var/www/html/*.php${NC}"
echo -e "  2. Configure firewall"
echo -e "  3. Setup SSL certificates"
echo -e "  4. Secure MySQL root password"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "  Install phpMyAdmin:  ${YELLOW}./setup-phpmyadmin.sh${NC}"
echo -e "  Create virtual host: ${YELLOW}./manage-vhost.sh create domain.com user${NC}"
echo -e "  Install SSL:         ${YELLOW}./manage-ssl.sh install domain.com${NC}"
echo ""

# Save installation info
cat > /root/.lemp-install-info <<EOF
LEMP Stack Installation
=======================
Date: $(date)
OS: $OS $VERSION
Installed PHP Versions: ${SELECTED_PHP_VERSIONS[*]}
Default PHP Version: $DEFAULT_PHP_VERSION
Server IP: $SERVER_IP

PHP-FPM Services:
$(for i in "${!SELECTED_PHP_VERSIONS[@]}"; do
    echo "  ${SELECTED_PHP_VERSIONS[$i]}: ${PHP_FPM_SERVICES[$i]} (${PHP_FPM_SOCKETS[$i]})"
done)

Management Commands:
  Switch PHP: switch-php <version>
  Restart Nginx: systemctl restart nginx
  Restart MariaDB: systemctl restart mariadb
EOF

echo -e "${GREEN}Installation complete! Info saved to /root/.lemp-install-info${NC}"