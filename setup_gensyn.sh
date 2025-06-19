#!/bin/bash
set -e

#================= Colors =================#
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

#================= Banner =================#
echo -e "${GREEN}"
cat << 'EOF'
   ____                 _                 
  / ___| ___   ___   __| | ___  ___ _ __  
 | |  _ / _ \ / _ \ / _` |/ _ \/ _ \ '_ \ 
 | |_| | (_) | (_) | (_| |  __/  __/ | | |
  \____|\___/ \___/ \__,_|\___|\___|_| |_|
EOF
echo -e "${NC}"

echo -e "${YELLOW}[*] Starting Gensyn + Anti-GCP + Cloudflare Setup...${NC}"

#================= Install Base Tools =================#
sudo apt-get update -y && sudo apt-get upgrade -y
sudo apt-get install -y curl wget net-tools tmux unzip jq git python3-pip python3-venv macchanger lsb-release software-properties-common cron

#================= GCP Anti-Ban Protection =================#
echo -e "${CYAN}[+] Applying GCP Anti-Ban Protections...${NC}"

# Block metadata server (anti-crypto detection)
echo "127.0.0.1 metadata.google.internal" | sudo tee -a /etc/hosts
echo "127.0.0.1 metadata" | sudo tee -a /etc/hosts

# Change hostname to random
NEW_HOST="vm-$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)"
sudo hostnamectl set-hostname "$NEW_HOST"
echo -e "${GREEN}[✓] Hostname changed to $NEW_HOST${NC}"

# Randomize MAC address
IFACE=$(ip route | grep default | awk '{print $5}')
sudo ip link set $IFACE down
sudo macchanger -r $IFACE || true
sudo ip link set $IFACE up

# Disable TCP timestamps (avoid fingerprinting)
sudo sysctl -w net.ipv4.tcp_timestamps=0
echo "net.ipv4.tcp_timestamps=0" | sudo tee -a /etc/sysctl.conf

# Flush DNS (for masking)
sudo systemd-resolve --flush-caches || true

#================= Install Cloudflared =================#
echo -e "${CYAN}[+] Installing Cloudflared...${NC}"
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -O cloudflared.deb
sudo dpkg -i cloudflared.deb || sudo apt-get install -f -y
sudo rm cloudflared.deb
CLOUDFLARED_PATH=$(command -v cloudflared)
sudo chmod +x "$CLOUDFLARED_PATH"
sudo setcap cap_net_bind_service=+ep "$CLOUDFLARED_PATH" || true

#================= Cloudflare Tunnel Login =================#
echo -e "${YELLOW}[!] Logging in to Cloudflare (copy + open the URL)...${NC}"
LOGIN_URL=$(cloudflared tunnel login 2>&1 | tee /tmp/cf_login.log | grep -o 'https://.*cloudflare.com.*')
if [[ -z "$LOGIN_URL" ]]; then
    echo -e "${RED}[X] Failed to get login URL. Exiting.${NC}"
    exit 1
fi
echo -e "\n${CYAN}>>> LOGIN URL: ${NC}$LOGIN_URL\n"
echo -e "${YELLOW}Open this link in a browser and finish login. Then press ENTER to continue.${NC}"
read -p ""

#================= Create Tunnel =================#
mkdir -p ~/.cloudflared
TUNNEL_NAME="gensyn-$(date +%s)"
cloudflared tunnel create "$TUNNEL_NAME"

# Write config
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_NAME
credentials-file: /root/.cloudflared/${TUNNEL_NAME}.json
ingress:
  - service: http://localhost:8000
  - service: http_status:404
EOF

#================= Gensyn Setup =================#
echo -e "${CYAN}[+] Installing Gensyn...${NC}"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install "gensyn[speed]"

#================= Create Start Scripts =================#
echo -e "${CYAN}[+] Creating start scripts...${NC}"

cat <<EOF > run_node.sh
#!/bin/bash
source venv/bin/activate
gensyn swarm --start
EOF
chmod +x run_node.sh

cat <<EOF > run_tunnel.sh
#!/bin/bash
cloudflared tunnel run $TUNNEL_NAME
EOF
chmod +x run_tunnel.sh

#================= Auto Tunnel Refresh Setup =================#
echo -e "${CYAN}[+] Setting up auto-refresh every 12 hours via cron + tmux...${NC}"

(crontab -l 2>/dev/null; echo "0 */12 * * * pkill -f 'cloudflared tunnel run' && tmux kill-session -t tunnel && tmux new-session -d -s tunnel './run_tunnel.sh'") | crontab -

#================= Start Node and Tunnel =================#
echo -e "${CYAN}[+] Launching Gensyn node and tunnel in background (tmux)...${NC}"
tmux new-session -d -s gensyn './run_node.sh'
tmux new-session -d -s tunnel './run_tunnel.sh'

#================= Done =================#
echo -e "${GREEN}[✓] Setup complete! Gensyn node and tunnel are now running.${NC}"
echo -e "${YELLOW}Use the following commands to monitor or restart:"
echo -e "  - tmux attach -t gensyn     # View node"
echo -e "  - tmux attach -t tunnel     # View tunnel"
echo -e "  - ./run_node.sh             # Manual restart node"
echo -e "  - ./run_tunnel.sh           # Manual restart tunnel"
echo -e "${NC}"
