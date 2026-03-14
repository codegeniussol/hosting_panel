#!/bin/bash
# User Account Management Script
# Usage: ./manage-user.sh [create|delete|modify|list] [username]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
USERNAME=$2

# Function to display usage
usage() {
    echo "Usage: $0 [create|delete|modify|list|info] [username]"
    echo ""
    echo "Actions:"
    echo "  create <username>  - Create a new user account"
    echo "  delete <username>  - Delete a user account"
    echo "  modify <username>  - Modify user settings"
    echo "  list              - List all users"
    echo "  info <username>   - Show user information"
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Create user
create_user() {
    local username=$1
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username already exists${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Creating user: $username${NC}"
    
    # Get password
    echo -e "${YELLOW}Enter password for $username:${NC}"
    read -s PASSWORD
    echo -e "${YELLOW}Confirm password:${NC}"
    read -s PASSWORD_CONFIRM
    
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo -e "${RED}Passwords do not match${NC}"
        exit 1
    fi
    
    # Get additional information
    echo -e "${YELLOW}Enter full name (optional):${NC}"
    read FULLNAME
    
    echo -e "${YELLOW}Enter shell (default: /bin/bash):${NC}"
    read SHELL_CHOICE
    SHELL_CHOICE=${SHELL_CHOICE:-/bin/bash}
    
    # Create user with home directory
    useradd -m -s "$SHELL_CHOICE" -c "$FULLNAME" "$username"
    
    # Set password
    echo "$username:$PASSWORD" | chpasswd
    
    # Create www directory
    mkdir -p /home/$username/www
    mkdir -p /home/$username/public_html
    mkdir -p /home/$username/logs
    mkdir -p /home/$username/tmp
    
    # Set permissions
    chown -R $username:$username /home/$username
    chmod 755 /home/$username
    chmod 755 /home/$username/www
    chmod 755 /home/$username/public_html
    
    # Add user to www-data group (or nginx group)
    if getent group www-data > /dev/null 2>&1; then
        usermod -a -G www-data $username
    elif getent group nginx > /dev/null 2>&1; then
        usermod -a -G nginx $username
    fi
    
    # Create user config file
    cat > /home/$username/.userconfig <<EOF
USERNAME=$username
CREATED=$(date)
HOME_DIR=/home/$username
WWW_DIR=/home/$username/www
PUBLIC_DIR=/home/$username/public_html
LOGS_DIR=/home/$username/logs
EOF
    
    chown $username:$username /home/$username/.userconfig
    
    echo -e "${GREEN}User $username created successfully${NC}"
    echo -e "${YELLOW}Home directory:${NC} /home/$username"
    echo -e "${YELLOW}Web directory:${NC} /home/$username/www"
    echo -e "${YELLOW}Public directory:${NC} /home/$username/public_html"
}

# Delete user
delete_user() {
    local username=$1
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will delete user $username and all their files${NC}"
    echo -e "${YELLOW}Are you sure? (yes/no):${NC}"
    read CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Backup user data
    BACKUP_DIR="/root/user_backups"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/${username}_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    echo -e "${YELLOW}Creating backup...${NC}"
    tar -czf "$BACKUP_FILE" /home/$username 2>/dev/null || true
    
    echo -e "${YELLOW}Backup saved to: $BACKUP_FILE${NC}"
    
    # Kill all user processes
    pkill -u $username || true
    
    # Delete user and home directory
    userdel -r $username 2>/dev/null || userdel $username
    
    # Remove from additional groups
    groupdel $username 2>/dev/null || true
    
    echo -e "${GREEN}User $username deleted successfully${NC}"
}

# Modify user
modify_user() {
    local username=$1
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Modify user: $username${NC}"
    echo "1. Change password"
    echo "2. Change shell"
    echo "3. Change full name"
    echo "4. Lock account"
    echo "5. Unlock account"
    echo "6. Add to sudo group"
    echo "7. Remove from sudo group"
    echo "0. Cancel"
    echo ""
    echo -e "${YELLOW}Select option:${NC}"
    read OPTION
    
    case $OPTION in
        1)
            echo -e "${YELLOW}Enter new password:${NC}"
            read -s NEW_PASSWORD
            echo "$username:$NEW_PASSWORD" | chpasswd
            echo -e "${GREEN}Password changed${NC}"
            ;;
        2)
            echo -e "${YELLOW}Enter new shell (e.g., /bin/bash, /bin/zsh):${NC}"
            read NEW_SHELL
            usermod -s "$NEW_SHELL" $username
            echo -e "${GREEN}Shell changed to $NEW_SHELL${NC}"
            ;;
        3)
            echo -e "${YELLOW}Enter new full name:${NC}"
            read NEW_NAME
            usermod -c "$NEW_NAME" $username
            echo -e "${GREEN}Full name changed${NC}"
            ;;
        4)
            usermod -L $username
            echo -e "${GREEN}Account locked${NC}"
            ;;
        5)
            usermod -U $username
            echo -e "${GREEN}Account unlocked${NC}"
            ;;
        6)
            usermod -aG sudo $username 2>/dev/null || usermod -aG wheel $username
            echo -e "${GREEN}Added to sudo group${NC}"
            ;;
        7)
            gpasswd -d $username sudo 2>/dev/null || gpasswd -d $username wheel
            echo -e "${GREEN}Removed from sudo group${NC}"
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

# List users
list_users() {
    echo -e "${GREEN}=== System Users ===${NC}"
    echo ""
    printf "%-20s %-10s %-30s %-20s\n" "USERNAME" "UID" "HOME" "SHELL"
    echo "--------------------------------------------------------------------------------"
    
    # List only regular users (UID >= 1000)
    awk -F: '$3 >= 1000 {printf "%-20s %-10s %-30s %-20s\n", $1, $3, $6, $7}' /etc/passwd
}

# Show user info
show_user_info() {
    local username=$1
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== User Information: $username ===${NC}"
    echo ""
    
    # Get user info
    USER_INFO=$(getent passwd $username)
    UID=$(echo $USER_INFO | cut -d: -f3)
    GID=$(echo $USER_INFO | cut -d: -f4)
    FULLNAME=$(echo $USER_INFO | cut -d: -f5)
    HOME=$(echo $USER_INFO | cut -d: -f6)
    SHELL=$(echo $USER_INFO | cut -d: -f7)
    
    echo -e "${YELLOW}Username:${NC} $username"
    echo -e "${YELLOW}UID:${NC} $UID"
    echo -e "${YELLOW}GID:${NC} $GID"
    echo -e "${YELLOW}Full Name:${NC} $FULLNAME"
    echo -e "${YELLOW}Home Directory:${NC} $HOME"
    echo -e "${YELLOW}Shell:${NC} $SHELL"
    echo ""
    
    # Groups
    echo -e "${YELLOW}Groups:${NC}"
    groups $username
    echo ""
    
    # Disk usage
    if [ -d "$HOME" ]; then
        DISK_USAGE=$(du -sh "$HOME" 2>/dev/null | cut -f1)
        echo -e "${YELLOW}Disk Usage:${NC} $DISK_USAGE"
    fi
    
    # Quota info
    if command -v quota &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Quota Information:${NC}"
        quota -v $username 2>/dev/null || echo "No quota set"
    fi
    
    # Last login
    echo ""
    echo -e "${YELLOW}Last Login:${NC}"
    lastlog -u $username 2>/dev/null | tail -1
}

# Main logic
case $ACTION in
    create)
        if [ -z "$USERNAME" ]; then
            usage
        fi
        create_user $USERNAME
        ;;
    delete)
        if [ -z "$USERNAME" ]; then
            usage
        fi
        delete_user $USERNAME
        ;;
    modify)
        if [ -z "$USERNAME" ]; then
            usage
        fi
        modify_user $USERNAME
        ;;
    list)
        list_users
        ;;
    info)
        if [ -z "$USERNAME" ]; then
            usage
        fi
        show_user_info $USERNAME
        ;;
    *)
        usage
        ;;
esac