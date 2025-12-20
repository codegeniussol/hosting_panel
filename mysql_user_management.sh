#!/bin/bash
# MySQL User Management Script
# Usage: ./manage-mysql-user.sh [create|delete|modify|list|info] [username]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
USERNAME=$2
PASSWORD=$3

usage() {
    echo "Usage: $0 [create|delete|modify|list|info|password] [username] [password]"
    echo ""
    echo "Actions:"
    echo "  create <user> <password>   - Create MySQL user"
    echo "  delete <user>              - Delete MySQL user"
    echo "  modify <user>              - Modify user settings"
    echo "  list                       - List all MySQL users"
    echo "  info <user>                - Show user information"
    echo "  password <user> <new_pass> - Change user password"
    echo ""
    echo "Examples:"
    echo "  $0 create dbuser secretpass"
    echo "  $0 delete dbuser"
    echo "  $0 password dbuser newpass123"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Get MySQL root password
get_mysql_password() {
    if [ -f /root/.my.cnf ]; then
        MYSQL_ROOT_PASSWORD=$(grep password /root/.my.cnf | cut -d'=' -f2 | tr -d ' "'"'"'')
        MYSQL_CMD="mysql"
    else
        echo -e "${YELLOW}Enter MySQL root password:${NC}"
        read -s MYSQL_ROOT_PASSWORD
        MYSQL_CMD="mysql -u root -p${MYSQL_ROOT_PASSWORD}"
    fi
}

# Create MySQL user
create_user() {
    local username=$1
    local password=$2
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Get password if not provided
    if [ -z "$password" ]; then
        read -s -p "Enter password for $username: " password
        echo ""
        read -s -p "Confirm password: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            echo -e "${RED}Passwords do not match${NC}"
            exit 1
        fi
    fi
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -gt 0 ]; then
        echo -e "${RED}User $username already exists${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Creating MySQL user: $username${NC}"
    
    # Get host
    echo -e "${YELLOW}Access from:${NC}"
    echo "1. localhost only"
    echo "2. any host (%)"
    echo "3. specific host/IP"
    read -p "Choice [1-3]: " HOST_CHOICE
    
    case $HOST_CHOICE in
        1)
            HOST="localhost"
            ;;
        2)
            HOST="%"
            ;;
        3)
            read -p "Enter host/IP: " HOST
            ;;
        *)
            HOST="localhost"
            ;;
    esac
    
    # Create user
    $MYSQL_CMD <<MYSQL_SCRIPT
CREATE USER '${username}'@'${HOST}' IDENTIFIED BY '${password}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}User created successfully${NC}"
        echo -e "${YELLOW}Username:${NC} $username"
        echo -e "${YELLOW}Host:${NC} $HOST"
        echo ""
        echo -e "${YELLOW}Grant permissions using:${NC}"
        echo "  ./manage-mysql-permissions.sh grant $username <database>"
    else
        echo -e "${RED}Failed to create user${NC}"
        exit 1
    fi
}

# Delete MySQL user
delete_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Get all hosts for this user
    echo -e "${YELLOW}Hosts for user $username:${NC}"
    $MYSQL_CMD -e "SELECT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null
    
    echo ""
    echo -e "${RED}WARNING: This will delete user $username from all hosts${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Delete user from all hosts
    $MYSQL_CMD <<MYSQL_SCRIPT
DROP USER IF EXISTS '${username}'@'localhost';
DROP USER IF EXISTS '${username}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
    
    # Try to drop any other host combinations
    HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
    
    for host in $HOSTS; do
        $MYSQL_CMD -e "DROP USER IF EXISTS '${username}'@'${host}';" 2>/dev/null
    done
    
    $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    echo -e "${GREEN}User deleted successfully${NC}"
}

# Modify MySQL user
modify_user() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Modify MySQL user: $username${NC}"
    echo "1. Change password"
    echo "2. Change host"
    echo "3. Rename user"
    echo "4. Lock account"
    echo "5. Unlock account"
    echo "0. Cancel"
    echo ""
    read -p "Select option: " OPTION
    
    case $OPTION in
        1)
            read -s -p "Enter new password: " NEW_PASSWORD
            echo ""
            
            # Get hosts for user
            HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
            
            for host in $HOSTS; do
                $MYSQL_CMD -e "ALTER USER '${username}'@'${host}' IDENTIFIED BY '${NEW_PASSWORD}';" 2>/dev/null
            done
            
            $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
            echo -e "${GREEN}Password changed${NC}"
            ;;
        2)
            echo "Current hosts:"
            $MYSQL_CMD -e "SELECT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null
            
            read -p "Enter old host: " OLD_HOST
            read -p "Enter new host: " NEW_HOST
            
            $MYSQL_CMD -e "RENAME USER '${username}'@'${OLD_HOST}' TO '${username}'@'${NEW_HOST}';" 2>/dev/null
            echo -e "${GREEN}Host changed${NC}"
            ;;
        3)
            read -p "Enter new username: " NEW_USERNAME
            
            HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
            
            for host in $HOSTS; do
                $MYSQL_CMD -e "RENAME USER '${username}'@'${host}' TO '${NEW_USERNAME}'@'${host}';" 2>/dev/null
            done
            
            echo -e "${GREEN}User renamed to $NEW_USERNAME${NC}"
            ;;
        4)
            HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
            
            for host in $HOSTS; do
                $MYSQL_CMD -e "ALTER USER '${username}'@'${host}' ACCOUNT LOCK;" 2>/dev/null
            done
            
            echo -e "${GREEN}Account locked${NC}"
            ;;
        5)
            HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
            
            for host in $HOSTS; do
                $MYSQL_CMD -e "ALTER USER '${username}'@'${host}' ACCOUNT UNLOCK;" 2>/dev/null
            done
            
            echo -e "${GREEN}Account unlocked${NC}"
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

# List MySQL users
list_users() {
    get_mysql_password
    
    echo -e "${GREEN}=== MySQL Users ===${NC}"
    echo ""
    
    $MYSQL_CMD <<'MYSQL_SCRIPT'
SELECT 
    User AS 'Username',
    Host AS 'Host',
    plugin AS 'Auth Plugin',
    account_locked AS 'Locked'
FROM mysql.user 
WHERE User != '' 
ORDER BY User, Host;
MYSQL_SCRIPT
}

# Show user info
show_user_info() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== MySQL User Information: $username ===${NC}"
    echo ""
    
    # User details
    echo -e "${YELLOW}User Details:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    User,
    Host,
    plugin AS 'Auth Plugin',
    password_expired AS 'Password Expired',
    account_locked AS 'Account Locked',
    password_lifetime AS 'Password Lifetime',
    password_last_changed AS 'Last Password Change'
FROM mysql.user 
WHERE User='${username}';
MYSQL_SCRIPT
    
    echo ""
    echo -e "${YELLOW}Global Privileges:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SHOW GRANTS FOR '${username}'@'localhost';
MYSQL_SCRIPT
    
    echo ""
    echo -e "${YELLOW}Database Privileges:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    Db AS 'Database',
    GROUP_CONCAT(DISTINCT 
        CASE 
            WHEN Select_priv='Y' THEN 'SELECT'
            WHEN Insert_priv='Y' THEN 'INSERT'
            WHEN Update_priv='Y' THEN 'UPDATE'
            WHEN Delete_priv='Y' THEN 'DELETE'
            WHEN Create_priv='Y' THEN 'CREATE'
            WHEN Drop_priv='Y' THEN 'DROP'
        END
    ) AS 'Privileges'
FROM mysql.db 
WHERE User='${username}'
GROUP BY Db;
MYSQL_SCRIPT
}

# Change password
change_password() {
    local username=$1
    local new_password=$2
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Get password if not provided
    if [ -z "$new_password" ]; then
        read -s -p "Enter new password for $username: " new_password
        echo ""
        read -s -p "Confirm password: " password_confirm
        echo ""
        
        if [ "$new_password" != "$password_confirm" ]; then
            echo -e "${RED}Passwords do not match${NC}"
            exit 1
        fi
    fi
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Change password for all hosts
    HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
    
    for host in $HOSTS; do
        $MYSQL_CMD -e "ALTER USER '${username}'@'${host}' IDENTIFIED BY '${new_password}';" 2>/dev/null
    done
    
    $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    echo -e "${GREEN}Password changed successfully${NC}"
}

# Main logic
case $ACTION in
    create)
        create_user $USERNAME "$PASSWORD"
        ;;
    delete)
        delete_user $USERNAME
        ;;
    modify)
        modify_user $USERNAME
        ;;
    list)
        list_users
        ;;
    info)
        show_user_info $USERNAME
        ;;
    password)
        change_password $USERNAME "$PASSWORD"
        ;;
    *)
        usage
        ;;
esac