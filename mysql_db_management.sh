#!/bin/bash
# MySQL Database Management Script
# Usage: ./manage-mysql-db.sh [create|delete|list|info|backup|restore] [database]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
DATABASE=$2

usage() {
    echo "Usage: $0 [create|delete|list|info|backup|restore|import] [database] [file]"
    echo ""
    echo "Actions:"
    echo "  create <database>          - Create new database"
    echo "  delete <database>          - Delete database"
    echo "  list                       - List all databases"
    echo "  info <database>            - Show database info"
    echo "  backup <database> [file]   - Backup database"
    echo "  restore <database> <file>  - Restore database"
    echo "  import <database> <file>   - Import SQL file"
    echo ""
    echo "Examples:"
    echo "  $0 create myapp_db"
    echo "  $0 backup myapp_db /backup/myapp.sql"
    echo "  $0 import myapp_db schema.sql"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

BACKUP_DIR="/root/mysql_backups"

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

# Create database
create_database() {
    local dbname=$1
    
    if [ -z "$dbname" ]; then
        echo -e "${RED}Database name required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if database exists
    if $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${RED}Database $dbname already exists${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Creating database: $dbname${NC}"
    
    # Get charset and collation
    read -p "Character set [utf8mb4]: " CHARSET
    CHARSET=${CHARSET:-utf8mb4}
    
    read -p "Collation [utf8mb4_unicode_ci]: " COLLATION
    COLLATION=${COLLATION:-utf8mb4_unicode_ci}
    
    # Create database
    $MYSQL_CMD <<MYSQL_SCRIPT
CREATE DATABASE \`${dbname}\` 
CHARACTER SET ${CHARSET} 
COLLATE ${COLLATION};
MYSQL_SCRIPT
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Database created successfully${NC}"
        echo -e "${YELLOW}Database:${NC} $dbname"
        echo -e "${YELLOW}Charset:${NC} $CHARSET"
        echo -e "${YELLOW}Collation:${NC} $COLLATION"
        
        # Ask to create user
        echo ""
        read -p "Create a user for this database? (y/n): " CREATE_USER
        if [ "$CREATE_USER" = "y" ] || [ "$CREATE_USER" = "Y" ]; then
            echo -e "${YELLOW}Tip: Use ./manage-mysql-user.sh create <username> <password>${NC}"
        fi
    else
        echo -e "${RED}Failed to create database${NC}"
        exit 1
    fi
}

# Delete database
delete_database() {
    local dbname=$1
    
    if [ -z "$dbname" ]; then
        echo -e "${RED}Database name required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if database exists
    if ! $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${RED}Database $dbname does not exist${NC}"
        exit 1
    fi
    
    # Protect system databases
    if [ "$dbname" = "mysql" ] || [ "$dbname" = "information_schema" ] || \
       [ "$dbname" = "performance_schema" ] || [ "$dbname" = "sys" ]; then
        echo -e "${RED}Cannot delete system database: $dbname${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will permanently delete database: $dbname${NC}"
    read -p "Type database name to confirm: " CONFIRM
    
    if [ "$CONFIRM" != "$dbname" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Create backup before deletion
    echo -e "${YELLOW}Creating backup before deletion...${NC}"
    mkdir -p "$BACKUP_DIR"
    BACKUP_FILE="$BACKUP_DIR/${dbname}_before_delete_$(date +%Y%m%d_%H%M%S).sql"
    
    mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" "$dbname" > "$BACKUP_FILE" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup created: $BACKUP_FILE${NC}"
    fi
    
    # Drop database
    $MYSQL_CMD -e "DROP DATABASE \`${dbname}\`;" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Database deleted successfully${NC}"
    else
        echo -e "${RED}Failed to delete database${NC}"
        exit 1
    fi
}

# List databases
list_databases() {
    get_mysql_password
    
    echo -e "${GREEN}=== MySQL Databases ===${NC}"
    echo ""
    
    # Get database list with sizes
    $MYSQL_CMD <<'MYSQL_SCRIPT'
SELECT 
    table_schema AS 'Database',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)',
    COUNT(*) AS 'Tables'
FROM information_schema.TABLES 
GROUP BY table_schema
ORDER BY table_schema;
MYSQL_SCRIPT
}

# Show database info
show_database_info() {
    local dbname=$1
    
    if [ -z "$dbname" ]; then
        echo -e "${RED}Database name required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if database exists
    if ! $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${RED}Database $dbname does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Database Information: $dbname ===${NC}"
    echo ""
    
    # Database charset and collation
    echo -e "${YELLOW}Character Set & Collation:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    DEFAULT_CHARACTER_SET_NAME AS 'Charset',
    DEFAULT_COLLATION_NAME AS 'Collation'
FROM information_schema.SCHEMATA 
WHERE SCHEMA_NAME = '${dbname}';
MYSQL_SCRIPT
    
    echo ""
    echo -e "${YELLOW}Database Size:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.TABLES 
WHERE table_schema = '${dbname}';
MYSQL_SCRIPT
    
    echo ""
    echo -e "${YELLOW}Tables:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    TABLE_NAME AS 'Table',
    ENGINE AS 'Engine',
    TABLE_ROWS AS 'Rows',
    ROUND(((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024), 2) AS 'Size (MB)'
FROM information_schema.TABLES 
WHERE TABLE_SCHEMA = '${dbname}'
ORDER BY TABLE_NAME;
MYSQL_SCRIPT
    
    echo ""
    echo -e "${YELLOW}Users with access:${NC}"
    $MYSQL_CMD <<MYSQL_SCRIPT
SELECT 
    GRANTEE AS 'User',
    PRIVILEGE_TYPE AS 'Privilege'
FROM information_schema.SCHEMA_PRIVILEGES 
WHERE TABLE_SCHEMA = '${dbname}'
GROUP BY GRANTEE, PRIVILEGE_TYPE
ORDER BY GRANTEE;
MYSQL_SCRIPT
}

# Backup database
backup_database() {
    local dbname=$1
    local backup_file=$2
    
    if [ -z "$dbname" ]; then
        echo -e "${RED}Database name required${NC}"
        usage
    fi
    
    get_mysql_password
    
    # Check if database exists
    if ! $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${RED}Database $dbname does not exist${NC}"
        exit 1
    fi
    
    # Set backup file path
    if [ -z "$backup_file" ]; then
        mkdir -p "$BACKUP_DIR"
        backup_file="$BACKUP_DIR/${dbname}_$(date +%Y%m%d_%H%M%S).sql"
    fi
    
    echo -e "${YELLOW}Backing up database: $dbname${NC}"
    
    # Perform backup
    mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        "$dbname" > "$backup_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Compress backup
        gzip "$backup_file"
        backup_file="${backup_file}.gz"
        
        BACKUP_SIZE=$(du -h "$backup_file" | cut -f1)
        echo -e "${GREEN}Backup created successfully${NC}"
        echo -e "${YELLOW}File:${NC} $backup_file"
        echo -e "${YELLOW}Size:${NC} $BACKUP_SIZE"
    else
        echo -e "${RED}Backup failed${NC}"
        exit 1
    fi
}

# Restore database
restore_database() {
    local dbname=$1
    local backup_file=$2
    
    if [ -z "$dbname" ] || [ -z "$backup_file" ]; then
        echo -e "${RED}Database name and backup file required${NC}"
        usage
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo -e "${RED}Backup file not found: $backup_file${NC}"
        exit 1
    fi
    
    get_mysql_password
    
    # Check if database exists
    if ! $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${YELLOW}Database $dbname does not exist. Creating...${NC}"
        $MYSQL_CMD -e "CREATE DATABASE \`${dbname}\`;"
    fi
    
    echo -e "${RED}WARNING: This will overwrite database: $dbname${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    echo -e "${YELLOW}Restoring database: $dbname${NC}"
    
    # Check if file is compressed
    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" | mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$dbname" 2>/dev/null
    else
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$dbname" < "$backup_file" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Database restored successfully${NC}"
    else
        echo -e "${RED}Restore failed${NC}"
        exit 1
    fi
}

# Import SQL file
import_sql() {
    local dbname=$1
    local sql_file=$2
    
    if [ -z "$dbname" ] || [ -z "$sql_file" ]; then
        echo -e "${RED}Database name and SQL file required${NC}"
        usage
    fi
    
    if [ ! -f "$sql_file" ]; then
        echo -e "${RED}SQL file not found: $sql_file${NC}"
        exit 1
    fi
    
    get_mysql_password
    
    # Check if database exists
    if ! $MYSQL_CMD -e "SHOW DATABASES LIKE '${dbname}';" 2>/dev/null | grep -q "$dbname"; then
        echo -e "${RED}Database $dbname does not exist${NC}"
        read -p "Create database? (y/n): " CREATE_DB
        if [ "$CREATE_DB" = "y" ] || [ "$CREATE_DB" = "Y" ]; then
            $MYSQL_CMD -e "CREATE DATABASE \`${dbname}\`;"
        else
            exit 1
        fi
    fi
    
    echo -e "${YELLOW}Importing SQL file into: $dbname${NC}"
    
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "$dbname" < "$sql_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SQL file imported successfully${NC}"
    else
        echo -e "${RED}Import failed${NC}"
        exit 1
    fi
}

# Main logic
case $ACTION in
    create)
        create_database $DATABASE
        ;;
    delete)
        delete_database $DATABASE
        ;;
    list)
        list_databases
        ;;
    info)
        show_database_info $DATABASE
        ;;
    backup)
        BACKUP_FILE=$3
        backup_database $DATABASE "$BACKUP_FILE"
        ;;
    restore)
        BACKUP_FILE=$3
        restore_database $DATABASE "$BACKUP_FILE"
        ;;
    import)
        SQL_FILE=$3
        import_sql $DATABASE "$SQL_FILE"
        ;;
    *)
        usage
        ;;
esac