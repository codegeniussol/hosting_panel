#!/bin/bash
# FTP User Account Management (using vsftpd)
# Usage: ./manage-ftp.sh [setup|add|remove|modify|list|quota] [username]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
USERNAME=$2

usage() {
    echo "Usage: $0 [setup|add|remove|modify|list|quota|info] [username]"
    echo ""
    echo "Actions:"
    echo "  setup                    - Install and configure vsftpd"
    echo "  add <username>          - Create FTP user"
    echo "  remove <username>       - Remove FTP user"
    echo "  modify <username>       - Modify FTP user"
    echo "  list                    - List all FTP users"
    echo "  quota <user> <mb>       - Set FTP user quota"
    echo "  info <username>         - Show FTP user info"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 add ftpuser"
    echo "  $0 quota ftpuser 5000"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

FTP_USERS_FILE="/etc/vsftpd.userlist"
FTP_CONFIG="/etc/vsftpd.conf"
FTP_HOME="/home/ftp"

# Setup vsftpd
setup_ftp() {
    echo -e "${GREEN}=== Installing vsftpd FTP Server ===${NC}"
    
    # Install vsftpd
    if command -v apt &> /dev/null; then
        apt update
        apt install -y vsftpd
    elif command -v yum &> /dev/null; then
        yum install -y vsftpd || dnf install -y vsftpd
    else
        echo -e "${RED}Unsupported package manager${NC}"
        exit 1
    fi
    
    # Backup original config
    cp "$FTP_CONFIG" "${FTP_CONFIG}.original"
    
    # Create FTP home directory
    mkdir -p "$FTP_HOME"
    chmod 755 "$FTP_HOME"
    
    # Configure vsftpd
    cat > "$FTP_CONFIG" <<'EOF'
# vsftpd configuration

# Basic settings
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# Security
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd

# User list
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO

# Passive mode
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# Performance
max_clients=50
max_per_ip=5

# Logging
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES

# Banner
ftpd_banner=Welcome to FTP Server

# Additional security
ssl_enable=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO

# User isolation
user_sub_token=$USER
local_root=/home/ftp/$USER

# File permissions
file_open_mode=0755
local_umask=022
EOF
    
    # Create user list file
    touch "$FTP_USERS_FILE"
    chmod 600 "$FTP_USERS_FILE"
    
    # Create log directory
    mkdir -p /var/log
    touch /var/log/vsftpd.log
    
    # Configure firewall (if ufw is installed)
    if command -v ufw &> /dev/null; then
        ufw allow 20/tcp
        ufw allow 21/tcp
        ufw allow 40000:40100/tcp
        echo -e "${GREEN}Firewall rules added${NC}"
    fi
    
    # Start vsftpd
    systemctl enable vsftpd
    systemctl restart vsftpd
    
    echo -e "${GREEN}vsftpd setup complete${NC}"
    echo -e "${YELLOW}Config:${NC} $FTP_CONFIG"
    echo -e "${YELLOW}User list:${NC} $FTP_USERS_FILE"
    echo -e "${YELLOW}FTP home:${NC} $FTP_HOME"
    echo -e "${YELLOW}Passive ports:${NC} 40000-40100"
}

# Add FTP user
add_ftp_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    # Check if user exists in system
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}System user $username already exists${NC}"
        read -p "Use existing system user? (y/n): " USE_EXISTING
        
        if [ "$USE_EXISTING" != "y" ] && [ "$USE_EXISTING" != "Y" ]; then
            exit 0
        fi
    else
        # Create system user
        echo -e "${GREEN}Creating FTP user: $username${NC}"
        
        read -s -p "Enter password: " PASSWORD
        echo ""
        read -s -p "Confirm password: " PASSWORD_CONFIRM
        echo ""
        
        if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
            echo -e "${RED}Passwords do not match${NC}"
            exit 1
        fi
        
        # Create user with nologin shell
        useradd -m -d "$FTP_HOME/$username" -s /sbin/nologin "$username"
        echo "$username:$PASSWORD" | chpasswd
    fi
    
    # Create FTP directory structure
    USER_FTP_DIR="$FTP_HOME/$username"
    mkdir -p "$USER_FTP_DIR"
    mkdir -p "$USER_FTP_DIR/uploads"
    mkdir -p "$USER_FTP_DIR/downloads"
    
    # Set permissions
    chown -R $username:$username "$USER_FTP_DIR"
    chmod 755 "$USER_FTP_DIR"
    chmod 755 "$USER_FTP_DIR/uploads"
    chmod 755 "$USER_FTP_DIR/downloads"
    
    # Add to userlist
    if ! grep -q "^$username$" "$FTP_USERS_FILE" 2>/dev/null; then
        echo "$username" >> "$FTP_USERS_FILE"
    fi
    
    # Create user config
    cat > "$USER_FTP_DIR/.ftpconfig" <<EOF
USERNAME=$username
CREATED=$(date)
FTP_DIR=$USER_FTP_DIR
QUOTA=unlimited
EOF
    
    echo -e "${GREEN}FTP user created successfully${NC}"
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}FTP Directory:${NC} $USER_FTP_DIR"
    echo -e "${YELLOW}FTP Address:${NC} ftp://$(hostname -I | awk '{print $1}')"
}

# Remove FTP user
remove_ftp_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will remove FTP access for $username${NC}"
    read -p "Also delete system user and files? (y/n): " DELETE_ALL
    
    # Remove from userlist
    sed -i "/^$username$/d" "$FTP_USERS_FILE"
    
    if [ "$DELETE_ALL" = "y" ] || [ "$DELETE_ALL" = "Y" ]; then
        # Backup user data
        BACKUP_DIR="/root/ftp_backups"
        mkdir -p "$BACKUP_DIR"
        
        if [ -d "$FTP_HOME/$username" ]; then
            tar -czf "$BACKUP_DIR/${username}_$(date +%Y%m%d_%H%M%S).tar.gz" "$FTP_HOME/$username"
            echo -e "${YELLOW}Backup saved to: $BACKUP_DIR${NC}"
        fi
        
        # Delete user and files
        userdel -r $username 2>/dev/null || userdel $username
        rm -rf "$FTP_HOME/$username"
        
        echo -e "${GREEN}FTP user and files removed${NC}"
    else
        echo -e "${GREEN}FTP access removed (user and files kept)${NC}"
    fi
}

# Modify FTP user
modify_ftp_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Modify FTP user: $username${NC}"
    echo "1. Change password"
    echo "2. Change home directory"
    echo "3. Set quota"
    echo "4. Reset permissions"
    echo "0. Cancel"
    echo ""
    read -p "Select option: " OPTION
    
    case $OPTION in
        1)
            read -s -p "Enter new password: " NEW_PASSWORD
            echo ""
            echo "$username:$NEW_PASSWORD" | chpasswd
            echo -e "${GREEN}Password changed${NC}"
            ;;
        2)
            read -p "Enter new home directory: " NEW_HOME
            usermod -d "$NEW_HOME" $username
            mkdir -p "$NEW_HOME"
            chown $username:$username "$NEW_HOME"
            echo -e "${GREEN}Home directory changed to $NEW_HOME${NC}"
            ;;
        3)
            read -p "Enter quota in MB: " QUOTA_MB
            set_ftp_quota $username $QUOTA_MB
            ;;
        4)
            chown -R $username:$username "$FTP_HOME/$username"
            chmod 755 "$FTP_HOME/$username"
            echo -e "${GREEN}Permissions reset${NC}"
            ;;
        0)
            echo "Cancelled"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
}

# List FTP users
list_ftp_users() {
    echo -e "${GREEN}=== FTP Users ===${NC}"
    echo ""
    
    if [ ! -f "$FTP_USERS_FILE" ] || [ ! -s "$FTP_USERS_FILE" ]; then
        echo -e "${YELLOW}No FTP users configured${NC}"
        exit 0
    fi
    
    printf "%-20s %-30s %-15s %-15s\n" "USERNAME" "HOME DIRECTORY" "QUOTA" "STATUS"
    echo "--------------------------------------------------------------------------------"
    
    while IFS= read -r username; do
        if [ -n "$username" ]; then
            HOME_DIR=$(getent passwd "$username" | cut -d: -f6)
            
            # Get quota if set
            if command -v quota &> /dev/null; then
                QUOTA_INFO=$(quota -w $username 2>/dev/null | tail -1 | awk '{print $3}')
                QUOTA=${QUOTA_INFO:-"unlimited"}
            else
                QUOTA="unlimited"
            fi
            
            # Check if user can login
            SHELL=$(getent passwd "$username" | cut -d: -f7)
            if [ "$SHELL" = "/sbin/nologin" ] || [ "$SHELL" = "/usr/sbin/nologin" ]; then
                STATUS="${GREEN}FTP only${NC}"
            else
                STATUS="${YELLOW}Full access${NC}"
            fi
            
            printf "%-20s %-30s %-15s %-15s\n" "$username" "$HOME_DIR" "$QUOTA" "$(echo -e $STATUS)"
        fi
    done < "$FTP_USERS_FILE"
}

# Set FTP user quota
set_ftp_quota() {
    local username=$1
    local quota_mb=$2
    
    if [ -z "$username" ] || [ -z "$quota_mb" ]; then
        echo -e "${RED}Username and quota required${NC}"
        echo "Usage: $0 quota <username> <quota_mb>"
        exit 1
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Check if quota tools are installed
    if ! command -v setquota &> /dev/null; then
        echo -e "${YELLOW}Installing quota tools...${NC}"
        if command -v apt &> /dev/null; then
            apt install -y quota quotatool
        elif command -v yum &> /dev/null; then
            yum install -y quota || dnf install -y quota
        fi
    fi
    
    # Set quota
    SOFT_BLOCKS=$((quota_mb * 1024))
    HARD_BLOCKS=$((quota_mb * 1024 + 512))
    
    setquota -u $username $SOFT_BLOCKS $HARD_BLOCKS 0 0 /home 2>/dev/null || \
        echo -e "${YELLOW}Quota system may not be enabled. Run manage-quota.sh setup first.${NC}"
    
    # Update config file
    if [ -f "$FTP_HOME/$username/.ftpconfig" ]; then
        sed -i "s/^QUOTA=.*/QUOTA=${quota_mb}MB/" "$FTP_HOME/$username/.ftpconfig"
    fi
    
    echo -e "${GREEN}Quota set to ${quota_mb}MB for $username${NC}"
}

# Show FTP user info
show_ftp_info() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== FTP User Information: $username ===${NC}"
    echo ""
    
    # User details
    USER_INFO=$(getent passwd $username)
    HOME_DIR=$(echo $USER_INFO | cut -d: -f6)
    SHELL=$(echo $USER_INFO | cut -d: -f7)
    
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}Home Directory:${NC} $HOME_DIR"
    echo -e "${YELLOW}Shell:${NC} $SHELL"
    
    # FTP status
    if grep -q "^$username$" "$FTP_USERS_FILE" 2>/dev/null; then
        echo -e "${YELLOW}FTP Access:${NC} ${GREEN}Enabled${NC}"
    else
        echo -e "${YELLOW}FTP Access:${NC} ${RED}Disabled${NC}"
    fi
    
    # Disk usage
    if [ -d "$HOME_DIR" ]; then
        DISK_USAGE=$(du -sh "$HOME_DIR" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}Disk Usage:${NC} $DISK_USAGE"
    fi
    
    # Quota
    if command -v quota &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Quota Information:${NC}"
        quota -vs $username 2>/dev/null || echo "No quota set"
    fi
    
    # Recent connections
    echo ""
    echo -e "${YELLOW}Recent FTP connections:${NC}"
    grep "$username" /var/log/vsftpd.log 2>/dev/null | tail -5 || echo "No recent connections"
}

# Main logic
case $ACTION in
    setup)
        setup_ftp
        ;;
    add)
        add_ftp_user $USERNAME
        ;;
    remove)
        remove_ftp_user $USERNAME
        ;;
    modify)
        modify_ftp_user $USERNAME
        ;;
    list)
        list_ftp_users
        ;;
    quota)
        QUOTA_MB=$3
        set_ftp_quota $USERNAME $QUOTA_MB
        ;;
    info)
        show_ftp_info $USERNAME
        ;;
    *)
        usage
        ;;
esac