#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure we're in a valid directory
cd ~ || { echo "\n${RED}❌ Failed to change to home directory.${NC}"; exit 1; }

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

# 0. Backup PEM
if [ -f "$USER_HOME/swarm.pem" ]; then
  PEM_SRC="$USER_HOME/swarm.pem"
elif [ -f "$RL_SWARM_DIR/swarm.pem" ]; then
  PEM_SRC="$RL_SWARM_DIR/swarm.pem"
fi
if [ -n "$PEM_SRC" ]; then
  echo -e "${GREEN}[0/10] Backing up swarm.pem...${NC}"
  cp "$PEM_SRC" "$PEM_DEST.backup"
fi

# 1. Update system
echo -e "${GREEN}[1/10] Updating system...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

# 2. Install dependencies
echo -e "${GREEN}[2/10] Installing dependencies...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen > /dev/null

# 3. Install Node.js using NVM
echo -e "${GREEN}[3/10] Installing NVM and latest Node.js...${NC}"
cd ~ || exit 1
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node
nvm use node

# 4. Remove old rl-swarm
[ -d "$RL_SWARM_DIR" ] && rm -rf "$RL_SWARM_DIR"

# 5. Clone repo
echo -e "${GREEN}[5/10] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR"

# Restore PEM if needed
[ -f "$PEM_DEST.backup" ] && cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"

# 6. Setup venv
cd "$RL_SWARM_DIR"
echo -e "${GREEN}[6/10] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

# Find YAML config
echo -e "${GREEN}🔍 Searching for YAML config file...${NC}"
SEARCH_DIRS=("$HOME/rl-swarm/hivemind_exp/configs/mac" "$HOME/rl-swarm")
CONFIG_FILE=""
for dir in "${SEARCH_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    cd "$dir"
    file=$(ls *.yaml 2>/dev/null | head -n 1)
    [ -n "$file" ] && CONFIG_FILE="$file" && CONFIG_DIR="$dir" && break
  fi
done

[ -z "$CONFIG_FILE" ] && echo -e "${RED}❌ No YAML config file found.${NC}" && exit 1

# Patch config
cd "$CONFIG_DIR"
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
sed -i 's/torch_dtype:.*/torch_dtype: float32/' "$CONFIG_FILE"
sed -i 's/bf16:.*/bf16: false/' "$CONFIG_FILE"
sed -i 's/tf32:.*/tf32: false/' "$CONFIG_FILE"
sed -i 's/gradient_checkpointing:.*/gradient_checkpointing: false/' "$CONFIG_FILE"
sed -i 's/per_device_train_batch_size:.*/per_device_train_batch_size: 1/' "$CONFIG_FILE"
echo -e "${GREEN}✅ Patched $CONFIG_FILE${NC}"

# Patch Python files
sed -i.bak 's/startup_timeout=30/startup_timeout=120/' "$HOME/rl-swarm/hivemind_exp/runner/grpo_runner.py"
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$HOME/rl-swarm/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"
[ -f "$P2P_DAEMON_FILE" ] && sed -i 's/startup_timeout: float = 15/startup_timeout: float = 120/' "$P2P_DAEMON_FILE"

# Kill previous sessions
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done

# Free port 3000
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)
[ -n "$PORT_3000_PID" ] && sudo kill -9 "$PORT_3000_PID"

# 8. Start screen session
screen -dmS gensyn bash -c "cd ~/rl-swarm && source .venv/bin/activate && ./run_rl_swarm.sh || echo '⚠️ Failed'"

# 9. Start IAP tunnel
INSTANCE_NAME="REPLACE_WITH_YOUR_INSTANCE_NAME"
ZONE_NAME="REPLACE_WITH_YOUR_ZONE"
PROJECT_ID="REPLACE_WITH_YOUR_PROJECT_ID"
echo -e "${GREEN}[10/10] Starting GCP IAP tunnel...${NC}"
gcloud compute start-iap-tunnel "$INSTANCE_NAME" 3000 \
  --local-host-port=localhost:3000 \
  --zone="$ZONE_NAME" \
  --project="$PROJECT_ID" &
sleep 3
echo -e "${CYAN}✅ Gensyn UI available at: http://localhost:3000${NC}"
