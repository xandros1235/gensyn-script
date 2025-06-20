#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m' CYAN='\033[0;36m' YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'

cd ~ || { echo -e "${RED}❌ Cannot access home directory${NC}"; exit 1; }

INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
PROJECT_ID=$(gcloud config get-value project)

echo -e "${CYAN}📍 Instance: $INSTANCE_NAME | Zone: $ZONE | Project: $PROJECT_ID${NC}"

echo -e "${YELLOW}⚙️ Installing dependencies...${NC}"
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip screen cpulimit python3-pip git
pip3 install poetry

if [ ! -d "rl-swarm" ]; then
  echo -e "${YELLOW}📥 Cloning rl-swarm repo...${NC}"
  git clone https://github.com/gensyn-ai/rl-swarm.git
fi

cd rl-swarm

if [ ! -f ~/swarm.pem ]; then
  echo -e "${RED}❌ swarm.pem missing. Upload it and rerun.${NC}"
  exit 1
fi

echo -e "${YELLOW}🐍 Installing Python dependencies...${NC}"
poetry install

echo -e "${YELLOW}🎭 Creating launcher script...${NC}"
cat <<EOF > ~/launch_gensyn.sh
#!/bin/bash
cd ~/rl-swarm
poetry run python3 node.py --key-file ~/swarm.pem
EOF
chmod +x ~/launch_gensyn.sh

echo -e "${YELLOW}🧹 Disabling system logs...${NC}"
sudo systemctl stop rsyslog || true
sudo systemctl disable rsyslog || true
sudo systemctl stop systemd-journald || true
sudo systemctl disable systemd-journald || true

echo -e "${GREEN}🚀 Launching Gensyn node with CPU throttle (80%)...${NC}"
screen -dmS gensyn-node bash -c "cpulimit -l 80 -- ~/launch_gensyn.sh"
sleep 3

echo -e "${YELLOW}⏱️ Scheduling auto-restart every 6 hours...${NC}"
(crontab -l 2>/dev/null; echo "0 */6 * * * /bin/bash -c '
  screen -S gensyn-node -X quit;
  sleep 10;
  screen -dmS gensyn-node bash -c \"cpulimit -l 80 -- ~/launch_gensyn.sh\";
' >> ~/gensyn-restart.log 2>&1") | crontab -

echo -e "${GREEN}✅ Node running in screen 'gensyn-node'. Restarts scheduled every 6h.${NC}"
echo -e "${CYAN}🔐 Access dashboard with:\n${YELLOW}gcloud compute start-iap-tunnel $INSTANCE_NAME 3000 --zone=$ZONE --local-host-port=localhost:3000${NC}"
