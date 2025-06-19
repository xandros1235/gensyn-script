#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# BANNER
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

echo -e "${GREEN}[1/10] Updating system silently...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[2/10] Installing dependencies silently...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen > /dev/null

echo -e "${GREEN}[3/10] Installing NVM and latest Node.js...${NC}"
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

echo -e "${GREEN}[5/10] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR" > /dev/null

# Restore swarm.pem if we had a backup
if [ -f "$PEM_DEST.backup" ]; then
  cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"
  echo "Restored swarm.pem into rl-swarm folder."
fi

cd "$RL_SWARM_DIR"

echo -e "${GREEN}[6/10] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

# Try to locate the config YAML
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
echo -e "${GREEN} Activating virtual environment...${NC}"
cd "$HOME/rl-swarm"
source .venv/bin/activate

# Now we can safely get the Python version from the venv
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$HOME/rl-swarm/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"

echo -e "${GREEN}[7/10] Updating startup_timeout in hivemind's p2p_daemon.py...${NC}"

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

# Free port 3000 if already in use
echo -e "${GREEN}🔍 Checking if port 3000 is in use (via netstat)...${NC}"
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)

if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️  Port 3000 is in use by PID $PORT_3000_PID. Terminating...${NC}"
  sudo kill -9 "$PORT_3000_PID" || true
  echo -e "${GREEN}✅ Port 3000 has been freed.${NC}"
else
  echo -e "${GREEN}✅ Port 3000 is already free.${NC}"
fi

echo -e "${GREEN}[8/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source \"$HOME/rl-swarm/.venv/bin/activate\"
./run_rl_swarm.sh || echo '⚠️ run_rl_swarm.sh exited with error code \$?'
exec bash
"

echo -e "${GREEN}[9/10] Skipping public tunnels to avoid GCP violations.${NC}"
echo -e "${YELLOW}🔐 Using GCP Identity-Aware Proxy to forward port 3000 securely...${NC}"

# === GCP IAP TUNNEL START ===

INSTANCE_NAME="michel1"
ZONE_NAME="us-central1-c"
PROJECT_ID="bold-impulse-463214-j9"

echo -e "${GREEN}✅ Starting GCP IAP tunnel to access your node via localhost:3000...${NC}"
gcloud compute start-iap-tunnel "$INSTANCE_NAME" 3000 \
  --local-host-port=localhost:3000 \
  --zone="$ZONE_NAME" \
  --project="$PROJECT_ID" &
sleep 3

echo -e "${CYAN}🌐 Open this in your browser: http://localhost:3000${NC}"
echo -e "${GREEN}✅ Tunnel is private and GCP-compliant.${NC}"

# === GCP IAP TUNNEL END ===
