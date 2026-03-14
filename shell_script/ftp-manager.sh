#!/bin/bash

# FTP Management Script for Ubuntu VPS
# Requires root privileges

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Install vsftpd
install_vsftpd() {
    echo -e "${YELLOW}Installing vsftpd...${NC}"
    apt-get update
    apt-get install -y vsftpd
    
    # Backup original config
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
    
    echo -e "${GREEN}vsftpd installed successfully!${NC}"
    configure_vsftpd
}

# Configure vsftpd with secure settings
configure_vsftpd() {
    echo -e "${YELLOW}Configuring vsftpd...${NC}"
    
    cat > /etc/vsftpd.conf << 'EOF'
# Basic settings
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# Security settings
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd

# Passive mode settings
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000

# User list
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO

# Performance
idle_session_timeout=600
data_connection_timeout=120

# Logging
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES
EOF

    # Create userlist file if it doesn't exist
    touch /etc/vsftpd.userlist
    
    echo -e "${GREEN}vsftpd configured successfully!${NC}"
    systemctl restart vsftpd
}

# Add FTP user
add_ftp_user() {
    read -p "Enter username: " username
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username already exists${NC}"
        return 1
    fi
    
    read -p "Enter home directory path (default: /home/$username): " homedir
    homedir=${homedir:-/home/$username}
    
    # Create user without shell access
    useradd -m -d "$homedir" -s /usr/sbin/nologin "$username"
    
    # Set password
    passwd "$username"
    
    # Add to vsftpd userlist
    echo "$username" >> /etc/vsftpd.userlist
    
    # Set proper permissions
    chown -R "$username:$username" "$homedir"
    chmod 755 "$homedir"
    
    echo -e "${GREEN}FTP user $username created successfully!${NC}"
    echo -e "${YELLOW}Home directory: $homedir${NC}"
}

# Remove FTP user
remove_ftp_user() {
    read -p "Enter username to remove: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        return 1
    fi
    
    read -p "Are you sure you want to remove $username? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
        echo "Cancelled"
        return 0
    fi
    
    # Remove from userlist
    sed -i "/^$username$/d" /etc/vsftpd.userlist
    
    # Remove user
    userdel -r "$username"
    
    echo -e "${GREEN}User $username removed successfully!${NC}"
}

# List FTP users
list_ftp_users() {
    echo -e "${YELLOW}FTP Users:${NC}"
    if [ -f /etc/vsftpd.userlist ]; then
        cat /etc/vsftpd.userlist
    else
        echo "No users configured"
    fi
}

# Change user password
change_password() {
    read -p "Enter username: " username
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        return 1
    fi
    
    passwd "$username"
    echo -e "${GREEN}Password changed successfully!${NC}"
}

# Check FTP status
check_status() {
    echo -e "${YELLOW}vsftpd Service Status:${NC}"
    systemctl status vsftpd
}

# Start FTP service
start_service() {
    systemctl start vsftpd
    echo -e "${GREEN}vsftpd service started${NC}"
}

# Stop FTP service
stop_service() {
    systemctl stop vsftpd
    echo -e "${GREEN}vsftpd service stopped${NC}"
}

# Restart FTP service
restart_service() {
    systemctl restart vsftpd
    echo -e "${GREEN}vsftpd service restarted${NC}"
}

# Enable service on boot
enable_service() {
    systemctl enable vsftpd
    echo -e "${GREEN}vsftpd will start on boot${NC}"
}

# View logs
view_logs() {
    echo -e "${YELLOW}Recent FTP logs (last 50 lines):${NC}"
    tail -n 50 /var/log/vsftpd.log
}

# Configure firewall
configure_firewall() {
    echo -e "${YELLOW}Configuring firewall for FTP...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow 20/tcp
        ufw allow 21/tcp
        ufw allow 40000:50000/tcp
        ufw reload
        echo -e "${GREEN}Firewall rules added${NC}"
    else
        echo -e "${RED}UFW not found. Install it with: apt-get install ufw${NC}"
    fi
}

# Main menu
show_menu() {
    clear
    echo "======================================"
    echo "   FTP Management Script - Ubuntu VPS"
    echo "======================================"
    echo "1.  Install vsftpd"
    echo "2.  Configure vsftpd"
    echo "3.  Add FTP user"
    echo "4.  Remove FTP user"
    echo "5.  List FTP users"
    echo "6.  Change user password"
    echo "7.  Check service status"
    echo "8.  Start service"
    echo "9.  Stop service"
    echo "10. Restart service"
    echo "11. Enable service on boot"
    echo "12. View logs"
    echo "13. Configure firewall"
    echo "0.  Exit"
    echo "======================================"
}

# Main loop
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Enter your choice: " choice
        
        case $choice in
            1) install_vsftpd ;;
            2) configure_vsftpd ;;
            3) add_ftp_user ;;
            4) remove_ftp_user ;;
            5) list_ftp_users ;;
            6) change_password ;;
            7) check_status ;;
            8) start_service ;;
            9) stop_service ;;
            10) restart_service ;;
            11) enable_service ;;
            12) view_logs ;;
            13) configure_firewall ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main