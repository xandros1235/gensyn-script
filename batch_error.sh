#!/bin/bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}📁 Navigating to config directory...${NC}"
CONFIG_DIR="$HOME/rl-swarm/hivemind_exp/configs/mac"
cd "$CONFIG_DIR"

CONFIG_FILE=$(ls | head -n 1)

if [ -z "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ No YAML file found in $CONFIG_DIR${NC}"
  exit 1
fi

echo -e "${GREEN}🛠 Fixing batch error in: $CONFIG_FILE${NC}"

cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

sed -i 's/torch_dtype:.*/torch_dtype: float32/' "$CONFIG_FILE"
sed -i 's/bf16:.*/bf16: false/' "$CONFIG_FILE"
sed -i 's/tf32:.*/tf32: false/' "$CONFIG_FILE"
sed -i 's/gradient_checkpointing:.*/gradient_checkpointing: false/' "$CONFIG_FILE"
sed -i 's/per_device_train_batch_size:.*/per_device_train_batch_size: 1/' "$CONFIG_FILE"

echo -e "${GREEN}✅ Config updated and backup saved as $CONFIG_FILE.bak${NC}"

echo -e "${GREEN}🧹 Closing any existing 'gensyn' screen sessions...${NC}"
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done

echo -e "${GREEN}🚀 Starting new 'gensyn' screen session...${NC}"
screen -dmS gensyn bash -c "cd ~/rl-swarm && source .venv/bin/activate && ./run_rl_swarm.sh"

echo -e "${GREEN}✅ Gensyn node restarted in screen session 'gensyn'.${NC}"
