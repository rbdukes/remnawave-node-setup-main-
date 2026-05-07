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
