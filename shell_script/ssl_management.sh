#!/bin/bash
# Let's Encrypt SSL Certificate Management
# Usage: ./manage-ssl.sh [install|renew|remove|list|info] [domain]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
DOMAIN=$2

usage() {
    echo "Usage: $0 [install|renew|remove|list|info|auto-renew] [domain]"
    echo ""
    echo "Actions:"
    echo "  install <domain>      - Install SSL certificate"
    echo "  renew <domain>        - Renew SSL certificate"
    echo "  remove <domain>       - Remove SSL certificate"
    echo "  list                  - List all certificates"
    echo "  info <domain>         - Show certificate info"
    echo "  auto-renew            - Setup automatic renewal"
    echo ""
    echo "Examples:"
    echo "  $0 install example.com"
    echo "  $0 renew example.com"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Check if certbot is installed
check_certbot() {
    if ! command -v certbot &> /dev/null; then
        echo -e "${RED}Certbot is not installed${NC}"
        echo -e "${YELLOW}Installing Certbot...${NC}"
        
        if command -v apt &> /dev/null; then
            apt install -y certbot python3-certbot-nginx
        elif command -v yum &> /dev/null; then
            yum install -y certbot python3-certbot-nginx || dnf install -y certbot python3-certbot-nginx
        else
            echo -e "${RED}Cannot install Certbot automatically${NC}"
            exit 1
        fi
    fi
}

# Install SSL certificate
install_ssl() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    # Check if virtual host exists
    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Virtual host for $domain does not exist${NC}"
        echo -e "${YELLOW}Create it first using: ./manage-vhost.sh create $domain <username>${NC}"
        exit 1
    fi
    
    # Check if SSL already installed
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${YELLOW}SSL certificate already exists for $domain${NC}"
        read -p "Reinstall? (y/n): " REINSTALL
        if [ "$REINSTALL" != "y" ] && [ "$REINSTALL" != "Y" ]; then
            exit 0
        fi
    fi
    
    echo -e "${GREEN}Installing SSL certificate for: $domain${NC}"
    
    # Get email
    read -p "Enter email address for SSL notifications: " EMAIL
    
    if [ -z "$EMAIL" ]; then
        echo -e "${RED}Email is required${NC}"
        exit 1
    fi
    
    # Ask about www subdomain
    read -p "Include www.$domain? (y/n): " INCLUDE_WWW
    
    if [ "$INCLUDE_WWW" = "y" ] || [ "$INCLUDE_WWW" = "Y" ]; then
        DOMAINS="-d $domain -d www.$domain"
    else
        DOMAINS="-d $domain"
    fi
    
    # Test Nginx configuration first
    if ! nginx -t 2>/dev/null; then
        echo -e "${RED}Nginx configuration has errors. Fix them first.${NC}"
        exit 1
    fi
    
    # Install certificate
    echo -e "${YELLOW}Obtaining SSL certificate...${NC}"
    certbot --nginx $DOMAINS --email $EMAIL --agree-tos --no-eff-email --redirect
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSL certificate installed successfully${NC}"
        echo ""
        show_ssl_info $domain
        
        # Setup auto-renewal if not already done
        setup_auto_renew
    else
        echo -e "${RED}Failed to install SSL certificate${NC}"
        exit 1
    fi
}

# Renew SSL certificate
renew_ssl() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        # Renew all certificates
        echo -e "${YELLOW}Renewing all SSL certificates...${NC}"
        certbot renew --quiet
        
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            echo -e "${GREEN}All certificates renewed successfully${NC}"
        else
            echo -e "${RED}Failed to renew some certificates${NC}"
            certbot renew
            exit 1
        fi
    else
        # Renew specific certificate
        if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
            echo -e "${RED}No SSL certificate found for $domain${NC}"
            exit 1
        fi
        
        echo -e "${YELLOW}Renewing SSL certificate for $domain...${NC}"
        certbot renew --cert-name $domain
        
        if [ $? -eq 0 ]; then
            systemctl reload nginx
            echo -e "${GREEN}Certificate renewed successfully${NC}"
        else
            echo -e "${RED}Failed to renew certificate${NC}"
            exit 1
        fi
    fi
}

# Remove SSL certificate
remove_ssl() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${RED}No SSL certificate found for $domain${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will remove the SSL certificate for $domain${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Delete certificate
    certbot delete --cert-name $domain
    
    # Remove SSL configuration from Nginx
    if [ -f "/etc/nginx/sites-available/$domain" ]; then
        # Backup current config
        cp "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-available/${domain}.ssl-backup"
        
        # Remove SSL directives (basic removal, might need manual adjustment)
        sed -i '/listen 443/d' "/etc/nginx/sites-available/$domain"
        sed -i '/ssl_certificate/d' "/etc/nginx/sites-available/$domain"
        sed -i '/ssl_certificate_key/d' "/etc/nginx/sites-available/$domain"
        
        # Test and reload
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            echo -e "${GREEN}SSL certificate removed${NC}"
            echo -e "${YELLOW}Config backup: /etc/nginx/sites-available/${domain}.ssl-backup${NC}"
        else
            # Restore backup if test fails
            mv "/etc/nginx/sites-available/${domain}.ssl-backup" "/etc/nginx/sites-available/$domain"
            echo -e "${RED}Failed to update Nginx config${NC}"
            exit 1
        fi
    fi
}

# List all SSL certificates
list_ssl() {
    echo -e "${GREEN}=== SSL Certificates ===${NC}"
    echo ""
    
    if [ ! -d "/etc/letsencrypt/live" ] || [ -z "$(ls -A /etc/letsencrypt/live 2>/dev/null)" ]; then
        echo -e "${YELLOW}No SSL certificates found${NC}"
        exit 0
    fi
    
    certbot certificates
}

# Show SSL certificate info
show_ssl_info() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    if [ ! -d "/etc/letsencrypt/live/$domain" ]; then
        echo -e "${RED}No SSL certificate found for $domain${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== SSL Certificate Information: $domain ===${NC}"
    echo ""
    
    # Get certificate info
    CERT_FILE="/etc/letsencrypt/live/$domain/cert.pem"
    
    if [ -f "$CERT_FILE" ]; then
        # Expiry date
        EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
        
        echo -e "${YELLOW}Certificate File:${NC} $CERT_FILE"
        echo -e "${YELLOW}Expires:${NC} $EXPIRY"
        echo -e "${YELLOW}Days Remaining:${NC} $DAYS_LEFT"
        
        if [ $DAYS_LEFT -lt 30 ]; then
            echo -e "${RED}WARNING: Certificate expires in less than 30 days!${NC}"
        elif [ $DAYS_LEFT -lt 60 ]; then
            echo -e "${YELLOW}Notice: Certificate expires in less than 60 days${NC}"
        fi
        
        # Domains covered
        echo ""
        echo -e "${YELLOW}Domains:${NC}"
        openssl x509 -noout -text -in "$CERT_FILE" | grep "DNS:" | sed 's/DNS://g' | tr ',' '\n' | sed 's/^[ \t]*/  /'
        
        # Issuer
        echo ""
        echo -e "${YELLOW}Issuer:${NC}"
        openssl x509 -noout -issuer -in "$CERT_FILE" | sed 's/issuer=//'
    fi
}

# Setup automatic renewal
setup_auto_renew() {
    echo -e "${YELLOW}Setting up automatic SSL renewal...${NC}"
    
    # Create renewal script
    cat > /usr/local/bin/certbot-renew-all <<'RENEW_SCRIPT'
#!/bin/bash
# Automatic SSL Certificate Renewal Script

LOG_FILE="/var/log/certbot-renew.log"

echo "=== SSL Certificate Renewal ===" >> "$LOG_FILE"
echo "Date: $(date)" >> "$LOG_FILE"

# Renew certificates
certbot renew --quiet >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "Renewal successful" >> "$LOG_FILE"
    systemctl reload nginx >> "$LOG_FILE" 2>&1
else
    echo "Renewal failed" >> "$LOG_FILE"
fi

echo "" >> "$LOG_FILE"
RENEW_SCRIPT
    
    chmod +x /usr/local/bin/certbot-renew-all
    
    # Check if cron job exists
    if ! crontab -l 2>/dev/null | grep -q "certbot-renew-all"; then
        # Add cron job (runs daily at 2:30 AM)
        (crontab -l 2>/dev/null; echo "30 2 * * * /usr/local/bin/certbot-renew-all") | crontab -
        echo -e "${GREEN}Automatic renewal configured${NC}"
        echo -e "${YELLOW}Renewal will run daily at 2:30 AM${NC}"
        echo -e "${YELLOW}Logs: /var/log/certbot-renew.log${NC}"
    else
        echo -e "${YELLOW}Automatic renewal already configured${NC}"
    fi
    
    # Create systemd timer as alternative (if systemd is available)
    if command -v systemctl &> /dev/null; then
        cat > /etc/systemd/system/certbot-renew.service <<'SERVICE'
[Unit]
Description=Certbot SSL Certificate Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/certbot-renew-all
SERVICE
        
        cat > /etc/systemd/system/certbot-renew.timer <<'TIMER'
[Unit]
Description=Certbot SSL Certificate Renewal Timer
After=network.target

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
TIMER
        
        systemctl daemon-reload
        systemctl enable certbot-renew.timer
        systemctl start certbot-renew.timer
        
        echo -e "${GREEN}Systemd timer also configured${NC}"
    fi
}

# Main logic
check_certbot

case $ACTION in
    install)
        install_ssl $DOMAIN
        ;;
    renew)
        renew_ssl $DOMAIN
        ;;
    remove)
        remove_ssl $DOMAIN
        ;;
    list)
        list_ssl
        ;;
    info)
        show_ssl_info $DOMAIN
        ;;
    auto-renew)
        setup_auto_renew
        ;;
    *)
        usage
        ;;
esac