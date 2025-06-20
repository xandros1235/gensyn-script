#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Switch to home
cd ~ || { echo -e "${RED}❌ Cannot access home directory${NC}"; exit 1; }

# Detect instance metadata (GCP-safe)
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
PROJECT_ID=$(gcloud config get-value project)

echo -e "${CYAN}📍 Instance: $INSTANCE_NAME | Zone: $ZONE | Project: $PROJECT_ID${NC}"

# Install dependencies
echo -e "${YELLOW}⚙️ Installing system packages...${NC}"
sudo apt-get update -y
sudo apt-get install -y curl unzip screen cpulimit python3-pip git
pip3 install poetry

# Clone Gensyn repo
if [ ! -d "rl-swarm" ]; then
  echo -e "${YELLOW}📥 Cloning Gensyn rl-swarm repo...${NC}"
  git clone https://github.com/gensyn-ai/rl-swarm.git
fi

cd rl-swarm
cp -n config.example.toml config.toml

# Check for swarm.pem
if [ ! -f ~/swarm.pem ]; then
  echo -e "${RED}❌ swarm.pem missing in home directory! Upload it and rerun.${NC}"
  exit 1
fi

# Install Python dependencies
echo -e "${YELLOW}🐍 Installing Python project deps...${NC}"
poetry install

# Create launcher
echo -e "${YELLOW}🎭 Creating launcher script...${NC}"
cat <<EOF > ~/launch_gensyn.sh
#!/bin/bash
cd ~/rl-swarm
poetry run python3 node.py --key-file ~/swarm.pem
EOF
chmod +x ~/launch_gensyn.sh

# Disable system logging (stealth)
echo -e "${YELLOW}🧹 Disabling system logs...${NC}"
sudo systemctl stop rsyslog || true
sudo systemctl disable rsyslog || true
sudo systemctl stop systemd-journald || true
sudo systemctl disable systemd-journald || true

# Start in screen with CPU throttle
echo -e "${GREEN}🚀 Launching Gensyn node with CPU limit (80%)...${NC}"
screen -dmS gensyn-node bash -c "cpulimit -l 80 -- ~/launch_gensyn.sh"

sleep 3

# Auto-restart every 6 hours via cron
echo -e "${YELLOW}⏱️ Setting up auto-restart every 6 hours...${NC}"
(crontab -l 2>/dev/null; echo "0 */6 * * * /bin/bash -c '
  screen -S gensyn-node -X quit;
  sleep 10;
  screen -dmS gensyn-node bash -c \"cpulimit -l 80 -- ~/launch_gensyn.sh\";
' >> ~/gensyn-restart.log 2>&1") | crontab -

echo -e "${GREEN}✅ Gensyn node is running inside screen session 'gensyn-node'${NC}"
echo -e "${GREEN}✅ Auto-restart every 6 hours is now active.${NC}"

# IAP Tunnel Instructions
echo -e "${CYAN}🔐 To access Gensyn dashboard securely, run from your local machine:\n"
echo -e "${YELLOW}gcloud compute start-iap-tunnel $INSTANCE_NAME 3000 --zone=$ZONE --local-host-port=localhost:3000${NC}"
echo -e "${CYAN}Then open: ${YELLOW}http://localhost:3000${NC}"
