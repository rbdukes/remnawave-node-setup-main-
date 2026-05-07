#!/bin/bash

# ============================================================
#   Remnawave Node Setup Script
#   Based on heatfm.cc setup
#   Run this on a FRESH VPS to add it as a new node
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

clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     Remnawave Node Setup Script          ║"
echo "  ║     heatfm.cc Infrastructure            ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- GATHER INFO ---
echo -e "${YELLOW}${BOLD}Step 1 — Node Information${NC}"
echo ""

# Country name
read -p "$(echo -e ${BLUE}Enter country name [e.g. Netherlands, USA, Finland]: ${NC})" COUNTRY
if [ -z "$COUNTRY" ]; then
    echo -e "${RED}Country name is required!${NC}"
    exit 1
fi

# Subdomain
COUNTRY_LOWER=$(echo "$COUNTRY" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
DEFAULT_SUBDOMAIN="${COUNTRY_LOWER}.${DEFAULT_DOMAIN_SUFFIX}"
read -p "$(echo -e ${BLUE}Node subdomain [default: ${DEFAULT_SUBDOMAIN}]: ${NC})" SUBDOMAIN
SUBDOMAIN=${SUBDOMAIN:-$DEFAULT_SUBDOMAIN}

# Node Port
read -p "$(echo -e ${BLUE}Node API port [default: ${DEFAULT_NODE_PORT}]: ${NC})" NODE_PORT
NODE_PORT=${NODE_PORT:-$DEFAULT_NODE_PORT}

# Panel URL
read -p "$(echo -e ${BLUE}Panel URL [default: ${DEFAULT_PANEL_URL}]: ${NC})" PANEL_URL
PANEL_URL=${PANEL_URL:-$DEFAULT_PANEL_URL}

# Secret Key
echo ""
echo -e "${YELLOW}${BOLD}Step 2 — Secret Key${NC}"
echo -e "${CYAN}Go to your Remnawave panel → Nodes → Add Node${NC}"
echo -e "${CYAN}Fill in the node details and copy the SECRET_KEY${NC}"
echo ""
read -p "$(echo -e ${BLUE}Paste the SECRET_KEY from the panel: ${NC})" SECRET_KEY
if [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}Secret key is required!${NC}"
    exit 1
fi

# Confirm
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  Setup Summary${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Country    : ${BOLD}$COUNTRY${NC}"
echo -e "  Subdomain  : ${BOLD}$SUBDOMAIN${NC}"
echo -e "  Node Port  : ${BOLD}$NODE_PORT${NC}"
echo -e "  Panel URL  : ${BOLD}$PANEL_URL${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -p "$(echo -e ${YELLOW}Proceed with installation? [y/N]: ${NC})" CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation cancelled.${NC}"
    exit 0
fi

# --- SYSTEM UPDATE ---
echo ""
echo -e "${CYAN}${BOLD}[1/6] Updating system...${NC}"
apt update -y && apt upgrade -y
echo -e "${GREEN}✅ System updated${NC}"

# --- OPEN FIREWALL PORTS ---
echo ""
echo -e "${CYAN}${BOLD}[2/6] Configuring firewall...${NC}"
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 80/tcp
ufw allow ${NODE_PORT}/tcp
ufw --force enable
ufw reload
echo -e "${GREEN}✅ Firewall configured (22, 80, 443, ${NODE_PORT})${NC}"

# --- INSTALL DOCKER ---
echo ""
echo -e "${CYAN}${BOLD}[3/6] Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    echo -e "${GREEN}✅ Docker installed${NC}"
else
    echo -e "${GREEN}✅ Docker already installed${NC}"
fi

# --- CREATE REMNANODE ENV ---
echo ""
echo -e "${CYAN}${BOLD}[4/6] Creating remnanode configuration...${NC}"
mkdir -p /opt/remnanode

cat > /opt/remnanode/.env << EOF
SECRET_KEY=${SECRET_KEY}
NODE_PORT=${NODE_PORT}
EOF

echo -e "${GREEN}✅ Configuration created${NC}"

# --- CREATE DOCKER COMPOSE ---
# ✅ FIXED: Removed volumes section that caused mount errors
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

echo -e "${GREEN}✅ Docker compose created${NC}"

# --- START REMNANODE ---
echo ""
echo -e "${CYAN}${BOLD}[5/6] Starting Remnawave Node...${NC}"
cd /opt/remnanode
docker compose pull
docker compose up -d
echo -e "${GREEN}✅ Remnawave Node started${NC}"

# --- FINAL STATUS CHECK ---
echo ""
echo -e "${CYAN}${BOLD}[6/6] Checking node status...${NC}"
sleep 5
docker compose logs --tail=20

# --- GET IPV4 ---
IPV4=$(curl -4 -s ifconfig.me)

# --- DONE ---
echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${BOLD}  ✅ Node Setup Complete!${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}${BOLD}Next steps in the Remnawave Panel:${NC}"
echo -e "  1. Go to ${BOLD}Nodes → Management${NC}"
echo -e "  2. Find your new ${BOLD}$COUNTRY${NC} node"
echo -e "  3. Click ${BOLD}Link Inbound${NC} → select ${BOLD}VLESS_TCP_REALITY${NC}"
echo -e "  4. Go to ${BOLD}Hosts → Add Host${NC}:"
echo -e "     - Remark   : 🌍 $COUNTRY"
echo -e "     - Address  : $SUBDOMAIN"
echo -e "     - Port     : 443"
echo -e "     - Inbound  : VLESS_TCP_REALITY"
echo -e "     - SNI      : github.com"
echo -e "     - FP       : chrome"
echo -e "     - x25519   : ON"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}DNS A Record to add:${NC}"
echo -e "  ${BOLD}$SUBDOMAIN → $IPV4${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
# ============================================================
# --- OPTIONAL: WARP INSTALLATION ---
# ============================================================
echo ""
read -p "$(echo -e ${YELLOW}Do you want to install WARP \(wg0\) on this node now? [y/N]: ${NC})" INSTALL_WARP

if [[ "$INSTALL_WARP" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}[Bonus] Installing Cloudflare WARP (Safe wg0 Mode)...${NC}"

    # 1. Install WireGuard tools
    apt install -y wireguard-tools curl resolvconf > /dev/null 2>&1

    # 2. Download wgcf binary
    echo -e "${BLUE}  - Downloading WARP generator...${NC}"
    wget -qO /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_amd64
    chmod +x /usr/local/bin/wgcf

    # 3. Register and generate config
    mkdir -p /tmp/warp-setup
    cd /tmp/warp-setup
    echo -e "${BLUE}  - Registering WARP device...${NC}"
    wgcf register --accept-tos 2>&1 | grep -v "GET"
    echo -e "${BLUE}  - Generating WireGuard config...${NC}"
    wgcf generate 2>&1 | grep -v "GET"

    # 4. Detect gateway and interface dynamically
    GW=$(ip route show | grep default | awk '{print $3}' | head -1)
    DEV=$(ip route show | grep default | awk '{print $5}' | head -1)
    SERVER_IP=$(curl -4 -s ifconfig.me)

    echo -e "${BLUE}  - Detected gateway: ${GW} on interface: ${DEV}${NC}"

    # 5. Extract keys from generated config
    PRIVKEY=$(grep PrivateKey wgcf-profile.conf | awk '{print $3}')
    ADDRESS_V4=$(grep Address wgcf-profile.conf | head -1 | awk '{print $3}')
    ADDRESS_V6=$(grep Address wgcf-profile.conf | tail -1 | awk '{print $3}')
    PUBKEY=$(grep PublicKey wgcf-profile.conf | awk '{print $3}')

    # 6. Add warp routing table if not present
    grep -q "^100 warp" /etc/iproute2/rt_tables || echo "100 warp" >> /etc/iproute2/rt_tables

    # 7. Write clean config with persistent routing
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${PRIVKEY}
Address = ${ADDRESS_V4}
Address = ${ADDRESS_V6}
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280
Table = off
PostUp = ip route add 162.159.192.1 via ${GW} dev ${DEV} || true; ip route add default dev wg0 table warp || true; ip rule add from all lookup warp priority 5000 || true; ip rule add from ${SERVER_IP} lookup main priority 4000 || true
PreDown = ip route del 162.159.192.1 via ${GW} dev ${DEV} || true; ip rule del priority 5000 || true; ip rule del priority 4000 || true; ip route flush table warp || true

[Peer]
PublicKey = ${PUBKEY}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:2408
PersistentKeepalive = 25
EOF

    # 8. Enable and start
    systemctl enable wg-quick@wg0 > /dev/null 2>&1
    systemctl start wg-quick@wg0
    sleep 5

    # 9. Cleanup
    cd /
    rm -rf /tmp/warp-setup

    # 10. Verify
    WARP_IP=$(curl -s --max-time 10 https://ipinfo.io/ip)
    WARP_ORG=$(curl -s --max-time 10 https://ipinfo.io/org)
    if echo "$WARP_ORG" | grep -qi "cloudflare"; then
        echo -e "${GREEN}✅ WARP is working! Outbound IP: ${WARP_IP} (${WARP_ORG})${NC}"
    else
        echo -e "${RED}❌ WARP may not be routing correctly. Current IP: ${WARP_IP}${NC}"
        echo -e "${YELLOW}   Run: sudo wg show — to check handshake status${NC}"
    fi
else
    echo -e "${CYAN}Skipping WARP installation.${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}All done! Exiting...${NC}"
echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
