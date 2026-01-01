#!/bin/bash
# phpMyAdmin Docker Setup Script
# Usage: sudo ./setup-phpmyadmin.sh [port] [mysql_root_password]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PORT=${1:-8080}
MYSQL_ROOT_PASSWORD=${2:-""}

echo -e "${GREEN}=== phpMyAdmin Docker Setup ===${NC}"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please run setup-lemp.sh first.${NC}"
    exit 1
fi

# Get MySQL root password if not provided
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo -e "${YELLOW}Enter MySQL root password:${NC}"
    read -s MYSQL_ROOT_PASSWORD
fi

# Create directory for phpMyAdmin config
mkdir -p /opt/phpmyadmin
cd /opt/phpmyadmin

# Create docker-compose.yml
cat > docker-compose.yml <<EOF
version: '3.8'

services:
  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: phpmyadmin
    restart: always
    ports:
      - "${PORT}:80"
    environment:
      - PMA_HOST=host.docker.internal
      - PMA_PORT=3306
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - PMA_ABSOLUTE_URI=http://localhost:${PORT}/
      - UPLOAD_LIMIT=256M
      - MEMORY_LIMIT=512M
      - MAX_EXECUTION_TIME=300
    volumes:
      - phpmyadmin-data:/sessions
    extra_hosts:
      - "host.docker.internal:host-gateway"

volumes:
  phpmyadmin-data:
    driver: local
EOF

# Configure MySQL to allow Docker connections
echo -e "${YELLOW}Configuring MySQL for Docker access...${NC}"

# Find MySQL config file
if [ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]; then
    MYSQL_CNF="/etc/mysql/mariadb.conf.d/50-server.cnf"
elif [ -f /etc/my.cnf.d/server.cnf ]; then
    MYSQL_CNF="/etc/my.cnf.d/server.cnf"
elif [ -f /etc/my.cnf ]; then
    MYSQL_CNF="/etc/my.cnf"
else
    MYSQL_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
fi

# Backup config
cp "$MYSQL_CNF" "${MYSQL_CNF}.backup"

# Update bind-address
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$MYSQL_CNF" || \
    echo "bind-address = 0.0.0.0" >> "$MYSQL_CNF"

# Restart MySQL
systemctl restart mariadb

# Grant access to root from Docker network
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
GRANT ALL PRIVILEGES ON *.* TO 'root'@'172.%.%.%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Start phpMyAdmin
echo -e "${YELLOW}Starting phpMyAdmin container...${NC}"
docker-compose up -d

# Wait for container to start
sleep 5

# Check status
if docker ps | grep -q phpmyadmin; then
    echo -e "${GREEN}=== phpMyAdmin Setup Complete ===${NC}"
    echo -e "${GREEN}Status:${NC} Running"
    echo -e "${GREEN}Access URL:${NC} http://your-server-ip:${PORT}"
    echo -e "${YELLOW}Username:${NC} root"
    echo -e "${YELLOW}Password:${NC} [Your MySQL root password]"
    echo ""
    echo -e "${YELLOW}Management Commands:${NC}"
    echo "  Start:   cd /opt/phpmyadmin && docker-compose start"
    echo "  Stop:    cd /opt/phpmyadmin && docker-compose stop"
    echo "  Restart: cd /opt/phpmyadmin && docker-compose restart"
    echo "  Logs:    cd /opt/phpmyadmin && docker-compose logs -f"
    echo "  Remove:  cd /opt/phpmyadmin && docker-compose down -v"
else
    echo -e "${RED}Failed to start phpMyAdmin container${NC}"
    docker-compose logs
    exit 1
fi

# Create Nginx reverse proxy configuration
echo -e "${YELLOW}Would you like to create an Nginx reverse proxy for phpMyAdmin? (y/n)${NC}"
read -r CREATE_PROXY

if [ "$CREATE_PROXY" = "y" ] || [ "$CREATE_PROXY" = "Y" ]; then
    echo -e "${YELLOW}Enter domain name for phpMyAdmin (e.g., phpmyadmin.example.com):${NC}"
    read -r DOMAIN
    
    cat > /etc/nginx/sites-available/${DOMAIN} <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    
    location / {
        proxy_pass http://localhost:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Increase timeouts for large operations
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
}
EOF
    
    ln -sf /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx
    
    echo -e "${GREEN}Nginx reverse proxy created for ${DOMAIN}${NC}"
    echo -e "${YELLOW}Access phpMyAdmin at: http://${DOMAIN}${NC}"
fi