#!/bin/bash
set -euo pipefail

# ============================================================
#   Remnawave Node Setup Script
#   heatfm.cc Infrastructure
#   Full-proof version with WARP + SSH protection
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
echo "  ║     heatfm.cc Infrastructure            ║"
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
# [1/7] SYSTEM UPDATE
# ============================================================
print_step "1/7" "Updating system packages"

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

# apt update -y
# DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Disable auto-updates permanently (prevents future lock issues)
systemctl disable unattended-upgrades 2>/dev/null || true
systemctl stop unattended-upgrades 2>/dev/null || true

print_ok "System updated and auto-upgrades disabled"

# ============================================================
# [2/7] SET HOSTNAME
# ============================================================
print_step "2/7" "Setting hostname"
hostnamectl set-hostname "${COUNTRY_LOWER}-node"
print_ok "Hostname set to: ${COUNTRY_LOWER}-node"

# ============================================================
# [3/7] FIREWALL
# ============================================================
print_step "3/7" "Configuring firewall (UFW)"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow "${NODE_PORT}"/tcp
ufw allow 61000/tcp
ufw --force enable
ufw reload
print_ok "Firewall configured (22, 80, 443, ${NODE_PORT}, 61000)"

# ============================================================
# [4/7] INSTALL DOCKER
# ============================================================
print_step "4/7" "Installing Docker"
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
# [5/7] CONFIGURE REMNANODE
# ============================================================
print_step "5/7" "Creating Remnawave Node configuration"
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
# [6/7] START REMNANODE
# ============================================================
print_step "6/7" "Starting Remnawave Node"
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
# [7/7] GET PUBLIC IP
# ============================================================
print_step "7/7" "Detecting public IP"
IPV4=$(curl -4 -s --max-time 10 ifconfig.me || curl -4 -s --max-time 10 api.ipify.org || echo "UNKNOWN")
print_ok "Public IP: $IPV4"

# ============================================================
# --- SUMMARY ---
# ============================================================
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
# --- OPTIONAL: WARP ---
# ============================================================
echo ""
read -rp "$(echo -e "${YELLOW}Do you want to install WARP (wg0) on this node now? [y/N]: ${NC}")" INSTALL_WARP

if [[ "$INSTALL_WARP" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}[Bonus] Installing Cloudflare WARP with SSH protection...${NC}"

    # 1. Install dependencies
    apt install -y wireguard-tools curl iproute2 >/dev/null 2>&1
    print_ok "WireGuard tools installed"

    # 2. Download latest wgcf binary
    echo -e "${BLUE}  - Fetching latest wgcf version...${NC}"
    WGCF_VER=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    if [ -z "$WGCF_VER" ]; then
        WGCF_VER="v2.2.22"
        echo -e "${YELLOW}  ⚠️  Could not fetch latest version, using fallback: ${WGCF_VER}${NC}"
    fi
    WGCF_VER_NUM="${WGCF_VER#v}"
    wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VER}/wgcf_${WGCF_VER_NUM}_linux_amd64"
    chmod +x /usr/local/bin/wgcf
    print_ok "wgcf ${WGCF_VER} installed"

    # 3. Register and generate config in temp dir
    WARP_TMP=$(mktemp -d)
    cd "$WARP_TMP"
    echo -e "${BLUE}  - Registering WARP device...${NC}"
    wgcf register --accept-tos 2>&1 | grep -v "GET" || true
    echo -e "${BLUE}  - Generating WireGuard config...${NC}"
    wgcf generate 2>&1 | grep -v "GET" || true

    if [ ! -f wgcf-profile.conf ]; then
        print_err "wgcf failed to generate config. Skipping WARP."
        cd /
        rm -rf "$WARP_TMP"
    else
        # 4. Set full tunnel (AllowedIPs = 0.0.0.0/0) - routing table will handle SSH exclusion
        sed -i 's|AllowedIPs = .*|AllowedIPs = 0.0.0.0/0|' wgcf-profile.conf

        # 5. Add Table = off so wg-quick does NOT modify default routes
        #    We manage routing manually below to exclude SSH port 22
        if ! grep -q "^Table" wgcf-profile.conf; then
            sed -i '/^\[Interface\]/a Table = off' wgcf-profile.conf
        else
            sed -i 's/^Table = .*/Table = off/' wgcf-profile.conf
        fi

        # 6. Deploy to system WireGuard
        cp wgcf-profile.conf /etc/wireguard/wg0.conf
        cd /
        rm -rf "$WARP_TMP"
        print_ok "WARP config deployed to /etc/wireguard/wg0.conf"

        # 7. Enable and start WARP interface
        systemctl enable wg-quick@wg0 >/dev/null 2>&1
        systemctl start wg-quick@wg0
        sleep 3

        # 8. Apply routing rules to protect SSH (port 22) from going through WARP
        echo -e "${BLUE}  - Configuring routing rules (SSH port 22 excluded from WARP)...${NC}"

        # Add custom routing table if not already present
        grep -q "^100 warp" /etc/iproute2/rt_tables || echo "100 warp" >> /etc/iproute2/rt_tables

        # Add default route for WARP table
        ip route add default dev wg0 table warp 2>/dev/null || true

        # SSH exclusion rules (priority 4000 - higher priority = evaluated first)
        ip rule add from all sport 22 lookup main priority 4000 2>/dev/null || true
        ip rule add to   all dport 22 lookup main priority 4000 2>/dev/null || true

        # Node port exclusion (panel must reach node directly, not through WARP)
        ip rule add from all sport "${NODE_PORT}" lookup main priority 4001 2>/dev/null || true
        ip rule add to   all dport "${NODE_PORT}" lookup main priority 4001 2>/dev/null || true

        # All other traffic goes through WARP (priority 5000)
        ip rule add from all lookup warp priority 5000 2>/dev/null || true

        # 9. Persist routing rules across reboots via systemd service
        cat > /etc/systemd/system/warp-routing.service << SVCEOF
[Unit]
Description=WARP custom routing rules (SSH excluded)
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c '\
    grep -q "^100 warp" /etc/iproute2/rt_tables || echo "100 warp" >> /etc/iproute2/rt_tables; \
    ip route add default dev wg0 table warp 2>/dev/null || true; \
    ip rule add from all sport 22 lookup main priority 4000 2>/dev/null || true; \
    ip rule add to   all dport 22 lookup main priority 4000 2>/dev/null || true; \
    ip rule add from all sport ${NODE_PORT} lookup main priority 4001 2>/dev/null || true; \
    ip rule add to   all dport ${NODE_PORT} lookup main priority 4001 2>/dev/null || true; \
    ip rule add from all lookup warp priority 5000 2>/dev/null || true'
ExecStop=/bin/bash -c '\
    ip rule del from all sport 22 lookup main priority 4000 2>/dev/null || true; \
    ip rule del to   all dport 22 lookup main priority 4000 2>/dev/null || true; \
    ip rule del from all sport ${NODE_PORT} lookup main priority 4001 2>/dev/null || true; \
    ip rule del to   all dport ${NODE_PORT} lookup main priority 4001 2>/dev/null || true; \
    ip rule del from all lookup warp priority 5000 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
SVCEOF

        systemctl daemon-reload
        systemctl enable warp-routing.service >/dev/null 2>&1
        print_ok "Routing rules persisted via warp-routing.service"

        # 10. Verify WARP is up
        sleep 2
        if ip a show wg0 2>/dev/null | grep -q "inet"; then
            print_ok "WARP is running on wg0"
            echo ""
            echo -e "${CYAN}WARP status:${NC}"
            wg show wg0 2>/dev/null || true
            echo ""
            echo -e "${CYAN}Active routing rules:${NC}"
            ip rule list | grep -E "main|warp" | head -10
            echo ""
            echo -e "${GREEN}✅ SSH port 22 is excluded from WARP — your SSH connection is safe.${NC}"
            echo -e "${CYAN}Note: Make sure your XRay template has outbound pointing to \"interface\": \"wg0\"${NC}"
        else
            print_err "WARP interface wg0 failed to start."
            echo -e "${YELLOW}Debug with: systemctl status wg-quick@wg0${NC}"
        fi
    fi
else
    echo -e "${CYAN}Skipping WARP installation.${NC}"
fi

# ============================================================
# --- OPTIONAL: POST-INSTALL FIXES ---
# ============================================================
echo ""
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}${BOLD}Post-Install Fixes Available:${NC}"
echo -e "${CYAN}  This will apply the following fixes:${NC}"
echo -e "  ${BOLD}Fix 1${NC} — Remove bad /etc/hosts entry (127.0.1.1 line)"
echo -e "  ${BOLD}Fix 2${NC} — Restart WARP (wg-quick@wg0) to clear DNS issues"
echo -e "  ${BOLD}Fix 3${NC} — Verify WARP is routing through Cloudflare"
echo -e "  ${BOLD}Fix 4${NC} — Verify outbound internet connectivity"
echo -e "  ${BOLD}Fix 5${NC} — Restart remnanode container to apply all changes"
echo -e "  ${BOLD}Fix 6${NC} — Show last 5 lines of remnanode logs"
echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -rp "$(echo -e "${YELLOW}Do you want to apply post-install fixes now? [y/N]: ${NC}")" APPLY_FIXES

if [[ "$APPLY_FIXES" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}[Fix] Applying post-install fixes...${NC}"

    # Write the fix script to disk so it can be re-run later if needed
    cat > /root/node-fix.sh << 'FIXEOF'
#!/bin/bash

echo "🔧 Applying post-install fixes..."

# Fix 1 — Remove bad /etc/hosts entry
HOSTNAME=$(hostname)
sed -i '/127.0.1.1/d' /etc/hosts
echo "✅ Fixed /etc/hosts (removed 127.0.1.1 entries)"

# Fix 2 — Restart WARP to fix DNS
if systemctl is-active --quiet wg-quick@wg0; then
    systemctl restart wg-quick@wg0
    sleep 3
    echo "✅ WARP restarted"
else
    echo "⚠️  WARP (wg-quick@wg0) is not active — skipping restart"
fi

# Fix 3 — Verify WARP is working
WARP_ORG=$(curl -s --max-time 10 https://ipinfo.io/org || echo "unreachable")
if echo "$WARP_ORG" | grep -qi "cloudflare"; then
    echo "✅ WARP working: $WARP_ORG"
else
    echo "⚠️  WARP check result: $WARP_ORG"
fi

# Fix 4 — Verify internet works
IP=$(curl -4 -s --max-time 10 ifconfig.me || echo "UNKNOWN")
echo "✅ Outbound IP: $IP"

# Fix 5 — Restart remnanode to apply all changes
if docker ps -a --format '{{.Names}}' | grep -q "^remnanode$"; then
    docker restart remnanode
    sleep 10
    echo "✅ Remnanode restarted"
else
    echo "⚠️  remnanode container not found — skipping restart"
fi

# Fix 6 — Final status
echo ""
echo "📋 Last 5 lines of remnanode logs:"
docker logs remnanode --tail 5 2>&1 || echo "⚠️  Could not fetch logs"

echo ""
echo "✅ All fixes applied!"
echo "💡 You can re-run these fixes anytime with: bash /root/node-fix.sh"
FIXEOF

    chmod +x /root/node-fix.sh
    print_ok "Fix script saved to /root/node-fix.sh"

    # Run it immediately
    bash /root/node-fix.sh

else
    # Still write the fix script to disk even if skipped, for later use
    cat > /root/node-fix.sh << 'FIXEOF'
#!/bin/bash

echo "🔧 Applying post-install fixes..."

# Fix 1 — Remove bad /etc/hosts entry
HOSTNAME=$(hostname)
sed -i '/127.0.1.1/d' /etc/hosts
echo "✅ Fixed /etc/hosts (removed 127.0.1.1 entries)"

# Fix 2 — Restart WARP to fix DNS
if systemctl is-active --quiet wg-quick@wg0; then
    systemctl restart wg-quick@wg0
    sleep 3
    echo "✅ WARP restarted"
else
    echo "⚠️  WARP (wg-quick@wg0) is not active — skipping restart"
fi

# Fix 3 — Verify WARP is working
WARP_ORG=$(curl -s --max-time 10 https://ipinfo.io/org || echo "unreachable")
if echo "$WARP_ORG" | grep -qi "cloudflare"; then
    echo "✅ WARP working: $WARP_ORG"
else
    echo "⚠️  WARP check result: $WARP_ORG"
fi

# Fix 4 — Verify internet works
IP=$(curl -4 -s --max-time 10 ifconfig.me || echo "UNKNOWN")
echo "✅ Outbound IP: $IP"

# Fix 5 — Restart remnanode to apply all changes
if docker ps -a --format '{{.Names}}' | grep -q "^remnanode$"; then
    docker restart remnanode
    sleep 10
    echo "✅ Remnanode restarted"
else
    echo "⚠️  remnanode container not found — skipping restart"
fi

