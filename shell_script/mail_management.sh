#!/bin/bash
# Mail Server Management Script (Postfix/Dovecot setup)
# Usage: ./mail_management.sh [setup|add-user|remove-user|list-users|info]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ACTION=$1
PARAM1=$2
PARAM2=$3

usage() {
    echo "Usage: $0 [action] [parameters]"
    echo ""
    echo "Actions:"
    echo "  setup <domain>               - Install and configure Postfix and Dovecot for a domain"
    echo "  add-user <email>             - Add a new mail user"
    echo "  remove-user <email>          - Remove a mail user"
    echo "  list-users                   - List all mail users"
    echo "  info <email>                 - Show info about a mail user"
    echo ""
    echo "Examples:"
    echo "  $0 setup example.com"
    echo "  $0 add-user admin@example.com"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

setup_mail_server() {
    local domain=$1
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain required for setup${NC}"
        usage
    fi

    echo -e "${YELLOW}Setting up mail server (Postfix & Dovecot) for $domain...${NC}"
    
    # Pre-seed postfix choices
    echo "postfix postfix/mailname string $domain" | debconf-set-selections
    echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
    
    # Install Postfix and Dovecot
    apt-get update
    apt-get install -y postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd mailutils

    # Configure Postfix
    postconf -e "mydomain = $domain"
    postconf -e "myorigin = \$mydomain"
    postconf -e "mydestination = localhost.\$mydomain, localhost, \$mydomain"
    postconf -e "home_mailbox = Maildir/"
    
    # Postfix SMTP Auth setup
    postconf -e "smtpd_sasl_type = dovecot"
    postconf -e "smtpd_sasl_path = private/auth"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"
    
    # Configure Dovecot
    # Update mail location
    sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
    # Setup postfix auth mechanism in dovecot
    if ! grep -q "unix_listener /var/spool/postfix/private/auth" /etc/dovecot/conf.d/10-master.conf; then
        cat <<EOF >> /etc/dovecot/conf.d/10-master.conf
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF
    fi

    systemctl restart postfix dovecot
    systemctl enable postfix dovecot
    
    echo -e "${GREEN}Mail server setup complete for $domain!${NC}"
    echo -e "${YELLOW}Remember to add MX records for $domain pointing to your server IP.${NC}"
}

add_mail_user() {
    local email=$1
    if [ -z "$email" ]; then
        echo -e "${RED}Email required${NC}"
        usage
    fi
    local username="${email%@*}"
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User $username already exists${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Adding mail user: $email${NC}"
    useradd -m -s /sbin/nologin "$username"
    
    echo -e "${YELLOW}Enter password for $email:${NC}"
    passwd "$username"
    
    echo -e "${GREEN}Mail user $email added successfully!${NC}"
}

remove_mail_user() {
    local email=$1
    if [ -z "$email" ]; then
        echo -e "${RED}Email required${NC}"
        usage
    fi
    local username="${email%@*}"
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi

    echo -e "${RED}WARNING: This will permanently delete mail user: $email and all their mail!${NC}"
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    userdel -r "$username"
    echo -e "${GREEN}User $email deleted successfully!${NC}"
}

list_mail_users() {
    echo -e "${GREEN}=== Mail Users (System users with /sbin/nologin) ===${NC}"
    awk -F: '$7 == "/sbin/nologin" {print $1}' /etc/passwd
}

info_mail_user() {
    local email=$1
    if [ -z "$email" ]; then
        echo -e "${RED}Email required${NC}"
        usage
    fi
    local username="${email%@*}"
    
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User $username does not exist${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}=== Info for $email ===${NC}"
    echo -e "Maildir Location: /home/$username/Maildir"
    if [ -d "/home/$username/Maildir" ]; then
        SIZE=$(du -sh "/home/$username/Maildir" 2>/dev/null | cut -f1)
        echo -e "Mailbox Size: ${GREEN}$SIZE${NC}"
    else
        echo -e "Mailbox Size: ${YELLOW}No mail received yet${NC}"
    fi
}

# Main logic
case $ACTION in
    setup)
        setup_mail_server "$PARAM1"
        ;;
    add-user)
        add_mail_user "$PARAM1"
        ;;
    remove-user)
        remove_mail_user "$PARAM1"
        ;;
    list-users)
        list_mail_users
        ;;
    info)
        info_mail_user "$PARAM1"
        ;;
    *)
        usage
        ;;
esac
