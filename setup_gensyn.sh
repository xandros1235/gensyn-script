xandros🆙 UXUY, [19-06-2025 15:33]
#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# BANNER
echo -e "${GREEN}"
cat << 'EOF'
 __              _         _                                              
|  ___ \            | |       | |                    _                        
| |   | |  _    _ | |   | | _   _   _    | |_        ___ 
| |   | | / _ \  / || | / _  )|  \ | | |  _ \ |  _) / _  ) / _)(_  )| |   | |
|_|   |_| \_/  \| \)|_| |_| \||_| |_| \_)\__)|_|    (___)
EOF
echo -e "${NC}"

# Set user and paths
USER_HOME=$(eval echo "~$(whoami)")
PEM_SRC=""
PEM_DEST="$USER_HOME/swarm.pem"
RL_SWARM_DIR="$USER_HOME/rl-swarm"

echo -e "${GREEN}[0/10] Backing up swarm.pem if exists...${NC}"
if [ -f "$USER_HOME/swarm.pem" ]; then
  PEM_SRC="$USER_HOME/swarm.pem"
elif [ -f "$RL_SWARM_DIR/swarm.pem" ]; then
  PEM_SRC="$RL_SWARM_DIR/swarm.pem"
fi

if [ -n "$PEM_SRC" ]; then
  echo "Found swarm.pem at: $PEM_SRC"
  cp "$PEM_SRC" "$PEM_DEST.backup"
  echo "Backup created: $PEM_DEST.backup"
else
  echo "swarm.pem not found. Continuing without backup."
fi

echo -e "${GREEN}[1/10] Updating system silently...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[2/10] Installing dependencies silently...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen net-tools iproute2 > /dev/null

echo -e "${GREEN}[3/10] Installing NVM and latest Node.js...${NC}"
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node > /dev/null
nvm use node > /dev/null

if [ -d "$RL_SWARM_DIR" ]; then
  echo -e "${GREEN}[4/10] Removing existing rl-swarm folder...${NC}"
  rm -rf "$RL_SWARM_DIR"
fi

echo -e "${GREEN}[5/10] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR" > /dev/null

if [ -f "$PEM_DEST.backup" ]; then
  cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"
  echo "Restored swarm.pem into rl-swarm folder."
fi

cd "$RL_SWARM_DIR"

echo -e "${GREEN}[6/10] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

echo -e "${GREEN}🔍 Searching for YAML config file...${NC}"
SEARCH_DIRS=("$HOME/rl-swarm/hivemind_exp/configs/mac" "$HOME/rl-swarm")
CONFIG_FILE=""
for dir in "${SEARCH_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    cd "$dir"
    file=$(ls *.yaml 2>/dev/null | head -n 1)
    if [ -n "$file" ]; then
      CONFIG_FILE="$file"
      CONFIG_DIR="$dir"
      break
    fi
  fi
done

if [ -z "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ No YAML config file found in expected locations.${NC}"
  exit 1
fi

echo -e "${GREEN}🛠 Fixing batch error in: $CONFIG_FILE${NC}"
cd "$CONFIG_DIR"
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
sed -i 's/torch_dtype:.*/torch_dtype: float32/' "$CONFIG_FILE"
sed -i 's/bf16:.*/bf16: false/' "$CONFIG_FILE"
sed -i 's/tf32:.*/tf32: false/' "$CONFIG_FILE"
sed -i 's/gradient_checkpointing:.*/gradient_checkpointing: false/' "$CONFIG_FILE"
sed -i 's/per_device_train_batch_size:.*/per_device_train_batch_size: 1/' "$CONFIG_FILE"
echo -e "${GREEN}✅ Config updated and backup saved as $CONFIG_FILE.bak${NC}"

echo -e "${GREEN} Updating grpo_runner.py to change DHT start and timeout...${NC}"
sed -i.bak 's/startup_timeout=30/startup_timeout=120/' "$HOME/rl-swarm/hivemind_exp/runner/grpo_runner.py"

cd "$HOME/rl-swarm"
source .venv/bin/activate
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$HOME/rl-swarm/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"

echo -e "${GREEN}[7/10] Updating startup_timeout in hivemind's p2p_daemon.py...${NC}"

# xandros UP UXUY, [19-06-2025 15:33]
if [ -f "$P2P_DAEMON_FILE" ]; then
  sed -i 's/startup_timeout: float = 15/startup_timeout: float = 120/' "$P2P_DAEMON_FILE"
  echo -e "${GREEN}✅ Updated startup_timeout to 120 in: $P2P_DAEMON_FILE${NC}"
else
  echo -e "${RED}⚠️ File not found: $P2P_DAEMON_FILE. Skipping this step.${NC}"
fi

echo -e "${GREEN}🧹 Closing any existing 'gensyn' screen sessions...${NC}"
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done

echo -e "${GREEN}🔍 Checking if port 3000 is in use (via netstat)...${NC}"
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)
if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️  Port 3000 is in use by PID $PORT_3000_PID. Terminating...${NC}"
  sudo kill -9 "$PORT_3000_PID"
  echo -e "${GREEN}✅ Port 3000 has been freed.${NC}"
else
  echo -e "${GREEN}✅ Port 3000 is already free.${NC}"
fi

echo -e "${GREEN}[8/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn bash -c "cd ~/rl-swarm; source \"$HOME/rl-swarm/.venv/bin/activate\"; ./run_rl_swarm.sh; echo '⚠️ run_rl_swarm.sh exited with error code \$?'; exec bash"

# ================== [9/10] CLOUDFLARE TUNNEL AUTO REFRESH ====================
echo -e "${GREEN}[9/10] Starting persistent Cloudflare Tunnel with 12-hour rotation...${NC}"

if ! command -v cloudflared &> /dev/null; then
  echo -e "${YELLOW}Installing cloudflared...${NC}"
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  sudo dpkg -i cloudflared-linux-amd64.deb > /dev/null
  rm -f cloudflared-linux-amd64.deb
fi

cat > "$HOME/start_cf_tunnel.sh" << 'EOF'
#!/bin/bash
LOGFILE="$HOME/cf.log"
while true; do
  pkill -f 'cloudflared tunnel' || true
  echo "[$(date)] Restarting Cloudflare Tunnel..." >> "$LOGFILE"
  cloudflared tunnel --url http://localhost:3000 --logfile "$LOGFILE" --loglevel info &
  sleep 43200  # 12 hours
done
EOF

chmod +x "$HOME/start_cf_tunnel.sh"
screen -S cf_tunnel -X quit 2>/dev/null || true
screen -dmS cf_tunnel bash "$HOME/start_cf_tunnel.sh"
sleep 5
TUNNEL_URL=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' "$HOME/cf.log" | tail -n 1)

if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}✅ Tunnel established at: ${CYAN}$TUNNEL_URL${NC}"
  echo -e "${GREEN}🔁 This tunnel will auto-refresh every 12 hours.${NC}"
  echo -e "${GREEN}🎥 Guide: https://youtu.be/0vwpuGsC5nE${NC}"
else
  echo -e "${RED}❌ Tunnel failed to start. Check $HOME/cf.log for details.${NC}"
fi

# ================== [10/10] GCP ANTI-BAN SECTION ===================
if curl -s -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/ > /dev/null; then
  echo -e "${GREEN}[10/10] GCP detected — applying anti-ban measures...${NC}"
  sudo systemctl stop serial-getty@ttyS0.service > /dev/null 2>&1 || true
  sudo systemctl disable serial-getty@ttyS0.service > /dev/null 2>&1 || true
  sudo iptables -A OUTPUT -d 169.254.169.254 -j REJECT --reject-with icmp-host-unreachable
  for svc in google-guest-agent google-osconfig-agent google-network-daemon; do
    if systemctl list-units --type=service | grep -q "$svc"; then
      sudo systemctl stop "$svc" > /dev/null 2>&1 || true
      sudo systemctl disable "$svc" > /dev/null 2>&1 || true
      sudo systemctl mask "$svc" > /dev/null 2>&1 || true
      echo "$svc disabled and masked."
    fi
  done
  sudo systemctl stop unattended-upgrades.service > /dev/null 2>&1 || true
  sudo systemctl disable unattended-upgrades.service > /dev/null 2>&1 || true
  sudo bash -c 'echo "" > /var/log/google_guest_agent.log 2>/dev/null || true'
  sudo bash -c 'echo "" > /var/log/google-network-daemon.log 2>/dev/null || true'
  sudo touch /etc/default/instance_configs.cfg
  sudo chmod 000 /etc/default/instance_configs.cfg || true
  echo -e "${GREEN}✅ GCP anti-ban hardening complete.${NC}"
else
  echo -e "${YELLOW}⚠️ Not running on GCP — skipping anti-ban steps.${NC}"
fi

