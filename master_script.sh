#!/bin/bash
# LEMP Stack Master Management Script
# Central interface for all management scripts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# make a variable for each script path
LEMP_SETUP_SCRIPT="$SCRIPT_DIR/lemp_setup.sh"
PHPMYADMIN_SCRIPT="$SCRIPT_DIR/phpmyadmin_docker.sh"
USER_MANAGEMENT_SCRIPT="$SCRIPT_DIR/user_management.sh"
QUOTA_MANAGEMENT_SCRIPT="$SCRIPT_DIR/quota_management.sh"
VHOST_MANAGEMENT_SCRIPT="$SCRIPT_DIR/vhost_management.sh"
SSL_MANAGEMENT_SCRIPT="$SCRIPT_DIR/ssl_management.sh"
DNS_MANAGEMENT_SCRIPT="$SCRIPT_DIR/dns_management.sh"
FTP_MANAGEMENT_SCRIPT="$SCRIPT_DIR/ftp_management.sh"
MYSQL_DB_MANAGEMENT_SCRIPT="$SCRIPT_DIR/mysql_db_management.sh"
MYSQL_USER_MANAGEMENT_SCRIPT="$SCRIPT_DIR/mysql_user_management.sh"
MYSQL_PERM_MANAGEMENT_SCRIPT="$SCRIPT_DIR/mysql_permissions.sh"


clear
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║           LEMP STACK MANAGEMENT SYSTEM                    ║
║          Linux + Nginx + MySQL + PHP Manager              ║
╚═══════════════════════════════════════════════════════════╝
EOF

echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Main menu
show_main_menu() {
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           MAIN MENU                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}1.${NC}  Initial Setup & Installation"
    echo -e "${GREEN}2.${NC}  User Management"
    echo -e "${GREEN}3.${NC}  Quota Management"
    echo -e "${GREEN}4.${NC}  Virtual Host Management"
    echo -e "${GREEN}5.${NC}  SSL Certificate Management"
    echo -e "${GREEN}6.${NC}  DNS Zone Management"
    echo -e "${GREEN}7.${NC}  FTP Management"
    echo -e "${GREEN}8.${NC}  MySQL Database Management"
    echo -e "${GREEN}9.${NC}  MySQL User Management"
    echo -e "${GREEN}10.${NC} MySQL Permissions Management"
    echo -e "${GREEN}11.${NC} phpMyAdmin Management"
    echo -e "${GREEN}12.${NC} System Status & Monitoring"
    echo -e "${GREEN}0.${NC}  Exit"
    echo ""
    read -p "Select option: " main_choice
    
    case $main_choice in
        1) setup_menu ;;
        2) user_menu ;;
        3) quota_menu ;;
        4) vhost_menu ;;
        5) ssl_menu ;;
        6) dns_menu ;;
        7) ftp_menu ;;
        8) mysql_db_menu ;;
        9) mysql_user_menu ;;
        10) mysql_perm_menu ;;
        11) phpmyadmin_menu ;;
        12) system_status ;;
        0) exit 0 ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; show_main_menu ;;
    esac
}

# Setup menu
setup_menu() {
    clear
    echo -e "${YELLOW}=== Initial Setup & Installation ===${NC}"
    echo ""
    echo "1. Install LEMP Stack (Nginx, MySQL, PHP-FPM)"
    echo "2. Setup phpMyAdmin (Docker)"
    echo "3. Setup Quota System"
    echo "4. Setup FTP Server"
    echo "5. Setup DNS Server (BIND9)"
    echo "6. Install All (Complete Setup)"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " setup_choice
    
    case $setup_choice in
        1) 
            bash "$LEMP_SETUP_SCRIPT"
            ;;
        2) 
            bash "$PHPMYADMIN_SCRIPT"
            ;;
        3) 
            bash "$QUOTA_MANAGEMENT_SCRIPT" setup
            ;;
        4) 
            bash "$FTP_MANAGEMENT_SCRIPT" setup
            ;;
        5) 
            bash "$DNS_MANAGEMENT_SCRIPT" setup
            ;;
        6)
            echo -e "${YELLOW}Installing complete LEMP stack...${NC}"
            bash "$LEMP_SETUP_SCRIPT"
            bash "$PHPMYADMIN_SCRIPT"
            bash "$QUOTA_MANAGEMENT_SCRIPT" setup
            bash "$FTP_MANAGEMENT_SCRIPT" setup
            bash "$DNS_MANAGEMENT_SCRIPT" setup
            echo -e "${GREEN}Complete setup finished!${NC}"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; setup_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    setup_menu
}

# User menu
user_menu() {
    clear
    echo -e "${YELLOW}=== User Management ===${NC}"
    echo ""
    echo "1. Create User"
    echo "2. Delete User"
    echo "3. Modify User"
    echo "4. List All Users"
    echo "5. Show User Info"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " user_choice
    
    case $user_choice in
        1) 
            read -p "Enter username: " username
            bash "$USER_MANAGEMENT_SCRIPT" create "$username"
            ;;
        2) 
            read -p "Enter username: " username
            bash "$USER_MANAGEMENT_SCRIPT" delete "$username"
            ;;
        3) 
            read -p "Enter username: " username
            bash "$USER_MANAGEMENT_SCRIPT" modify "$username"
            ;;
        4) 
            bash "$USER_MANAGEMENT_SCRIPT" list
            ;;
        5) 
            read -p "Enter username: " username
            bash "$USER_MANAGEMENT_SCRIPT" info "$username"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; user_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    user_menu
}

# Quota menu
quota_menu() {
    clear
    echo -e "${YELLOW}=== Quota Management ===${NC}"
    echo ""
    echo "1. Set User Quota"
    echo "2. Remove User Quota"
    echo "3. Check User Quota"
    echo "4. View Quota Report"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " quota_choice
    
    case $quota_choice in
        1) 
            read -p "Enter username: " username
            read -p "Enter soft limit (MB): " soft
            read -p "Enter hard limit (MB): " hard
            bash "$QUOTA_MANAGEMENT_SCRIPT" set "$username" "$soft" "$hard"
            ;;
        2) 
            read -p "Enter username: " username
            bash "$QUOTA_MANAGEMENT_SCRIPT" remove "$username"
            ;;
        3) 
            read -p "Enter username: " username
            bash "$QUOTA_MANAGEMENT_SCRIPT" check "$username"
            ;;
        4) 
            bash "$QUOTA_MANAGEMENT_SCRIPT" report
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; quota_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    quota_menu
}

# Virtual host menu
vhost_menu() {
    clear
    echo -e "${YELLOW}=== Virtual Host Management ===${NC}"
    echo ""
    echo "1. Create Virtual Host"
    echo "2. Delete Virtual Host"
    echo "3. Enable Virtual Host"
    echo "4. Disable Virtual Host"
    echo "5. List Virtual Hosts"
    echo "6. Show Virtual Host Info"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " vhost_choice
    
    case $vhost_choice in
        1) 
            read -p "Enter domain: " domain
            read -p "Enter username: " username
            bash "$VHOST_MANAGEMENT_SCRIPT" create "$domain" "$username"
            ;;
        2) 
            read -p "Enter domain: " domain
            bash "$VHOST_MANAGEMENT_SCRIPT" delete "$domain"
            ;;
        3) 
            read -p "Enter domain: " domain
            bash "$VHOST_MANAGEMENT_SCRIPT" enable "$domain"
            ;;
        4) 
            read -p "Enter domain: " domain
            bash "$VHOST_MANAGEMENT_SCRIPT" disable "$domain"
            ;;
        5) 
            bash "$VHOST_MANAGEMENT_SCRIPT" list
            ;;
        6) 
            read -p "Enter domain: " domain
            bash "$VHOST_MANAGEMENT_SCRIPT" info "$domain"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; vhost_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    vhost_menu
}

# SSL menu
ssl_menu() {
    clear
    echo -e "${YELLOW}=== SSL Certificate Management ===${NC}"
    echo ""
    echo "1. Install SSL Certificate"
    echo "2. Renew SSL Certificate"
    echo "3. Remove SSL Certificate"
    echo "4. List SSL Certificates"
    echo "5. Show Certificate Info"
    echo "6. Setup Auto-Renewal"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " ssl_choice
    
    case $ssl_choice in
        1) 
            read -p "Enter domain: " domain
            bash "$SSL_MANAGEMENT_SCRIPT" install "$domain"
            ;;
        2) 
            read -p "Enter domain (leave empty for all): " domain
            bash "$SSL_MANAGEMENT_SCRIPT" renew "$domain"
            ;;
        3) 
            read -p "Enter domain: " domain
            bash "$SSL_MANAGEMENT_SCRIPT" remove "$domain"
            ;;
        4) 
            bash "$SSL_MANAGEMENT_SCRIPT" list
            ;;
        5) 
            read -p "Enter domain: " domain
            bash "$SSL_MANAGEMENT_SCRIPT" info "$domain"
            ;;
        6) 
            bash "$SSL_MANAGEMENT_SCRIPT" auto-renew
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; ssl_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    ssl_menu
}

# DNS menu
dns_menu() {
    clear
    echo -e "${YELLOW}=== DNS Zone Management ===${NC}"
    echo ""
    echo "1. Add DNS Zone"
    echo "2. Remove DNS Zone"
    echo "3. Add DNS Record"
    echo "4. Remove DNS Record"
    echo "5. List All Zones"
    echo "6. Check Zone Configuration"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " dns_choice
    
    case $dns_choice in
        1) 
            read -p "Enter domain: " domain
            bash "$DNS_MANAGEMENT_SCRIPT" add-zone "$domain"
            ;;
        2) 
            read -p "Enter domain: " domain
            bash "$DNS_MANAGEMENT_SCRIPT" remove-zone "$domain"
            ;;
        3) 
            read -p "Enter domain: " domain
            read -p "Enter record type (A/AAAA/CNAME/MX/TXT): " type
            read -p "Enter value: " value
            bash "$DNS_MANAGEMENT_SCRIPT" add-record "$domain" "$type" "$value"
            ;;
        4) 
            read -p "Enter domain: " domain
            read -p "Enter record type: " type
            bash "$DNS_MANAGEMENT_SCRIPT" remove-record "$domain" "$type"
            ;;
        5) 
            bash "$DNS_MANAGEMENT_SCRIPT" list
            ;;
        6) 
            read -p "Enter domain: " domain
            bash "$DNS_MANAGEMENT_SCRIPT" check "$domain"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; dns_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    dns_menu
}

# FTP menu
ftp_menu() {
    clear
    echo -e "${YELLOW}=== FTP Management ===${NC}"
    echo ""
    echo "1. Add FTP User"
    echo "2. Remove FTP User"
    echo "3. Modify FTP User"
    echo "4. List FTP Users"
    echo "5. Set FTP User Quota"
    echo "6. Show FTP User Info"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " ftp_choice
    
    case $ftp_choice in
        1) 
            read -p "Enter username: " username
            bash "$FTP_MANAGEMENT_SCRIPT" add "$username"
            ;;
        2) 
            read -p "Enter username: " username
            bash "$FTP_MANAGEMENT_SCRIPT" remove "$username"
            ;;
        3) 
            read -p "Enter username: " username
            bash "$FTP_MANAGEMENT_SCRIPT" modify "$username"
            ;;
        4) 
            bash "$FTP_MANAGEMENT_SCRIPT" list
            ;;
        5) 
            read -p "Enter username: " username
            read -p "Enter quota (MB): " quota
            bash "$FTP_MANAGEMENT_SCRIPT" quota "$username" "$quota"
            ;;
        6) 
            read -p "Enter username: " username
            bash "$FTP_MANAGEMENT_SCRIPT" info "$username"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; ftp_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    ftp_menu
}

# MySQL database menu
mysql_db_menu() {
    clear
    echo -e "${YELLOW}=== MySQL Database Management ===${NC}"
    echo ""
    echo "1. Create Database"
    echo "2. Delete Database"
    echo "3. List Databases"
    echo "4. Show Database Info"
    echo "5. Backup Database"
    echo "6. Restore Database"
    echo "7. Import SQL File"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " db_choice
    
    case $db_choice in
        1) 
            read -p "Enter database name: " dbname
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" create "$dbname"
            ;;
        2) 
            read -p "Enter database name: " dbname
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" delete "$dbname"
            ;;
        3) 
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" list
            ;;
        4) 
            read -p "Enter database name: " dbname
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" info "$dbname"
            ;;
        5) 
            read -p "Enter database name: " dbname
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" backup "$dbname"
            ;;
        6) 
            read -p "Enter database name: " dbname
            read -p "Enter backup file: " file
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" restore "$dbname" "$file"
            ;;
        7) 
            read -p "Enter database name: " dbname
            read -p "Enter SQL file: " file
            bash "$MYSQL_DB_MANAGEMENT_SCRIPT" import "$dbname" "$file"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; mysql_db_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    mysql_db_menu
}

# MySQL user menu
mysql_user_menu() {
    clear
    echo -e "${YELLOW}=== MySQL User Management ===${NC}"
    echo ""
    echo "1. Create MySQL User"
    echo "2. Delete MySQL User"
    echo "3. Modify MySQL User"
    echo "4. List MySQL Users"
    echo "5. Show User Info"
    echo "6. Change User Password"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " mysql_choice
    
    case $mysql_choice in
        1) 
            read -p "Enter username: " username
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" create "$username"
            ;;
        2) 
            read -p "Enter username: " username
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" delete "$username"
            ;;
        3) 
            read -p "Enter username: " username
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" modify "$username"
            ;;
        4) 
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" list
            ;;
        5) 
            read -p "Enter username: " username
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" info "$username"
            ;;
        6) 
            read -p "Enter username: " username
            bash "$MYSQL_USER_MANAGEMENT_SCRIPT" password "$username"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; mysql_user_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    mysql_user_menu
}

# MySQL permissions menu
mysql_perm_menu() {
    clear
    echo -e "${YELLOW}=== MySQL Permissions Management ===${NC}"
    echo ""
    echo "1. Grant Permissions"
    echo "2. Revoke Permissions"
    echo "3. Show User Permissions"
    echo "4. Apply Permission Template"
    echo "5. Enable Remote Access"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " perm_choice
    
    case $perm_choice in
        1) 
            read -p "Enter username: " username
            read -p "Enter database: " database
            bash "$MYSQL_PERM_MANAGEMENT_SCRIPT" grant "$username" "$database"
            ;;
        2) 
            read -p "Enter username: " username
            read -p "Enter database: " database
            bash "$MYSQL_PERM_MANAGEMENT_SCRIPT" revoke "$username" "$database"
            ;;
        3) 
            read -p "Enter username: " username
            bash "$MYSQL_PERM_MANAGEMENT_SCRIPT" show "$username"
            ;;
        4) 
            read -p "Enter username: " username
            read -p "Enter database: " database
            read -p "Enter template (readonly/readwrite/full/admin): " template
            bash "$MYSQL_PERM_MANAGEMENT_SCRIPT" template "$username" "$database" "$template"
            ;;
        5) 
            read -p "Enter username: " username
            read -p "Enter remote host/IP: " host
            bash "$MYSQL_PERM_MANAGEMENT_SCRIPT" remote "$username" "$host"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; mysql_perm_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    mysql_perm_menu
}

# phpMyAdmin menu
phpmyadmin_menu() {
    clear
    echo -e "${YELLOW}=== phpMyAdmin Management ===${NC}"
    echo ""
    echo "1. Start phpMyAdmin"
    echo "2. Stop phpMyAdmin"
    echo "3. Restart phpMyAdmin"
    echo "4. View Logs"
    echo "5. Reinstall phpMyAdmin"
    echo "0. Back to Main Menu"
    echo ""
    read -p "Select option: " pma_choice
    
    case $pma_choice in
        1) 
            cd /opt/phpmyadmin && docker-compose start
            echo -e "${GREEN}phpMyAdmin started${NC}"
            ;;
        2) 
            cd /opt/phpmyadmin && docker-compose stop
            echo -e "${GREEN}phpMyAdmin stopped${NC}"
            ;;
        3) 
            cd /opt/phpmyadmin && docker-compose restart
            echo -e "${GREEN}phpMyAdmin restarted${NC}"
            ;;
        4) 
            cd /opt/phpmyadmin && docker-compose logs -f
            ;;
        5) 
            bash "$PHPMYADMIN_SCRIPT"
            ;;
        0) show_main_menu ;;
        *) echo -e "${RED}Invalid option${NC}"; sleep 1; phpmyadmin_menu ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    phpmyadmin_menu
}

# System status
system_status() {
    clear
    echo -e "${GREEN}=== System Status & Monitoring ===${NC}"
    echo ""
    
    echo -e "${YELLOW}Service Status:${NC}"
    systemctl is-active nginx 2>/dev/null && echo -e "  Nginx: ${GREEN}Running${NC}" || echo -e "  Nginx: ${RED}Stopped${NC}"
    systemctl is-active mariadb 2>/dev/null && echo -e "  MariaDB: ${GREEN}Running${NC}" || echo -e "  MariaDB: ${RED}Stopped${NC}"
    systemctl is-active php*-fpm 2>/dev/null && echo -e "  PHP-FPM: ${GREEN}Running${NC}" || echo -e "  PHP-FPM: ${RED}Stopped${NC}"
    systemctl is-active vsftpd 2>/dev/null && echo -e "  FTP: ${GREEN}Running${NC}" || echo -e "  FTP: ${RED}Not Installed${NC}"
    systemctl is-active bind9 2>/dev/null || systemctl is-active named 2>/dev/null && echo -e "  DNS: ${GREEN}Running${NC}" || echo -e "  DNS: ${RED}Not Installed${NC}"
    docker ps | grep -q phpmyadmin && echo -e "  phpMyAdmin: ${GREEN}Running${NC}" || echo -e "  phpMyAdmin: ${RED}Stopped${NC}"
    
    echo ""
    echo -e "${YELLOW}Disk Usage:${NC}"
    df -h / | tail -1
    
    echo ""
    echo -e "${YELLOW}Memory Usage:${NC}"
    free -h | grep Mem
    
    echo ""
    echo -e "${YELLOW}System Load:${NC}"
    uptime
    
    echo ""
    read -p "Press Enter to continue..."
    show_main_menu
}

# Start the menu
show_main_menu