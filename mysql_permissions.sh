#!/bin/bash
# MySQL Permission Management Script
# Usage: ./manage-mysql-permissions.sh [grant|revoke|show|template] [username] [database]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
USERNAME=$2
DATABASE=$3

usage() {
    echo "Usage: $0 [grant|revoke|show|template|remote] [username] [database]"
    echo ""
    echo "Actions:"
    echo "  grant <user> <database>    - Grant permissions to database"
    echo "  revoke <user> <database>   - Revoke permissions from database"
    echo "  show <user>                - Show user permissions"
    echo "  template <user> <db> <type> - Apply permission template"
    echo "  remote <user> <host>       - Enable remote access"
    echo ""
    echo "Template types:"
    echo "  readonly  - SELECT only"
    echo "  readwrite - SELECT, INSERT, UPDATE, DELETE"
    echo "  full      - All privileges except GRANT"
    echo "  admin     - All privileges including GRANT"
    echo ""
    echo "Examples:"
    echo "  $0 grant dbuser myapp_db"
    echo "  $0 template dbuser myapp_db readwrite"
    echo "  $0 remote dbuser 192.168.1.100"
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

# Grant permissions
grant_permissions() {
    local username=$1
    local database=$2
    
    if [ -z "$username" ] || [ -z "$database" ]; then
        echo -e "${RED}Username and database required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Check if database exists
    DB_EXISTS=$($MYSQL_CMD -e "SHOW DATABASES LIKE '${database}';" 2>/dev/null | grep -c "$database" || echo "0")
    
    if [ "$DB_EXISTS" -eq 0 ]; then
        echo -e "${RED}Database $database does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Grant permissions for: ${username} on ${database}${NC}"
    echo ""
    echo "Permission templates:"
    echo "1. Read Only (SELECT)"
    echo "2. Read/Write (SELECT, INSERT, UPDATE, DELETE)"
    echo "3. Full Access (All privileges except GRANT)"
    echo "4. Admin (All privileges including GRANT)"
    echo "5. Custom (choose specific privileges)"
    echo ""
    read -p "Select template [1-5]: " TEMPLATE
    
    # Get user host
    USER_HOST=$($MYSQL_CMD -N -e "SELECT Host FROM mysql.user WHERE User='${username}' LIMIT 1;" 2>/dev/null)
    
    case $TEMPLATE in
        1)
            # Read only
            $MYSQL_CMD <<MYSQL_SCRIPT
GRANT SELECT ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Read-only permissions granted${NC}"
            ;;
        2)
            # Read/Write
            $MYSQL_CMD <<MYSQL_SCRIPT
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Read/Write permissions granted${NC}"
            ;;
        3)
            # Full access
            $MYSQL_CMD <<MYSQL_SCRIPT
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Full access granted (without GRANT option)${NC}"
            ;;
        4)
            # Admin
            $MYSQL_CMD <<MYSQL_SCRIPT
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${username}'@'${USER_HOST}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Admin privileges granted${NC}"
            ;;
        5)
            # Custom
            echo ""
            echo "Available privileges:"
            echo "SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER,"
            echo "INDEX, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE,"
            echo "CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE,"
            echo "EVENT, TRIGGER"
            echo ""
            read -p "Enter privileges (comma-separated): " PRIVILEGES
            
            $MYSQL_CMD <<MYSQL_SCRIPT
GRANT ${PRIVILEGES} ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Custom permissions granted${NC}"
            ;;
        *)
            echo -e "${RED}Invalid template${NC}"
            exit 1
            ;;
    esac
    
    # Show granted permissions
    echo ""
    echo -e "${YELLOW}Granted permissions:${NC}"
    $MYSQL_CMD -e "SHOW GRANTS FOR '${username}'@'${USER_HOST}';" 2>/dev/null | grep "$database"
}

# Revoke permissions
revoke_permissions() {
    local username=$1
    local database=$2
    
    if [ -z "$username" ] || [ -z "$database" ]; then
        echo -e "${RED}Username and database required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Get user host
    USER_HOST=$($MYSQL_CMD -N -e "SELECT Host FROM mysql.user WHERE User='${username}' LIMIT 1;" 2>/dev/null)
    
    echo -e "${YELLOW}Current permissions on ${database}:${NC}"
    $MYSQL_CMD -e "SHOW GRANTS FOR '${username}'@'${USER_HOST}';" 2>/dev/null | grep "$database" || echo "None"
    
    echo ""
    echo -e "${RED}WARNING: This will revoke all permissions on ${database}${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Revoke all permissions
    $MYSQL_CMD <<MYSQL_SCRIPT
REVOKE ALL PRIVILEGES ON \`${database}\`.* FROM '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
    
    echo -e "${GREEN}Permissions revoked${NC}"
}

# Show user permissions
show_permissions() {
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
    
    echo -e "${GREEN}=== Permissions for: $username ===${NC}"
    echo ""
    
    # Get all hosts for user
    HOSTS=$($MYSQL_CMD -N -e "SELECT DISTINCT Host FROM mysql.user WHERE User='${username}';" 2>/dev/null)
    
    for host in $HOSTS; do
        echo -e "${YELLOW}Host: $host${NC}"
        $MYSQL_CMD -e "SHOW GRANTS FOR '${username}'@'${host}';" 2>/dev/null
        echo ""
    done
}

# Apply permission template
apply_template() {
    local username=$1
    local database=$2
    local template=$3
    
    if [ -z "$username" ] || [ -z "$database" ] || [ -z "$template" ]; then
        echo -e "${RED}Username, database, and template required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Get user host
    USER_HOST=$($MYSQL_CMD -N -e "SELECT Host FROM mysql.user WHERE User='${username}' LIMIT 1;" 2>/dev/null)
    
    if [ -z "$USER_HOST" ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Applying '${template}' template for ${username} on ${database}${NC}"
    
    case $template in
        readonly)
            $MYSQL_CMD <<MYSQL_SCRIPT
REVOKE ALL PRIVILEGES ON \`${database}\`.* FROM '${username}'@'${USER_HOST}';
GRANT SELECT ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Read-only template applied${NC}"
            ;;
        readwrite)
            $MYSQL_CMD <<MYSQL_SCRIPT
REVOKE ALL PRIVILEGES ON \`${database}\`.* FROM '${username}'@'${USER_HOST}';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Read/Write template applied${NC}"
            ;;
        full)
            $MYSQL_CMD <<MYSQL_SCRIPT
REVOKE ALL PRIVILEGES ON \`${database}\`.* FROM '${username}'@'${USER_HOST}';
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${username}'@'${USER_HOST}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Full access template applied${NC}"
            ;;
        admin)
            $MYSQL_CMD <<MYSQL_SCRIPT
REVOKE ALL PRIVILEGES ON \`${database}\`.* FROM '${username}'@'${USER_HOST}';
GRANT ALL PRIVILEGES ON \`${database}\`.* TO '${username}'@'${USER_HOST}' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT
            echo -e "${GREEN}Admin template applied${NC}"
            ;;
        *)
            echo -e "${RED}Invalid template: $template${NC}"
            echo "Valid templates: readonly, readwrite, full, admin"
            exit 1
            ;;
    esac
    
    # Show applied permissions
    echo ""
    echo -e "${YELLOW}Applied permissions:${NC}"
    $MYSQL_CMD -e "SHOW GRANTS FOR '${username}'@'${USER_HOST}';" 2>/dev/null | grep "$database"
}

# Enable remote access
enable_remote_access() {
    local username=$1
    local remote_host=$2
    
    if [ -z "$username" ] || [ -z "$remote_host" ]; then
        echo -e "${RED}Username and remote host required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if user exists
    USER_EXISTS=$($MYSQL_CMD -e "SELECT User FROM mysql.user WHERE User='${username}';" 2>/dev/null | grep -c "$username" || echo "0")
    
    if [ "$USER_EXISTS" -eq 0 ]; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Enabling remote access for: ${username} from ${remote_host}${NC}"
    
    # Get current privileges
    echo -e "${YELLOW}Getting current privileges...${NC}"
    CURRENT_HOST=$($MYSQL_CMD -N -e "SELECT Host FROM mysql.user WHERE User='${username}' LIMIT 1;" 2>/dev/null)
    
    # Get password
    read -s -p "Enter password for user $username: " USER_PASSWORD
    echo ""
    
    # Create user for remote host
    $MYSQL_CMD <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '${username}'@'${remote_host}' IDENTIFIED BY '${USER_PASSWORD}';
MYSQL_SCRIPT
    
    # Copy grants from localhost to remote host
    echo -e "${YELLOW}Copying permissions...${NC}"
    
    # Get all database grants
    GRANTS=$($MYSQL_CMD -N -e "SELECT Db FROM mysql.db WHERE User='${username}' AND Host='${CURRENT_HOST}';" 2>/dev/null)
    
    for db in $GRANTS; do
        echo "  Granting permissions on $db"
        
        # Get privileges
        PRIVS=$($MYSQL_CMD -N <<MYSQL_SCRIPT
SELECT CONCAT(
    IF(Select_priv='Y','SELECT,',''),
    IF(Insert_priv='Y','INSERT,',''),
    IF(Update_priv='Y','UPDATE,',''),
    IF(Delete_priv='Y','DELETE,',''),
    IF(Create_priv='Y','CREATE,',''),
    IF(Drop_priv='Y','DROP,',''),
    IF(Alter_priv='Y','ALTER,',''),
    IF(Index_priv='Y','INDEX,',''),
    IF(Create_tmp_table_priv='Y','CREATE TEMPORARY TABLES,',''),
    IF(Lock_tables_priv='Y','LOCK TABLES,',''),
    IF(Execute_priv='Y','EXECUTE,',''),
    IF(Create_view_priv='Y','CREATE VIEW,',''),
    IF(Show_view_priv='Y','SHOW VIEW,',''),
    IF(Create_routine_priv='Y','CREATE ROUTINE,',''),
    IF(Alter_routine_priv='Y','ALTER ROUTINE,',''),
    IF(Event_priv='Y','EVENT,',''),
    IF(Trigger_priv='Y','TRIGGER,','')
) as privs
FROM mysql.db 
WHERE User='${username}' AND Host='${CURRENT_HOST}' AND Db='${db}';
MYSQL_SCRIPT
)
        
        # Remove trailing comma
        PRIVS=${PRIVS%,}
        
        if [ -n "$PRIVS" ]; then
            $MYSQL_CMD -e "GRANT ${PRIVS} ON \`${db}\`.* TO '${username}'@'${remote_host}';" 2>/dev/null
        fi
    done
    
    $MYSQL_CMD -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    echo -e "${GREEN}Remote access enabled${NC}"
    echo -e "${YELLOW}User:${NC} $username"
    echo -e "${YELLOW}From:${NC} $remote_host"
    echo ""
    echo -e "${YELLOW}Make sure your firewall allows MySQL connections (port 3306)${NC}"
    echo -e "${YELLOW}Connection string: mysql -u $username -p -h $(hostname -I | awk '{print $1}')${NC}"
}

# Main logic
case $ACTION in
    grant)
        grant_permissions $USERNAME $DATABASE
        ;;
    revoke)
        revoke_permissions $USERNAME $DATABASE
        ;;
    show)
        show_permissions $USERNAME
        ;;
    template)
        TEMPLATE=$4
        apply_template $USERNAME $DATABASE $TEMPLATE
        ;;
    remote)
        REMOTE_HOST=$3
        enable_remote_access $USERNAME $REMOTE_HOST
        ;;
    *)
        usage
        ;;
esac