#!/bin/bash
# Disk Quota Management Script
# Usage: ./manage-quota.sh [setup|set|remove|report] [username] [soft_limit] [hard_limit]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACTION=$1
USERNAME=$2
SOFT_LIMIT=$3
HARD_LIMIT=$4

usage() {
    echo "Usage: $0 [setup|set|remove|report|check] [username] [soft_limit] [hard_limit]"
    echo ""
    echo "Actions:"
    echo "  setup                         - Setup quota system"
    echo "  set <user> <soft> <hard>     - Set quota (in MB)"
    echo "  remove <user>                - Remove quota"
    echo "  report                       - Show all quotas"
    echo "  check <user>                 - Check user quota"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 set john 5000 6000        - 5GB soft, 6GB hard limit"
    echo "  $0 check john"
    exit 1
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Setup quota system
setup_quota() {
    echo -e "${GREEN}=== Setting up Quota System ===${NC}"
    
    # Detect filesystem and mount point
    MOUNT_POINT=$(df /home | tail -1 | awk '{print $6}')
    DEVICE=$(df /home | tail -1 | awk '{print $1}')
    
    echo -e "${YELLOW}Mount point:${NC} $MOUNT_POINT"
    echo -e "${YELLOW}Device:${NC} $DEVICE"
    
    # Backup fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d)
    
    # Check if quota is already enabled
    if grep -q "usrquota" /etc/fstab && grep -q "$MOUNT_POINT" /etc/fstab; then
        echo -e "${YELLOW}Quota options already exist in fstab${NC}"
    else
        # Add quota options to fstab
        sed -i "s|\($DEVICE.*$MOUNT_POINT.*defaults\)|\1,usrquota,grpquota|" /etc/fstab
        echo -e "${GREEN}Updated /etc/fstab with quota options${NC}"
    fi
    
    # Remount filesystem
    echo -e "${YELLOW}Remounting filesystem...${NC}"
    mount -o remount $MOUNT_POINT
    
    # Create quota files
    echo -e "${YELLOW}Creating quota files...${NC}"
    quotacheck -cugm $MOUNT_POINT 2>/dev/null || quotacheck -avugm
    
    # Enable quotas
    echo -e "${YELLOW}Enabling quotas...${NC}"
    quotaon $MOUNT_POINT 2>/dev/null || quotaon -avug
    
    # Create quota management directory
    mkdir -p /var/log/quota
    
    # Create quota check script
    cat > /usr/local/bin/quota-check-all <<'SCRIPT_EOF'
#!/bin/bash
echo "=== Disk Quota Report ==="
echo "Generated: $(date)"
echo ""
repquota -a
SCRIPT_EOF
    
    chmod +x /usr/local/bin/quota-check-all
    
    # Create cron job for quota reports
    CRON_CMD="0 0 * * * /usr/local/bin/quota-check-all > /var/log/quota/report-\$(date +\%Y\%m\%d).txt 2>&1"
    (crontab -l 2>/dev/null | grep -v "quota-check-all"; echo "$CRON_CMD") | crontab -
    
    echo -e "${GREEN}Quota system setup complete${NC}"
    echo -e "${YELLOW}Daily reports will be saved to /var/log/quota/${NC}"
}

# Set user quota
set_quota() {
    local username=$1
    local soft_mb=$2
    local hard_mb=$3
    
    if [ -z "$username" ] || [ -z "$soft_mb" ] || [ -z "$hard_mb" ]; then
        echo -e "${RED}Missing parameters${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    # Convert MB to blocks (1 block = 1KB)
    SOFT_BLOCKS=$((soft_mb * 1024))
    HARD_BLOCKS=$((hard_mb * 1024))
    
    # Set quota
    echo -e "${YELLOW}Setting quota for $username...${NC}"
    setquota -u $username $SOFT_BLOCKS $HARD_BLOCKS 0 0 /home/$username
    
    echo -e "${GREEN}Quota set successfully${NC}"
    echo -e "${YELLOW}Soft limit:${NC} ${soft_mb}MB (${SOFT_BLOCKS} blocks)"
    echo -e "${YELLOW}Hard limit:${NC} ${hard_mb}MB (${HARD_BLOCKS} blocks)"
    
    # Show current usage
    echo ""
    echo -e "${YELLOW}Current usage:${NC}"
    quota -vs $username
}

# Remove user quota
remove_quota() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Removing quota for $username...${NC}"
    setquota -u $username 0 0 0 0 /home
    
    echo -e "${GREEN}Quota removed for $username${NC}"
}

# Show quota report
quota_report() {
    echo -e "${GREEN}=== Disk Quota Report ===${NC}"
    echo ""
    
    # Overall quota status
    repquota -a
    
    echo ""
    echo -e "${GREEN}=== Users exceeding quota ===${NC}"
    repquota -a | grep -E "^\s*[a-zA-Z]" | awk '$3 > 0 && $3 >= $4 {print $0}'
    
    echo ""
    echo -e "${GREEN}=== Quota summary ===${NC}"
    echo -e "${YELLOW}Total users with quota:${NC} $(repquota -a | grep -E "^\s*[a-zA-Z]" | wc -l)"
    echo -e "${YELLOW}Users over soft limit:${NC} $(repquota -a | grep -E "^\s*[a-zA-Z]" | awk '$3 >= $4 && $4 > 0' | wc -l)"
    echo -e "${YELLOW}Users over hard limit:${NC} $(repquota -a | grep -E "^\s*[a-zA-Z]" | awk '$3 >= $5 && $5 > 0' | wc -l)"
}

# Check user quota
check_quota() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Username required${NC}"
        usage
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Quota Information: $username ===${NC}"
    echo ""
    
    # Show quota
    quota -vs $username
    
    # Get quota values
    QUOTA_INFO=$(quota -w $username 2>/dev/null | tail -1)
    
    if [ -n "$QUOTA_INFO" ]; then
        USED=$(echo $QUOTA_INFO | awk '{print $2}')
        SOFT=$(echo $QUOTA_INFO | awk '{print $3}')
        HARD=$(echo $QUOTA_INFO | awk '{print $4}')
        
        echo ""
        if [ "$SOFT" != "0" ]; then
            USED_NUM=$(echo $USED | sed 's/[^0-9]//g')
            SOFT_NUM=$(echo $SOFT | sed 's/[^0-9]//g')
            HARD_NUM=$(echo $HARD | sed 's/[^0-9]//g')
            
            if [ -n "$USED_NUM" ] && [ -n "$SOFT_NUM" ] && [ "$SOFT_NUM" -gt 0 ]; then
                PERCENT=$((USED_NUM * 100 / SOFT_NUM))
                echo -e "${YELLOW}Usage:${NC} ${PERCENT}% of soft limit"
                
                if [ $PERCENT -ge 90 ]; then
                    echo -e "${RED}WARNING: Approaching quota limit!${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}No quota set for this user${NC}"
        fi
    fi
    
    # Show disk usage of home directory
    echo ""
    echo -e "${YELLOW}Home directory usage:${NC}"
    du -sh /home/$username 2>/dev/null || echo "Unable to calculate"
}

# Main logic
case $ACTION in
    setup)
        setup_quota
        ;;
    set)
        set_quota $USERNAME $SOFT_LIMIT $HARD_LIMIT
        ;;
    remove)
        remove_quota $USERNAME
        ;;
    report)
        quota_report
        ;;
    check)
        check_quota $USERNAME
        ;;
    *)
        usage
        ;;
esac