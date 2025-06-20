#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Random delay (0–60s) to mimic human start behavior
DELAY=$((RANDOM % 60))
echo -e "${GREEN}⏳ Simulating human-like startup delay: ${CYAN}${DELAY}s${NC}"
sleep $DELAY

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
else
  echo "swarm.pem not found. Continuing without backup."
fi

echo -e "${GREEN}[1/10] Updating system silently...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[2/10] Installing dependencies silently...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen cpulimit at net-tools > /dev/null

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

echo -e "${GREEN}🛠 Patching: $CONFIG_FILE${NC}"
cd "$CONFIG_DIR"
cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
sed -i 's/torch_dtype:.*/torch_dtype: float32/' "$CONFIG_FILE"
sed -i 's/bf16:.*/bf16: false/' "$CONFIG_FILE"
sed -i 's/tf32:.*/tf32: false/' "$CONFIG_FILE"
sed -i 's/gradient_checkpointing:.*/gradient_checkpointing: false/' "$CONFIG_FILE"
sed -i 's/per_device_train_batch_size:.*/per_device_train_batch_size: 1/' "$CONFIG_FILE"

echo -e "${GREEN}✅ Config patched. Backup saved as $CONFIG_FILE.bak${NC}"

echo -e "${GREEN}[7/10] Updating startup timeouts for stability...${NC}"
sed -i.bak 's/startup_timeout=30/startup_timeout=120/' "$HOME/rl-swarm/hivemind_exp/runner/grpo_runner.py"
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$HOME/rl-swarm/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"

if [ -f "$P2P_DAEMON_FILE" ]; then
  sed -i 's/startup_timeout: float = 15/startup_timeout: float = 120/' "$P2P_DAEMON_FILE"
  echo -e "${GREEN}✅ Updated: $P2P_DAEMON_FILE${NC}"
fi

echo -e "${GREEN}🧹 Closing any existing gensyn screen...${NC}"
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done

echo -e "${GREEN}🔍 Checking if port 3000 is in use...${NC}"
PORT_3000_PID=$(sudo netstat -tunlp 2>/dev/null | grep ':3000' | awk '{print $7}' | cut -d'/' -f1 | head -n1)
if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️ Port 3000 is in use. Killing PID: $PORT_3000_PID${NC}"
  sudo kill -9 "$PORT_3000_PID" || true
fi

echo -e "${GREEN}[8/10] Launching Gensyn with throttled CPU in screen...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source .venv/bin/activate
cpulimit -l 80 -- ./run_rl_swarm.sh >> swarm.log 2>&1
"

echo -e "${GREEN}🔁 Scheduling auto-restart every 6 hours...${NC}"
echo "screen -S gensyn -X quit && bash ~/rl-swarm/restart.sh" | at now + 6 hours

cat << 'EOF' > ~/rl-swarm/restart.sh
#!/bin/bash
cd ~/rl-swarm
source .venv/bin/activate
cpulimit -l 80 -- ./run_rl_swarm.sh >> swarm.log 2>&1
EOF
chmod +x ~/rl-swarm/restart.sh

echo -e "${GREEN}[9/10] Exposing port 3000 — safe Ngrok tunnel...${NC}"
echo -e "3) Ngrok (safe mode)"
read -rp "🔑 Enter your Ngrok auth token (from https://dashboard.ngrok.com/get-started/your-authtoken): " NGROK_TOKEN
npm install -g ngrok > /dev/null 2>&1
ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1
screen -S ngrok_tunnel -X quit 2>/dev/null
screen -dmS ngrok_tunnel bash -c "ngrok http --region=ap 3000 > /dev/null 2>&1"

sleep 6
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1)

if [ -n "$NGROK_URL" ]; then
  echo -e "${GREEN}✅ Ngrok tunnel established: ${CYAN}$NGROK_URL${NC}"
  echo -e "${GREEN}🧠 Use it in your browser to access Gensyn login page${NC}"
else
  echo -e "${RED}❌ Failed to get Ngrok tunnel URL.${NC}"
fi
