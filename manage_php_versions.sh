#!/bin/bash
# PHP Version Management Script
# Usage: ./manage-php-versions.sh [install|remove|switch|list|info|set-default]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ACTION=$1
VERSION=$2

usage() {
    echo "Usage: $0 [install|remove|switch|list|info|set-default] [version]"
    echo ""
    echo "Actions:"
    echo "  install <version>       - Install PHP version (e.g., 8.2)"
    echo "  remove <version>        - Remove PHP version"
    echo "  switch <version>        - Switch default PHP version"
    echo "  list                    - List all PHP versions"
    echo "  info <version>          - Show PHP version info"
    echo "  set-default <version>   - Set default PHP version"
    echo "  update-cli <version>    - Set CLI PHP version"
    echo ""
    echo "Examples:"
    echo "  $0 install 8.3"
    echo "  $0 switch 8.2"
    echo "  $0 list"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo -e "${RED}Cannot detect OS${NC}"
    exit 1
fi

# Set package manager
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

# Function to detect installed PHP versions
get_installed_versions() {
    local versions=()
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # Check for PHP-FPM services
        for service in $(systemctl list-units --type=service --all | grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm)'); do
            versions+=("$service")
        done
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        # Check for PHP-FPM services
        for service in $(systemctl list-units --type=service --all | grep -oP 'php[0-9]+(?=-php-fpm)'); do
            version="${service//php/}"
            version="${version:0:1}.${version:1}"
            versions+=("$version")
        done
    fi
    
    # Also check socket files
    for sock in /run/php/php*-fpm.sock /var/run/php-fpm/php*-fpm.sock; do
        if [ -S "$sock" ]; then
            ver=$(basename "$sock" | grep -oP '\d+\.\d+')
            [[ ! " ${versions[@]} " =~ " ${ver} " ]] && versions+=("$ver")
        fi
    done
    
    # Return unique sorted versions
    printf '%s\n' "${versions[@]}" | sort -u
}

# Function to get default PHP version
get_default_version() {
    if [ -f /etc/nginx/conf.d/php-fpm-default.conf ]; then
        grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm.sock)' /etc/nginx/conf.d/php-fpm-default.conf || \
        grep -oP 'php\K[0-9]+(?=-fpm.sock)' /etc/nginx/conf.d/php-fpm-default.conf | sed 's/\(.\)\(.\)/\1.\2/'
    elif [ -f /etc/nginx/conf.d/php-upstreams.conf ]; then
        grep -A2 "upstream php-fpm" /etc/nginx/conf.d/php-upstreams.conf | grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm.sock)' | head -1
    else
        php -v 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1
    fi
}

# Install PHP version
install_php() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo -e "${RED}Version required${NC}"
        usage
    fi
    
    # Check if already installed
    if systemctl list-units --type=service --all | grep -q "php${version}-fpm"; then
        echo -e "${YELLOW}PHP $version is already installed${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}Installing PHP $version...${NC}"
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # Ensure PPA is added
        if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
            echo -e "${YELLOW}Adding Ondrej PHP PPA...${NC}"
            apt install -y software-properties-common
            add-apt-repository ppa:ondrej/php -y
            apt update
        fi
        
        # Install PHP-FPM and common extensions
        apt install -y \
            php${version}-fpm \
            php${version}-mysql \
            php${version}-cli \
            php${version}-curl \
            php${version}-gd \
            php${version}-mbstring \
            php${version}-xml \
            php${version}-zip \
            php${version}-opcache \
            php${version}-intl \
            php${version}-bcmath \
            php${version}-soap \
            php${version}-readline \
            php${version}-common
        
        # Optional extensions
        apt install -y php${version}-imagick 2>/dev/null || true
        
        PHP_FPM_SERVICE="php${version}-fpm"
        PHP_FPM_SOCK="/run/php/php${version}-fpm.sock"
        PHP_INI="/etc/php/${version}/fpm/php.ini"
        
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        # Ensure Remi repo is available
        if [ ! -f /etc/yum.repos.d/remi-php${version//./}.repo ]; then
            echo -e "${YELLOW}Installing Remi repository...${NC}"
            $PKG_MANAGER install -y epel-release
            $PKG_MANAGER install -y https://rpms.remirepo.net/enterprise/remi-release-${VERSION_ID%%.*}.rpm
        fi
        
        # Install PHP
        $PKG_MANAGER install -y \
            php${version//./}-php-fpm \
            php${version//./}-php-mysqlnd \
            php${version//./}-php-cli \
            php${version//./}-php-curl \
            php${version//./}-php-gd \
            php${version//./}-php-mbstring \
            php${version//./}-php-xml \
            php${version//./}-php-zip \
            php${version//./}-php-opcache \
            php${version//./}-php-intl \
            php${version//./}-php-bcmath \
            php${version//./}-php-soap
        
        PHP_FPM_SERVICE="php${version//./}-php-fpm"
        PHP_FPM_SOCK="/var/run/php-fpm/php${version//./}-fpm.sock"
        PHP_INI="/etc/opt/remi/php${version//./}/php.ini"
    fi
    
    # Configure PHP INI
    if [ -f "$PHP_INI" ]; then
        echo -e "${YELLOW}Configuring PHP $version...${NC}"
        cp "$PHP_INI" "${PHP_INI}.backup.$(date +%Y%m%d)"
        
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
        sed -i 's/^;date.timezone =.*/date.timezone = UTC/' "$PHP_INI"
        sed -i 's/^;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "$PHP_INI"
    fi
    
    # Start and enable service
    systemctl enable $PHP_FPM_SERVICE
    systemctl start $PHP_FPM_SERVICE
    
    # Add to Nginx upstreams
    if [ ! -f /etc/nginx/conf.d/php-upstreams.conf ]; then
        echo "# PHP-FPM upstream configurations" > /etc/nginx/conf.d/php-upstreams.conf
    fi
    
    if ! grep -q "upstream php${version//./}" /etc/nginx/conf.d/php-upstreams.conf; then
        cat >> /etc/nginx/conf.d/php-upstreams.conf <<EOF

upstream php${version//./} {
    server unix:${PHP_FPM_SOCK};
}
EOF
    fi
    
    # Create Nginx snippet
    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/php${version//./}.conf <<EOF
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass php${version//./};
}
EOF
    
    # Reload Nginx
    nginx -t && systemctl reload nginx
    
    echo -e "${GREEN}PHP $version installed successfully${NC}"
    echo -e "${YELLOW}Service: $PHP_FPM_SERVICE${NC}"
    echo -e "${YELLOW}Socket: $PHP_FPM_SOCK${NC}"
    echo ""
    echo -e "${YELLOW}To use this version:${NC}"
    echo -e "  Set as default: ${CYAN}sudo $0 set-default $version${NC}"
    echo -e "  Or in vhost: ${CYAN}include snippets/php${version//./}.conf;${NC}"
}

# Remove PHP version
remove_php() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo -e "${RED}Version required${NC}"
        usage
    fi
    
    # Check if it's the default version
    DEFAULT_VER=$(get_default_version)
    if [ "$version" = "$DEFAULT_VER" ]; then
        echo -e "${RED}Cannot remove default PHP version${NC}"
        echo -e "${YELLOW}Set another version as default first${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will remove PHP $version${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    echo -e "${YELLOW}Removing PHP $version...${NC}"
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        PHP_FPM_SERVICE="php${version}-fpm"
        
        systemctl stop $PHP_FPM_SERVICE
        systemctl disable $PHP_FPM_SERVICE
        
        apt remove -y php${version}-* 2>/dev/null || true
        apt autoremove -y
        
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        PHP_FPM_SERVICE="php${version//./}-php-fpm"
        
        systemctl stop $PHP_FPM_SERVICE
        systemctl disable $PHP_FPM_SERVICE
        
        $PKG_MANAGER remove -y php${version//./}-* 2>/dev/null || true
    fi
    
    # Remove Nginx configuration
    rm -f /etc/nginx/snippets/php${version//./}.conf
    sed -i "/upstream php${version//./}/,/^}/d" /etc/nginx/conf.d/php-upstreams.conf 2>/dev/null || true
    
    nginx -t && systemctl reload nginx
    
    echo -e "${GREEN}PHP $version removed${NC}"
}

# Switch default PHP version
switch_php() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo -e "${RED}Version required${NC}"
        usage
    fi
    
    # Check if version is installed
    if ! systemctl list-units --type=service --all | grep -q "php.*${version}.*fpm"; then
        echo -e "${RED}PHP $version is not installed${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Switching to PHP $version...${NC}"
    
    # Find socket path
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        SOCK_PATH="/run/php/php${version}-fpm.sock"
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ] || [ "$OS" = "almalinux" ]; then
        SOCK_PATH="/var/run/php-fpm/php${version//./}-fpm.sock"
    fi
    
    if [ ! -S "$SOCK_PATH" ]; then
        echo -e "${RED}Socket not found: $SOCK_PATH${NC}"
        exit 1
    fi
    
    # Update Nginx default upstream
    cat > /etc/nginx/conf.d/php-fpm-default.conf <<EOF
# Default PHP-FPM upstream
upstream php-fpm {
    server unix:${SOCK_PATH};
}
EOF
    
    # Test and reload
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}Switched to PHP $version${NC}"
        echo -e "${YELLOW}Socket: $SOCK_PATH${NC}"
    else
        echo -e "${RED}Nginx configuration error${NC}"
        rm -f /etc/nginx/conf.d/php-fpm-default.conf
        exit 1
    fi
}

# List PHP versions
list_php() {
    echo -e "${GREEN}=== Installed PHP Versions ===${NC}"
    echo ""
    
    DEFAULT_VER=$(get_default_version)
    
    mapfile -t VERSIONS < <(get_installed_versions)
    
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No PHP versions found${NC}"
        exit 0
    fi
    
    for version in "${VERSIONS[@]}"; do
        # Get service name
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            SERVICE="php${version}-fpm"
            SOCK="/run/php/php${version}-fpm.sock"
        else
            SERVICE="php${version//./}-php-fpm"
            SOCK="/var/run/php-fpm/php${version//./}-fpm.sock"
        fi
        
        # Check status
        STATUS=$(systemctl is-active $SERVICE 2>/dev/null || echo "inactive")
        
        # Check if default
        if [ "$version" = "$DEFAULT_VER" ]; then
            echo -e "${GREEN}★ PHP $version${NC} (default) - $STATUS"
        else
            echo -e "${YELLOW}  PHP $version${NC} - $STATUS"
        fi
        
        echo -e "    Service: $SERVICE"
        echo -e "    Socket:  $SOCK"
        
        # Show binary path
        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            BIN="/usr/bin/php${version}"
        else
            BIN="/opt/remi/php${version//./}/root/usr/bin/php"
        fi
        
        if [ -f "$BIN" ]; then
            echo -e "    Binary:  $BIN"
        fi
        
        echo ""
    done
    
    echo -e "${CYAN}Management Commands:${NC}"
    echo -e "  Switch version:  ${YELLOW}sudo $0 switch <version>${NC}"
    echo -e "  Install version: ${YELLOW}sudo $0 install <version>${NC}"
    echo -e "  Remove version:  ${YELLOW}sudo $0 remove <version>${NC}"
}

# Show PHP version info
php_info() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo -e "${RED}Version required${NC}"
        usage
    fi
    
    echo -e "${GREEN}=== PHP $version Information ===${NC}"
    echo ""
    
    # Find PHP binary
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        PHP_BIN="/usr/bin/php${version}"
        PHP_FPM_SERVICE="php${version}-fpm"
        PHP_INI="/etc/php/${version}/fpm/php.ini"
        PHP_CLI_INI="/etc/php/${version}/cli/php.ini"
    else
        PHP_BIN="/opt/remi/php${version//./}/root/usr/bin/php"
        PHP_FPM_SERVICE="php${version//./}-php-fpm"
        PHP_INI="/etc/opt/remi/php${version//./}/php.ini"
        PHP_CLI_INI="$PHP_INI"
    fi
    
    if [ ! -f "$PHP_BIN" ]; then
        echo -e "${RED}PHP $version not found${NC}"
        exit 1
    fi
    
    # Version info
    echo -e "${YELLOW}Version:${NC}"
    $PHP_BIN -v
    
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo -e "  INI File (FPM): $PHP_INI"
    echo -e "  INI File (CLI): $PHP_CLI_INI"
    echo -e "  Service:        $PHP_FPM_SERVICE"
    echo -e "  Status:         $(systemctl is-active $PHP_FPM_SERVICE)"
    
    echo ""
    echo -e "${YELLOW}Key Settings:${NC}"
    $PHP_BIN -i | grep -E "memory_limit|upload_max_filesize|post_max_size|max_execution_time"
    
    echo ""
    echo -e "${YELLOW}Loaded Extensions:${NC}"
    $PHP_BIN -m | column
}

# Set default PHP version for CLI
update_cli() {
    local version=$1
    
    if [ -z "$version" ]; then
        echo -e "${RED}Version required${NC}"
        usage
    fi
    
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        if [ -f "/usr/bin/php${version}" ]; then
            update-alternatives --set php "/usr/bin/php${version}"
            echo -e "${GREEN}CLI PHP set to $version${NC}"
            php -v
        else
            echo -e "${RED}PHP $version not found${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}On RHEL-based systems, use scl:${NC}"
        echo -e "  scl enable php${version//./} bash"
    fi
}

# Main logic
case $ACTION in
    install)
        install_php $VERSION
        ;;
    remove)
        remove_php $VERSION
        ;;
    switch|set-default)
        switch_php $VERSION
        ;;
    list)
        list_php
        ;;
    info)
        php_info $VERSION
        ;;
    update-cli)
        update_cli $VERSION
        ;;
    *)
        usage
        ;;
esac