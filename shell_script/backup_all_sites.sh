#!/bin/bash
# Backup All Sites and Databases Script
# This script backs up all Nginx virtual hosts, their web directories, and all MySQL databases.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="/root/complete_backups"
BACKUP_DIR="${BACKUP_ROOT}/backup_${TIMESTAMP}"
SITES_BACKUP_DIR="${BACKUP_DIR}/sites"
DB_BACKUP_DIR="${BACKUP_DIR}/databases"
NGINX_BACKUP_DIR="${BACKUP_DIR}/nginx_configs"

mkdir -p "$SITES_BACKUP_DIR"
mkdir -p "$DB_BACKUP_DIR"
mkdir -p "$NGINX_BACKUP_DIR"

echo -e "${CYAN}=== Full Server Backup ===${NC}"
echo -e "${YELLOW}Starting backup process...${NC}"
echo -e "Backup location: ${BACKUP_DIR}"

# 1. Backup Nginx Configurations
echo -e "\n${YELLOW}[1/3] Backing up Nginx configurations...${NC}"
if [ -d "/etc/nginx/sites-available" ]; then
    cp -r /etc/nginx/sites-available/ "$NGINX_BACKUP_DIR/" 2>/dev/null || true
fi
if [ -d "/etc/nginx/sites-enabled" ]; then
    cp -r /etc/nginx/sites-enabled/ "$NGINX_BACKUP_DIR/" 2>/dev/null || true
fi
echo -e "${GREEN}Nginx configs backed up.${NC}"

# 2. Backup Websites (Virtual Hosts)
echo -e "\n${YELLOW}[2/3] Backing up website files...${NC}"
if ls /etc/nginx/sites-available/* 1> /dev/null 2>&1; then
    for conf in /etc/nginx/sites-available/*; do
        if [ -f "$conf" ]; then
            domain=$(basename "$conf")
            echo -e "  Processing domain: ${CYAN}$domain${NC}"
            
            # Extract document root
            NGINX_ROOT=$(grep "root " "$conf" | head -1 | awk '{print $2}' | sed 's/;//')
            
            # Determine directory to backup
            SITE_DIR="$NGINX_ROOT"
            # If it ends with /public, back up the parent directory to include logs/etc if they reside there
            if [[ "$NGINX_ROOT" == */public ]]; then
                SITE_DIR="${NGINX_ROOT%/public}"
            fi
            
            if [ -n "$SITE_DIR" ] && [ -d "$SITE_DIR" ]; then
                ARCHIVE_NAME="${SITES_BACKUP_DIR}/${domain}.tar.gz"
                echo "    Creating archive: $ARCHIVE_NAME"
                # using -C to change to parent directory so the tarball extracts to the folder name
                DIR_NAME=$(basename "$SITE_DIR")
                PARENT_DIR=$(dirname "$SITE_DIR")
                tar -czf "$ARCHIVE_NAME" -C "$PARENT_DIR" "$DIR_NAME" 2>/dev/null || echo -e "${RED}    Warning: Some files could not be read.${NC}"
            else
                echo -e "    ${YELLOW}Warning: Directory ($SITE_DIR) not found. Skipping file backup for $domain.${NC}"
            fi
        fi
    done
else
    echo -e "${YELLOW}No virtual hosts found in /etc/nginx/sites-available/${NC}"
fi

# 3. Backup Databases
echo -e "\n${YELLOW}[3/3] Backing up MySQL databases...${NC}"

if command -v mysql >/dev/null 2>&1; then
    # Get MySQL password logic matching mysql_db_management.sh
    if [ -f /root/.my.cnf ]; then
        MYSQL_CMD="mysql"
        MYSQLDUMP_CMD="mysqldump"
    else
        echo -e "${YELLOW}Enter MySQL root password for database backups:${NC}"
        read -s MYSQL_ROOT_PASSWORD
        MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
        MYSQLDUMP_CMD="mysqldump -u root -p${MYSQL_ROOT_PASSWORD}"
    fi

    # Check if we can connect
    if $MYSQL_CMD -e "SELECT 1" &> /dev/null; then
        DATABASES=$($MYSQL_CMD -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys|phpmyadmin)$" || true)

        if [ -n "$DATABASES" ]; then
            for db in $DATABASES; do
                echo -e "  Backing up database: ${CYAN}$db${NC}"
                $MYSQLDUMP_CMD --single-transaction --routines --triggers --events "$db" > "${DB_BACKUP_DIR}/${db}.sql" 2>/dev/null
                if [ $? -eq 0 ]; then
                    gzip "${DB_BACKUP_DIR}/${db}.sql"
                else
                    echo -e "    ${RED}Failed to backup database: $db${NC}"
                fi
            done
        else
            echo -e "${YELLOW}No user databases found to backup.${NC}"
        fi
    else
        echo -e "${RED}Failed to connect to MySQL database. Skipping database backup.${NC}"
    fi
else
    echo -e "${YELLOW}MySQL not installed. Skipping database backup.${NC}"
fi

echo -e "\n${YELLOW}Compressing total backup...${NC}"
cd "$BACKUP_ROOT"
tar -czf "backup_${TIMESTAMP}.tar.gz" "backup_${TIMESTAMP}"
rm -rf "backup_${TIMESTAMP}"

echo -e "\n${GREEN}=== Backup Completed Successfully ===${NC}"
echo -e "Final Archive: ${CYAN}${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz${NC}"
if [ -f "${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz" ]; then
    echo -e "Size: $(du -sh "${BACKUP_ROOT}/backup_${TIMESTAMP}.tar.gz" | cut -f1)"
fi
