#!/bin/bash
# Virtual Host Management Script
# Usage: ./manage-vhost.sh [create|delete|list|enable|disable] [domain] [username]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
DOMAIN=$2
USERNAME=$3

usage() {
    echo "Usage: $0 [create|delete|list|enable|disable|info] [domain] [username]"
    echo ""
    echo "Actions:"
    echo "  create <domain> <username>  - Create new virtual host"
    echo "  delete <domain>            - Delete virtual host"
    echo "  list                       - List all virtual hosts"
    echo "  enable <domain>            - Enable virtual host"
    echo "  disable <domain>           - Disable virtual host"
    echo "  info <domain>              - Show virtual host info"
    echo ""
    echo "Examples:"
    echo "  $0 create example.com john"
    echo "  $0 delete example.com"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Get PHP-FPM version and socket
get_php_info() {
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.1")
    
    if [ -S "/run/php/php${PHP_VERSION}-fpm.sock" ]; then
        PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
    elif [ -S "/run/php-fpm/www.sock" ]; then
        PHP_FPM_SOCK="/run/php-fpm/www.sock"
    else
        PHP_FPM_SOCK="/run/php/php-fpm.sock"
    fi
}

# Create virtual host
create_vhost() {
    local domain=$1
    local username=$2
    
    if [ -z "$domain" ] || [ -z "$username" ]; then
        echo -e "${RED}Missing parameters${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    if [ -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Virtual host for $domain already exists${NC}"
        exit 1
    fi
    
    get_php_info
    
    echo -e "${GREEN}Creating virtual host: $domain${NC}"
    
    # Determine document root
    echo -e "${YELLOW}Select document root location:${NC}"
    echo "1. /home/$username/www/$domain"
    echo "2. /home/$username/public_html"
    echo "3. Custom path"
    read -p "Choice [1-3]: " ROOT_CHOICE
    
    case $ROOT_CHOICE in
        1)
            DOC_ROOT="/home/$username/www/$domain"
            ;;
        2)
            DOC_ROOT="/home/$username/public_html"
            ;;
        3)
            read -p "Enter custom path: " DOC_ROOT
            ;;
        *)
            DOC_ROOT="/home/$username/www/$domain"
            ;;
    esac
    
    # Create directory structure
    mkdir -p "$DOC_ROOT"
    mkdir -p "$DOC_ROOT/public"
    mkdir -p "/home/$username/logs/$domain"
    
    # Set permissions
    chown -R $username:$username "$DOC_ROOT"
    chown -R $username:$username "/home/$username/logs/$domain"
    
    # Create index.php
    cat > "$DOC_ROOT/public/index.php" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Website is Working!</h1>
    <div class="info">
        <p><strong>Document Root:</strong> <?php echo $_SERVER['DOCUMENT_ROOT']; ?></p>
        <p><strong>Server:</strong> <?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
        <p><strong>PHP Version:</strong> <?php echo PHP_VERSION; ?></p>
    </div>
</body>
</html>
EOF
    
    chown $username:$username "$DOC_ROOT/public/index.php"
    
    # Ask about additional features
    echo ""
    echo -e "${YELLOW}Enable additional features? (y/n)${NC}"
    read -p "1. Enable www redirect? (y/n): " ENABLE_WWW
    read -p "2. Enable gzip compression? (y/n): " ENABLE_GZIP
    read -p "3. Enable cache headers? (y/n): " ENABLE_CACHE
    
    # Create Nginx virtual host configuration
    cat > "/etc/nginx/sites-available/$domain" <<EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain www.$domain;
    
    root $DOC_ROOT/public;
    index index.php index.html index.htm;
    
    # Logs
    access_log /home/$username/logs/$domain/access.log;
    error_log /home/$username/logs/$domain/error.log;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
EOF

    # Add www redirect if enabled
    if [ "$ENABLE_WWW" = "y" ] || [ "$ENABLE_WWW" = "Y" ]; then
        cat >> "/etc/nginx/sites-available/$domain" <<EOF
    
    # Redirect www to non-www
    if (\$host = www.$domain) {
        return 301 http://$domain\$request_uri;
    }
EOF
    fi

    # Add gzip if enabled
    if [ "$ENABLE_GZIP" = "y" ] || [ "$ENABLE_GZIP" = "Y" ]; then
        cat >> "/etc/nginx/sites-available/$domain" <<'EOF'
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json;
EOF
    fi

    # Continue with main config
    cat >> "/etc/nginx/sites-available/$domain" <<EOF
    
    # Main location
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    # PHP handler
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_FPM_SOCK;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
EOF

    # Add cache headers if enabled
    if [ "$ENABLE_CACHE" = "y" ] || [ "$ENABLE_CACHE" = "Y" ]; then
        cat >> "/etc/nginx/sites-available/$domain" <<'EOF'
    
    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 365d;
        add_header Cache-Control "public, immutable";
    }
EOF
    fi

    # Close server block
    cat >> "/etc/nginx/sites-available/$domain" <<'EOF'
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }
    
    # Deny access to sensitive files
    location ~* \.(sql|log|conf|ini)$ {
        deny all;
    }
}
EOF
    
    # Enable the site
    ln -s "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/"
    
    # Test Nginx configuration
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        echo -e "${GREEN}Virtual host created successfully${NC}"
        echo ""
        echo -e "${YELLOW}Domain:${NC} $domain"
        echo -e "${YELLOW}Document Root:${NC} $DOC_ROOT/public"
        echo -e "${YELLOW}User:${NC} $username"
        echo -e "${YELLOW}Logs:${NC} /home/$username/logs/$domain"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Point DNS A record to server IP"
        echo "2. Install SSL: ./manage-ssl.sh install $domain"
        echo "3. Upload your website files to: $DOC_ROOT/public"
    else
        echo -e "${RED}Nginx configuration test failed${NC}"
        rm -f "/etc/nginx/sites-enabled/$domain"
        exit 1
    fi
}

# Delete virtual host
delete_vhost() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Virtual host for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will delete the virtual host configuration${NC}"
    echo -e "${YELLOW}Files in document root will NOT be deleted${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Disable site
    rm -f "/etc/nginx/sites-enabled/$domain"
    
    # Backup and delete config
    BACKUP_DIR="/root/vhost_backups"
    mkdir -p "$BACKUP_DIR"
    cp "/etc/nginx/sites-available/$domain" "$BACKUP_DIR/${domain}_$(date +%Y%m%d_%H%M%S).conf"
    rm -f "/etc/nginx/sites-available/$domain"
    
    # Remove SSL certificate if exists
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        certbot delete --cert-name $domain --non-interactive 2>/dev/null || true
    fi
    
    # Reload Nginx
    nginx -t && systemctl reload nginx
    
    echo -e "${GREEN}Virtual host deleted${NC}"
    echo -e "${YELLOW}Backup saved to: $BACKUP_DIR${NC}"
}

# List virtual hosts
list_vhosts() {
    echo -e "${GREEN}=== Virtual Hosts ===${NC}"
    echo ""
    printf "%-30s %-10s %-20s\n" "DOMAIN" "STATUS" "CONFIG FILE"
    echo "------------------------------------------------------------------------"
    
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ]; then
            domain=$(basename "$conf")
            
            if [ -L "/etc/nginx/sites-enabled/$domain" ]; then
                status="${GREEN}enabled${NC}"
            else
                status="${RED}disabled${NC}"
            fi
            
            printf "%-30s %-20s %-20s\n" "$domain" "$(echo -e $status)" "$conf"
        fi
    done
}

# Enable virtual host
enable_vhost() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Virtual host for $domain does not exist${NC}"
        exit 1
    fi
    
    ln -sf "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/"
    
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        echo -e "${GREEN}Virtual host $domain enabled${NC}"
    else
        echo -e "${RED}Nginx configuration test failed${NC}"
        rm -f "/etc/nginx/sites-enabled/$domain"
        exit 1
    fi
}

# Disable virtual host
disable_vhost() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    rm -f "/etc/nginx/sites-enabled/$domain"
    systemctl reload nginx
    
    echo -e "${GREEN}Virtual host $domain disabled${NC}"
}

# Show virtual host info
vhost_info() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Virtual host for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Virtual Host Information: $domain ===${NC}"
    echo ""
    
    # Status
    if [ -L "/etc/nginx/sites-enabled/$domain" ]; then
        echo -e "${YELLOW}Status:${NC} ${GREEN}Enabled${NC}"
    else
        echo -e "${YELLOW}Status:${NC} ${RED}Disabled${NC}"
    fi
    
    # Extract info from config
    DOC_ROOT=$(grep "root " "/etc/nginx/sites-available/$domain" | head -1 | awk '{print $2}' | sed 's/;//')
    ACCESS_LOG=$(grep "access_log" "/etc/nginx/sites-available/$domain" | head -1 | awk '{print $2}' | sed 's/;//')
    
    echo -e "${YELLOW}Document Root:${NC} $DOC_ROOT"
    echo -e "${YELLOW}Access Log:${NC} $ACCESS_LOG"
    
    # SSL status
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${YELLOW}SSL:${NC} ${GREEN}Installed${NC}"
        echo -e "${YELLOW}Certificate:${NC} /etc/letsencrypt/live/$domain/fullchain.pem"
    else
        echo -e "${YELLOW}SSL:${NC} ${RED}Not Installed${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Configuration file:${NC}"
    cat "/etc/nginx/sites-available/$domain"
}

# Main logic
case $ACTION in
    create)
        create_vhost $DOMAIN $USERNAME
        ;;
    delete)
        delete_vhost $DOMAIN
        ;;
    list)
        list_vhosts
        ;;
    enable)
        enable_vhost $DOMAIN
        ;;
    disable)
        disable_vhost $DOMAIN
        ;;
    info)
        vhost_info $DOMAIN
        ;;
    *)
        usage
        ;;
esac