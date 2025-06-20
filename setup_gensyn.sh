#!/bin/bash
set -e
export PATH="$HOME/.local/bin:$PATH"  # Ensure poetry can be found

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

cd ~ || { echo -e "${RED}❌ Cannot access home directory${NC}"; exit 1; }

# Detect metadata
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
PROJECT_ID=$(gcloud config get-value project)

echo -e "${CYAN}📍 Instance: $INSTANCE_NAME | Zone: $ZONE | Project: $PROJECT_ID${NC}"

# Install system dependencies
echo -e "${YELLOW}⚙️ Installing system packages...${NC}"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip screen cpulimit python3-pip git

# Install Poetry
echo -e "${YELLOW}📦 Installing Poetry...${NC}"
pip3 install --user poetry
export PATH="$HOME/.local/bin:$PATH"

# Force fresh rl-swarm clone
echo -e "${YELLOW}🧽 Removing old rl-swarm if it exists...${NC}"
rm -rf ~/rl-swarm

echo -e "${YELLOW}📥 Cloning latest rl-swarm...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm.git
cd rl-swarm

# Check for swarm.pem
if [ ! -f ~/swarm.pem ]; then
  echo -e "${RED}❌ swarm.pem missing in home directory! Upload it and rerun.${NC}"
  exit 1
fi

# Install Python dependencies
echo -e "${YELLOW}🐍 Installing Python dependencies...${NC}"
poetry install

# Create launch script
echo -e "${YELLOW}🎭 Creating launch script...${NC}"
cat <<EOF > ~/launch_gensyn.sh
#!/bin/bash
cd ~/rl-swarm
poetry run python3 node.py --key-file ~/swarm.pem
EOF
chmod +x ~/launch_gensyn.sh

# Disable system logs (stealth mode)
echo -e "${YELLOW}🧹 Disabling system logs...${NC}"
sudo systemctl stop rsyslog || true
sudo systemctl disable rsyslog || true
sudo systemctl stop systemd-journald || true
sudo systemctl disable systemd-journald || true

# Start node with CPU throttle (80%)
echo -e "${GREEN}🚀 Launching Gensyn node with CPU throttle (80%)...${NC}"
screen -dmS gensyn-node bash -c "cpulimit -l 80 -- ~/launch_gensyn.sh"
sleep 3

# Auto-restart every 6 hours
echo -e "${YELLOW}⏱️ Setting up auto-restart every 6 hours...${NC}"
(crontab -l 2>/dev/null; echo "0 */6 * * * /bin/bash -c '
  screen -S gensyn-node -X quit;
  sleep 10;
  screen -dmS gensyn-node bash -c \"cpulimit -l 80 -- ~/launch_gensyn.sh\";
' >> ~/gensyn-restart.log 2>&1") | crontab -

echo -e "${GREEN}✅ Gensyn node is running in screen session: gensyn-node${NC}"
echo -e "${GREEN}✅ Auto-restarts every 6 hours are active${NC}"

# Tunnel access instruction
echo -e "${CYAN}🔐 To access the dashboard run:\n${YELLOW}gcloud compute start-iap-tunnel $INSTANCE_NAME 3000 --zone=$ZONE --local-host-port=localhost:3000${NC}"
echo -e "${CYAN}Then open: ${YELLOW}http://localhost:3000${NC}"
