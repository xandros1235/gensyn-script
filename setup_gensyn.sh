#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# GCP detection
is_gcp() {
  curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id > /dev/null
  return $?
}

# Banner
echo -e "${GREEN}"
cat << 'EOF'
 ______              _         _                                             
|  ___ \            | |       | |                   _                        
| |   | |  ___    _ | |  ____ | | _   _   _  ____  | |_   ____   ____  _____ 
| |   | | / _ \  / || | / _  )| || \ | | | ||  _ \ |  _) / _  ) / ___)(___  )
| |   | || |_| |( (_| |( (/ / | | | || |_| || | | || |__( (/ / | |     / __/ 
|_|   |_| \___/  \____| \____)|_| |_| \____||_| |_| \___)\____)|_|    (_____)
EOF
echo -e "${NC}"

# Set user and paths
USER_HOME=$(eval echo "~$(whoami)")
PEM_SRC=""
PEM_DEST="$USER_HOME/swarm.pem"
RL_SWARM_DIR="$USER_HOME/rl-swarm"

echo -e "${GREEN}[0/10] Backing up swarm.pem if exists...${NC}"

# Search for swarm.pem in home directory or inside rl-swarm
if [ -f "$USER_HOME/swarm.pem" ]; then
  PEM_SRC="$USER_HOME/swarm.pem"
elif [ -f "$RL_SWARM_DIR/swarm.pem" ]; then
  PEM_SRC="$RL_SWARM_DIR/swarm.pem"
fi

# Backup PEM if found
if [ -n "$PEM_SRC" ]; then
  echo "Found swarm.pem at: $PEM_SRC"
  cp "$PEM_SRC" "$PEM_DEST.backup"
  echo "Backup created: $PEM_DEST.backup"
else
  echo "swarm.pem not found. Continuing without backup."
fi

echo -e "${GREEN}[1/10] Updating system...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[2/10] Installing dependencies...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen net-tools > /dev/null

echo -e "${GREEN}[3/10] Installing NVM and Node.js...${NC}"
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node > /dev/null
nvm use node > /dev/null

# Remove old rl-swarm if exists
if [ -d "$RL_SWARM_DIR" ]; then
  echo -e "${GREEN}[4/10] Removing existing rl-swarm folder...${NC}"
  rm -rf "$RL_SWARM_DIR"
fi

echo -e "${GREEN}[5/10] Cloning rl-swarm repo...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR" > /dev/null

# Restore PEM if backed up
if [ -f "$PEM_DEST.backup" ]; then
  cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"
  echo "Restored swarm.pem into rl-swarm folder."
fi

cd "$RL_SWARM_DIR"

echo -e "${GREEN}[6/10] Setting up Python venv...${NC}"
python3 -m venv .venv
source .venv/bin/activate

# Find config file
echo -e "${GREEN}🔍 Searching for config file...${NC}"
SEARCH_DIRS=("$RL_SWARM_DIR/hivemind_exp/configs/mac" "$RL_SWARM_DIR")
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
  echo -e "${RED}❌ No YAML config found.${NC}"
  exit 1
fi

echo -e "${GREEN}🛠 Patching config: $CONFIG_FILE${NC}"
cd "$CONFIG_DIR"
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
sed -i 's/torch_dtype:.*/torch_dtype: float32/' "$CONFIG_FILE"
sed -i 's/bf16:.*/bf16: false/' "$CONFIG_FILE"
sed -i 's/tf32:.*/tf32: false/' "$CONFIG_FILE"
sed -i 's/gradient_checkpointing:.*/gradient_checkpointing: false/' "$CONFIG_FILE"
sed -i 's/per_device_train_batch_size:.*/per_device_train_batch_size: 1/' "$CONFIG_FILE"

# Patch grpo_runner
echo -e "${GREEN}🛠 Patching grpo_runner.py...${NC}"
sed -i.bak 's/startup_timeout=30/startup_timeout=120/' "$RL_SWARM_DIR/hivemind_exp/runner/grpo_runner.py"

# Patch p2p_daemon
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$RL_SWARM_DIR/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"
if [ -f "$P2P_DAEMON_FILE" ]; then
  sed -i 's/startup_timeout: float = 15/startup_timeout: float = 120/' "$P2P_DAEMON_FILE"
fi

# Kill old screen + free port 3000
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)
if [ -n "$PORT_3000_PID" ]; then
  sudo kill -9 "$PORT_3000_PID" || true
fi

# Start node in screen
echo -e "${GREEN}[7/10] Starting Gensyn node in screen...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source .venv/bin/activate
./run_rl_swarm.sh || echo '⚠️ run_rl_swarm.sh exited with error'
exec bash
"

# GCP-safe tunneling
if is_gcp; then
  echo -e "${YELLOW}⚠️ GCP detected. Public tunnels are disabled to avoid bans.${NC}"
  echo -e "${CYAN}💡 Use this command from your laptop to safely access the login page:${NC}"
  echo -e "${GREEN}gcloud compute start-iap-tunnel YOUR_INSTANCE_NAME 3000 --local-host-port=localhost:3000 --zone=YOUR_ZONE${NC}"
  echo -e "${CYAN}Then open → ${GREEN}http://localhost:3000${NC}"
  exit 0
fi

# Public tunnels (outside GCP)
echo -e "${GREEN}[8/10] Choose a tunnel method to expose localhost:3000${NC}"
echo -e "1) LocalTunnel"
echo -e "2) Cloudflared"
echo -e "3) Ngrok"
echo -e "4) Auto fallback"
read -rp "Enter your choice [1-4]: " TUNNEL_CHOICE

start_localtunnel() {
  npm install -g localtunnel > /dev/null 2>&1
  screen -S lt_tunnel -X quit 2>/dev/null
  screen -dmS lt_tunnel bash -c "npx localtunnel --port 3000 > lt.log 2>&1"
  sleep 5
  grep -o 'https://[^[:space:]]*\.loca\.lt' lt.log | head -n 1
}

start_cloudflared() {
  if ! command -v cloudflared &> /dev/null; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb > /dev/null
    rm -f cloudflared-linux-amd64.deb
  fi
  screen -S cf_tunnel -X quit 2>/dev/null
  screen -dmS cf_tunnel bash -c "cloudflared tunnel --url http://localhost:3000 --logfile cf.log --loglevel info"
  sleep 5
  grep -o 'https://[^[:space:]]*\.trycloudflare\.com' cf.log | head -n 1
}

start_ngrok() {
  if ! command -v ngrok &> /dev/null; then
    npm install -g ngrok > /dev/null
  fi
  read -rp "🔑 Enter your Ngrok auth token: " NGROK_TOKEN
  ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1
  screen -S ngrok_tunnel -X quit 2>/dev/null
  screen -dmS ngrok_tunnel bash -c "ngrok http 3000 > /dev/null 2>&1"
  sleep 5
  curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1
}

# Run selected tunnel
TUNNEL_URL=""
case "$TUNNEL_CHOICE" in
  1) TUNNEL_URL=$(start_localtunnel) ;;
  2) TUNNEL_URL=$(start_cloudflared) ;;
  3) TUNNEL_URL=$(start_ngrok) ;;
  4|*) 
    TUNNEL_URL=$(start_localtunnel)
    [ -z "$TUNNEL_URL" ] && TUNNEL_URL=$(start_cloudflared)
    [ -z "$TUNNEL_URL" ] && TUNNEL_URL=$(start_ngrok)
    ;;
esac

if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}✅ Tunnel established at: ${CYAN}$TUNNEL_URL${NC}"
  echo -e "${GREEN}Open this in your browser to access the login page.${NC}"
else
  echo -e "${RED}❌ Tunnel setup failed. Check logs or try again.${NC}"
fi
