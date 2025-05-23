#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

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
sed -i 's/hivemind\.DHT(start=True, startup_timeout=30/hivemind.DHT(start=False, startup_timeout=120/' "$HOME/rl-swarm/hivemind_exp/runner/grpo_runner.py"
echo -e "${GREEN} Activating virtual environment...${NC}"
cd "$HOME/rl-swarm"
source .venv/bin/activate

# Now we can safely get the Python version from the venv
PYTHON_VERSION=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
P2P_DAEMON_FILE="$HOME/rl-swarm/.venv/lib/python$PYTHON_VERSION/site-packages/hivemind/p2p/p2p_daemon.py"

echo -e "${GREEN}[13/10] Updating startup_timeout in hivemind's p2p_daemon.py...${NC}"

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

echo -e "${GREEN}🚀 Starting new 'gensyn' screen session...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source \"$HOME/rl-swarm/.venv/bin/activate\"
./run_rl_swarm.sh || echo '⚠️ run_rl_swarm.sh exited with error code \$?'
exec bash
"

echo -e "${GREEN}✅ Gensyn node restarted in screen session 'gensyn'.${NC}"
