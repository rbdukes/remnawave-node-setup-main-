#!/bin/bash
set -euo pipefail

# ============================================================
#   Remnawave Node Setup Script with WARP Integration
#   heatfm.cc Infrastructure
#   Ultimate one-click installation
# ============================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- DEFAULTS ---
DEFAULT_NODE_PORT="3389"
DEFAULT_PANEL_URL="https://panel.heatfm.cc"
DEFAULT_DOMAIN_SUFFIX="heatfm.cc"

# --- ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ This script must be run as root. Use: sudo bash $0${NC}"
    exit 1
fi

# --- OS CHECK ---
if ! grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Warning: This script is designed for Ubuntu/Debian. Proceed with caution.${NC}"
    sleep 3
fi

clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     Remnawave Node Setup Script          ║"
echo "  ║     heatfm.cc Infrastructure             ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# --- GATHER INFO ---
# ============================================================
echo -e "${YELLOW}${BOLD}Step 1 — Node Information${NC}"
echo ""

# Country name
while true; do
    read -rp "$(echo -e "${BLUE}Enter country name [e.g. Netherlands, USA, Finland]: ${NC}")" COUNTRY
    if [ -n "$COUNTRY" ]; then break; fi
    echo -e "${RED}Country name is required!${NC}"
done

# Subdomain
COUNTRY_LOWER=$(echo "$COUNTRY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
DEFAULT_SUBDOMAIN="${COUNTRY_LOWER}.${DEFAULT_DOMAIN_SUFFIX}"
read -rp "$(echo -e "${BLUE}Node subdomain [default: ${DEFAULT_SUBDOMAIN}]: ${NC}")" SUBDOMAIN
SUBDOMAIN=${SUBDOMAIN:-$DEFAULT_SUBDOMAIN}

# Node Port
read -rp "$(echo -e "${BLUE}Node API port [default: ${DEFAULT_NODE_PORT}]: ${NC}")" NODE_PORT
NODE_PORT=${NODE_PORT:-$DEFAULT_NODE_PORT}
# Validate port is a number
if ! [[ "$NODE_PORT" =~ ^[0-9]+$ ]] || [ "$NODE_PORT" -lt 1 ] || [ "$NODE_PORT" -gt 65535 ]; then
    echo -e "${RED}Invalid port. Using default: ${DEFAULT_NODE_PORT}${NC}"
    NODE_PORT=$DEFAULT_NODE_PORT
fi

# Panel URL
read -rp "$(echo -e "${BLUE}Panel URL [default: ${DEFAULT_PANEL_URL}]: ${NC}")" PANEL_URL
PANEL_URL=${PANEL_URL:-$DEFAULT_PANEL_URL}

# WARP Installation
echo ""
read -rp "$(echo -e "${BLUE}Do you want to install Cloudflare WARP? (recommended) [Y/n]: ${NC}")" INSTALL_WARP
INSTALL_WARP=${INSTALL_WARP:-Y}

# Secret Key
echo ""
echo -e "${YELLOW}${BOLD}Step 2 — Secret Key${NC}"
echo -e "${CYAN}Go to your Remnawave panel → Nodes → Add Node${NC}"
echo -e "${CYAN}Fill in the node details and copy the SECRET_KEY${NC}"
echo ""
while true; do
    read -rp "$(echo -e "${BLUE}Paste the SECRET_KEY from the panel: ${NC}")" SECRET_KEY
    if [ -n "$SECRET_KEY" ]; then break; fi
    echo -e "${RED}Secret key is required!${NC}"
done

# Confirm
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Setup Summary${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Country    : ${BOLD}$COUNTRY${NC}"
echo -e "  Subdomain  : ${BOLD}$SUBDOMAIN${NC}"
echo -e "  Node Port  : ${BOLD}$NODE_PORT${NC}"
echo -e "  Panel URL  : ${BOLD}$PANEL_URL${NC}"
echo -e "  WARP       : ${BOLD}$([ "$INSTALL_WARP" =~ ^[Yy]$ ] && echo "Yes" || echo "No")${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -rp "$(echo -e "${YELLOW}Proceed with installation? [y/N]: ${NC}")" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${NC}"
    exit 0
fi

# ============================================================
# --- HELPER ---
# ============================================================
print_step() { echo -e "\n${CYAN}${BOLD}[$1] $2...${NC}"; }
print_ok()   { echo -e "${GREEN}✅ $1${NC}"; }
print_err()  { echo -e "${RED}❌ $1${NC}"; }

# ============================================================
# [1/8] SYSTEM UPDATE
# ============================================================
print_step "1/8" "Updating system packages"

# Wait for any existing apt lock to release
echo -e "${YELLOW}Waiting for package manager to be available...${NC}"
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 2
done

# Kill unattended-upgrades if still running
systemctl stop unattended-upgrades 2>/dev/null || true
killall unattended-upgr 2>/dev/null || true
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
dpkg --configure -a 2>/dev/null || true

apt update -y
DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Disable auto-updates permanently (prevents future lock issues)
systemctl disable unattended-upgrades 2>/dev/null || true
systemctl stop unattended-upgrades 2>/dev/null || true

print_ok "System updated and auto-upgrades disabled"

# ============================================================
# [2/8] SET HOSTNAME
# ============================================================
print_step "2/8" "Setting hostname"
hostnamectl set-hostname "${COUNTRY_LOWER}-node"
print_ok "Hostname set to: ${COUNTRY_LOWER}-node"

# ============================================================
# [3/8] FIREWALL
# ============================================================
print_step "3/8" "Configuring firewall (UFW)"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "${NODE_PORT}"/tcp
ufw allow 61000/tcp
ufw --force enable
ufw reload
print_ok "Firewall configured (22, 80, 443, ${NODE_PORT}, 61000)"

# ============================================================
# [4/8] INSTALL DOCKER
# ============================================================
print_step "4/8" "Installing Docker"
if command -v docker &>/dev/null; then
    print_ok "Docker already installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    print_ok "Docker installed"
fi

# Verify docker works
if ! docker info &>/dev/null; then
    print_err "Docker failed to start. Aborting."
    exit 1
fi

# ============================================================
# [5/8] CONFIGURE REMNANODE
# ============================================================
print_step "5/8" "Creating Remnawave Node configuration"
mkdir -p /opt/remnanode

cat > /opt/remnanode/.env << EOF
### NODE ###
NODE_PORT=${NODE_PORT}

### XRAY ###
SECRET_KEY=${SECRET_KEY}

### Internal port
XTLS_API_PORT=61000
EOF

cat > /opt/remnanode/docker-compose.yml << 'EOF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: ghcr.io/remnawave/node:latest
    env_file:
      - .env
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
EOF

print_ok "Configuration created at /opt/remnanode/"

# ============================================================
# [6/8] START REMNANODE
# ============================================================
print_step "6/8" "Starting Remnawave Node"
cd /opt/remnanode
docker compose pull
docker compose up -d

# Wait and verify
sleep 6
if docker ps | grep -q "remnanode"; then
    print_ok "Remnawave Node is running"
    docker compose logs --tail=15
else
    print_err "Container failed to start. Logs:"
    docker compose logs --tail=30
    exit 1
fi

# ============================================================
# [7/8] GET PUBLIC IP
# ============================================================
print_step "7/8" "Detecting public IP"
IPV4=$(curl -4 -s --max-time 10 ifconfig.me || curl -4 -s --max-time 10 api.ipify.org || echo "UNKNOWN")
print_ok "Public IP: $IPV4"

# ============================================================
# [8/8] INSTALL WARP (OPTIONAL)
# ============================================================
if [[ "$INSTALL_WARP" =~ ^[Yy]$ ]]; then
    print_step "8/8" "Installing and configuring Cloudflare WARP"
    
    # Create WARP setup script
    cat > /root/warp-setup.sh << 'EOF'
#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================${NC}"
echo -e "${GREEN}Complete Remnant Network Node WARP Setup & Fix Script${NC}"
echo -e "${BLUE}============================================================${NC}"

# Function to print status
print_ok() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_err() {
    echo -e "${RED}✗ $1${NC}"
}

# Step 1: Clean up any existing WARP setup
print_info "Cleaning up existing WARP installation..."
systemctl stop wg-quick@wg0 2>/dev/null || true
systemctl disable wg-quick@wg0 2>/dev/null || true
apt remove -y cloudflare-warp 2>/dev/null || true
rm -f /etc/wireguard/wg0.conf
ip rule del from all lookup warp priority 5000 2>/dev/null || true
ip rule del from all sport 22 lookup main priority 4000 2>/dev/null || true
ip rule del to all dport 22 lookup main priority 4000 2>/dev/null || true
print_ok "Cleaned up old WARP configuration"

# Step 2: Fix hosts file and DNS
print_info "Setting up system configuration..."
HOSTNAME=$(hostname)
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.0.1 $HOSTNAME" >> /etc/hosts
apt install -y systemd-resolved 2>/dev/null
systemctl enable --now systemd-resolved
if [ -L /etc/resolv.conf ]; then
    rm /etc/resolv.conf
fi
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf
print_ok "System configuration fixed"

# Step 3: Install dependencies
print_info "Installing dependencies..."
apt update
apt install -y wireguard-tools curl iproute2 wget gnupg2 apt-transport-https
print_ok "Dependencies installed"

# Step 4: Download and install wgcf
print_info "Installing wgcf..."
WGCF_VER="v2.2.22"
wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VER}/wgcf_${WGCF_VER#v}_linux_amd64"
chmod +x /usr/local/bin/wgcf
print_ok "wgcf ${WGCF_VER} installed"

# Step 5: Register and generate config
print_info "Registering WARP account..."
WARP_TMP=$(mktemp -d)
cd "$WARP_TMP"
wgcf register --accept-tos
wgcf generate
print_ok "WARP configuration generated"

# Step 6: Configure for full tunnel
print_info "Configuring WARP profile..."
sed -i 's|AllowedIPs = .*|AllowedIPs = 0.0.0.0/0|' wgcf-profile.conf

# Add Table = off so we can manage routing ourselves
if ! grep -q "^Table" wgcf-profile.conf; then
    sed -i '/^\[Interface\]/a Table = off' wgcf-profile.conf
else
    sed -i 's/^Table = .*/Table = off/' wgcf-profile.conf
fi

# Deploy config
cp wgcf-profile.conf /etc/wireguard/wg0.conf
cd /
rm -rf "$WARP_TMP"
print_ok "WARP profile configured and deployed"

# Step 7: Configure UFW to allow outbound traffic
print_info "Configuring firewall rules..."
ufw allow out on eth0
ufw allow out on wg0
ufw allow in on wg0
ufw allow out to any port 53 proto udp # DNS
ufw allow out to any port 80 proto tcp # HTTP
ufw allow out to any port 443 proto tcp # HTTPS
ufw allow out to 1.1.1.1
ufw allow out to 8.8.8.8
ufw reload
print_ok "Firewall configured to allow WARP traffic"

# Step 8: Enable and start WARP
print_info "Starting WARP service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
