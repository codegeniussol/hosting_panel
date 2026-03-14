#!/bin/bash
# DNS Zone Management Script (using BIND9)
# Usage: ./manage-dns.sh [setup|add-zone|remove-zone|add-record|remove-record|list]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
DOMAIN=$2
RECORD_TYPE=$3
RECORD_VALUE=$4

usage() {
    echo "Usage: $0 [setup|add-zone|remove-zone|add-record|remove-record|list|check] [domain] [type] [value]"
    echo ""
    echo "Actions:"
    echo "  setup                           - Install and configure BIND9"
    echo "  add-zone <domain>              - Add new DNS zone"
    echo "  remove-zone <domain>           - Remove DNS zone"
    echo "  add-record <domain> <type> <value> - Add DNS record"
    echo "  remove-record <domain> <type>  - Remove DNS record"
    echo "  list                           - List all zones"
    echo "  check <domain>                 - Check zone configuration"
    echo ""
    echo "Record types: A, AAAA, CNAME, MX, TXT, NS"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 add-zone example.com"
    echo "  $0 add-record example.com A 192.168.1.100"
    echo "  $0 add-record example.com MX 'mail.example.com'"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

BIND_DIR="/etc/bind"
ZONES_DIR="$BIND_DIR/zones"

# Setup BIND9
setup_bind() {
    echo -e "${GREEN}=== Installing BIND9 DNS Server ===${NC}"
    
    # Install BIND9
    if command -v apt &> /dev/null; then
        apt update
        apt install -y bind9 bind9utils bind9-doc dnsutils
    elif command -v yum &> /dev/null; then
        yum install -y bind bind-utils || dnf install -y bind bind-utils
        BIND_DIR="/etc/named"
        ZONES_DIR="$BIND_DIR/zones"
    else
        echo -e "${RED}Unsupported package manager${NC}"
        exit 1
    fi
    
    # Create zones directory
    mkdir -p "$ZONES_DIR"
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${YELLOW}Server IP detected: $SERVER_IP${NC}"
    
    # Configure named.conf.options
    cat > "$BIND_DIR/named.conf.options" <<EOF
options {
    directory "/var/cache/bind";
    
    recursion yes;
    allow-recursion { any; };
    
    listen-on { any; };
    listen-on-v6 { any; };
    
    allow-transfer { none; };
    
    forwarders {
        8.8.8.8;
        8.8.4.4;
        1.1.1.1;
    };
    
    dnssec-validation auto;
    
    auth-nxdomain no;
};
EOF
    
    # Configure named.conf.local for zone includes
    if [ ! -f "$BIND_DIR/named.conf.local" ]; then
        cat > "$BIND_DIR/named.conf.local" <<EOF
// Local DNS zones
include "$BIND_DIR/named.conf.zones";
EOF
    fi
    
    # Create zones configuration file
    touch "$BIND_DIR/named.conf.zones"
    
    # Set permissions
    chown -R bind:bind "$ZONES_DIR" 2>/dev/null || chown -R named:named "$ZONES_DIR"
    chmod 755 "$ZONES_DIR"
    
    # Restart BIND
    systemctl enable bind9 2>/dev/null || systemctl enable named
    systemctl restart bind9 2>/dev/null || systemctl restart named
    
    echo -e "${GREEN}BIND9 setup complete${NC}"
    echo -e "${YELLOW}Server IP:${NC} $SERVER_IP"
    echo -e "${YELLOW}Config:${NC} $BIND_DIR/named.conf.options"
    echo -e "${YELLOW}Zones:${NC} $ZONES_DIR"
}

# Add DNS zone
add_zone() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    ZONE_FILE="$ZONES_DIR/db.$domain"
    
    if [ -f "$ZONE_FILE" ]; then
        echo -e "${RED}Zone for $domain already exists${NC}"
        exit 1
    fi
    
    # Get server info
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_HOSTNAME=$(hostname -f)
    
    echo -e "${GREEN}Creating DNS zone for: $domain${NC}"
    
    # Get NS and admin email
    read -p "Enter nameserver hostname [$SERVER_HOSTNAME]: " NS_HOST
    NS_HOST=${NS_HOST:-$SERVER_HOSTNAME}
    
    read -p "Enter admin email [admin@$domain]: " ADMIN_EMAIL
    ADMIN_EMAIL=${ADMIN_EMAIL:-admin@$domain}
    ADMIN_EMAIL=$(echo $ADMIN_EMAIL | sed 's/@/./g')
    
    # Create zone file
    SERIAL=$(date +%Y%m%d01)
    
    cat > "$ZONE_FILE" <<EOF
\$TTL 86400
@   IN  SOA $NS_HOST. $ADMIN_EMAIL. (
        $SERIAL ; Serial
        3600       ; Refresh
        1800       ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

; Name servers
@       IN  NS      $NS_HOST.

; A records
@       IN  A       $SERVER_IP
www     IN  A       $SERVER_IP

; Mail server (optional)
; @       IN  MX  10  mail.$domain.
; mail    IN  A       $SERVER_IP
EOF
    
    # Set permissions
    chown bind:bind "$ZONE_FILE" 2>/dev/null || chown named:named "$ZONE_FILE"
    chmod 644 "$ZONE_FILE"
    
    # Add zone to named.conf.zones
    cat >> "$BIND_DIR/named.conf.zones" <<EOF

zone "$domain" {
    type master;
    file "$ZONE_FILE";
    allow-update { none; };
};
EOF
    
    # Check configuration
    named-checkzone $domain "$ZONE_FILE"
    named-checkconf
    
    # Reload BIND
    systemctl reload bind9 2>/dev/null || systemctl reload named
    
    echo -e "${GREEN}DNS zone created successfully${NC}"
    echo -e "${YELLOW}Zone file:${NC} $ZONE_FILE"
    echo -e "${YELLOW}Nameserver:${NC} $NS_HOST"
    echo ""
    echo -e "${YELLOW}Configure your domain registrar with:${NC}"
    echo "  Nameserver: $NS_HOST ($SERVER_IP)"
}

# Remove DNS zone
remove_zone() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    ZONE_FILE="$ZONES_DIR/db.$domain"
    
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}Zone for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${RED}WARNING: This will delete the DNS zone for $domain${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Backup zone file
    BACKUP_DIR="/root/dns_backups"
    mkdir -p "$BACKUP_DIR"
    cp "$ZONE_FILE" "$BACKUP_DIR/db.${domain}_$(date +%Y%m%d_%H%M%S)"
    
    # Remove zone file
    rm -f "$ZONE_FILE"
    
    # Remove from named.conf.zones
    sed -i "/zone \"$domain\"/,/^}/d" "$BIND_DIR/named.conf.zones"
    
    # Reload BIND
    systemctl reload bind9 2>/dev/null || systemctl reload named
    
    echo -e "${GREEN}DNS zone removed${NC}"
    echo -e "${YELLOW}Backup saved to: $BACKUP_DIR${NC}"
}

# Add DNS record
add_record() {
    local domain=$1
    local type=$2
    local value=$3
    
    if [ -z "$domain" ] || [ -z "$type" ] || [ -z "$value" ]; then
        echo -e "${RED}Missing parameters${NC}"
        usage
    fi
    
    ZONE_FILE="$ZONES_DIR/db.$domain"
    
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}Zone for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Adding $type record to $domain${NC}"
    
    # Get record name
    read -p "Enter record name (or @ for root): " RECORD_NAME
    RECORD_NAME=${RECORD_NAME:-@}
    
    # Increment serial number
    CURRENT_SERIAL=$(grep "Serial" "$ZONE_FILE" | awk '{print $1}')
    NEW_SERIAL=$((CURRENT_SERIAL + 1))
    sed -i "s/$CURRENT_SERIAL/$NEW_SERIAL/" "$ZONE_FILE"
    
    # Add record based on type
    case $type in
        A|AAAA)
            echo "$RECORD_NAME    IN  $type    $value" >> "$ZONE_FILE"
            ;;
        CNAME)
            echo "$RECORD_NAME    IN  CNAME   $value" >> "$ZONE_FILE"
            ;;
        MX)
            read -p "Enter priority [10]: " PRIORITY
            PRIORITY=${PRIORITY:-10}
            echo "$RECORD_NAME    IN  MX  $PRIORITY  $value" >> "$ZONE_FILE"
            ;;
        TXT)
            echo "$RECORD_NAME    IN  TXT    \"$value\"" >> "$ZONE_FILE"
            ;;
        NS)
            echo "$RECORD_NAME    IN  NS     $value" >> "$ZONE_FILE"
            ;;
        *)
            echo -e "${RED}Unsupported record type: $type${NC}"
            exit 1
            ;;
    esac
    
    # Check zone file
    if named-checkzone $domain "$ZONE_FILE" > /dev/null 2>&1; then
        # Reload BIND
        systemctl reload bind9 2>/dev/null || systemctl reload named
        echo -e "${GREEN}DNS record added successfully${NC}"
    else
        echo -e "${RED}Zone file validation failed${NC}"
        named-checkzone $domain "$ZONE_FILE"
        exit 1
    fi
}

# Remove DNS record
remove_record() {
    local domain=$1
    local type=$2
    
    if [ -z "$domain" ] || [ -z "$type" ]; then
        echo -e "${RED}Missing parameters${NC}"
        usage
    fi
    
    ZONE_FILE="$ZONES_DIR/db.$domain"
    
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}Zone for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Records of type $type in $domain:${NC}"
    grep -n "IN  $type" "$ZONE_FILE" | cat -n
    
    read -p "Enter line number to remove: " LINE_NUM
    
    if [ -z "$LINE_NUM" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Backup
    cp "$ZONE_FILE" "${ZONE_FILE}.backup"
    
    # Get actual line number from grep output
    ACTUAL_LINE=$(grep -n "IN  $type" "$ZONE_FILE" | sed -n "${LINE_NUM}p" | cut -d: -f1)
    
    # Remove line
    sed -i "${ACTUAL_LINE}d" "$ZONE_FILE"
    
    # Increment serial
    CURRENT_SERIAL=$(grep "Serial" "$ZONE_FILE" | awk '{print $1}')
    NEW_SERIAL=$((CURRENT_SERIAL + 1))
    sed -i "s/$CURRENT_SERIAL/$NEW_SERIAL/" "$ZONE_FILE"
    
    # Check and reload
    if named-checkzone $domain "$ZONE_FILE" > /dev/null 2>&1; then
        systemctl reload bind9 2>/dev/null || systemctl reload named
        echo -e "${GREEN}DNS record removed${NC}"
    else
        mv "${ZONE_FILE}.backup" "$ZONE_FILE"
        echo -e "${RED}Failed to update zone file${NC}"
        exit 1
    fi
}

# List all zones
list_zones() {
    echo -e "${GREEN}=== DNS Zones ===${NC}"
    echo ""
    
    if [ ! -d "$ZONES_DIR" ] || [ -z "$(ls -A $ZONES_DIR 2>/dev/null)" ]; then
        echo -e "${YELLOW}No DNS zones configured${NC}"
        exit 0
    fi
    
    for zone in $ZONES_DIR/db.*; do
        if [ -f "$zone" ]; then
            domain=$(basename "$zone" | sed 's/^db\.//')
            echo -e "${YELLOW}Zone:${NC} $domain"
            echo -e "${YELLOW}File:${NC} $zone"
            
            # Show records
            echo "Records:"
            grep -E "IN\s+(A|AAAA|CNAME|MX|TXT|NS)" "$zone" | grep -v "^;" | sed 's/^/  /'
            echo ""
        fi
    done
}

# Check zone configuration
check_zone() {
    local domain=$1
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required${NC}"
        usage
    fi
    
    ZONE_FILE="$ZONES_DIR/db.$domain"
    
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}Zone for $domain does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Checking DNS Zone: $domain ===${NC}"
    echo ""
    
    # Check zone file syntax
    echo -e "${YELLOW}Zone file syntax check:${NC}"
    named-checkzone $domain "$ZONE_FILE"
    
    echo ""
    echo -e "${YELLOW}Zone file content:${NC}"
    cat "$ZONE_FILE"
    
    echo ""
    echo -e "${YELLOW}DNS queries:${NC}"
    dig @localhost $domain +short
}

# Main logic
case $ACTION in
    setup)
        setup_bind
        ;;
    add-zone)
        add_zone $DOMAIN
        ;;
    remove-zone)
        remove_zone $DOMAIN
        ;;
    add-record)
        add_record $DOMAIN $RECORD_TYPE "$RECORD_VALUE"
        ;;
    remove-record)
        remove_record $DOMAIN $RECORD_TYPE
        ;;
    list)
        list_zones
        ;;
    check)
        check_zone $DOMAIN
        ;;
    *)
        usage
        ;;
esac