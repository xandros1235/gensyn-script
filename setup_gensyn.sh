#!/bin/bash

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Tunnel functions
start_cloudflared() {
  echo -e "${CYAN}Starting Cloudflared tunnel...${NC}"
  cloudflared tunnel --url http://localhost:3000 2>&1 | tee cloudflared.log &
  sleep 5
  grep -o 'https://.*trycloudflare.com' cloudflared.log | head -n1
}

start_ngrok() {
  echo -e "${CYAN}Starting Ngrok tunnel...${NC}"
  ngrok http 3000 > /dev/null &
  sleep 6
  curl -s http://127.0.0.1:4040/api/tunnels | grep -o 'https://[a-z0-9]*\.ngrok.io' | head -n1
}

start_localtunnel() {
  echo -e "${CYAN}Starting LocalTunnel...${NC}"
  lt --port 3000 > localtunnel.log 2>&1 &
  sleep 5
  grep -o 'https://.*.loca.lt' localtunnel.log | head -n1
}

# Detect if script is running on Google Cloud
is_gcp() {
  curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/id > /dev/null
  return $?
}

# Set up GCP-safe IAP tunnel
setup_iap_tunnel() {
  echo -e "${CYAN}Setting up secure GCP IAP tunnel to port 3000...${NC}"
  read -p "Enter your GCP VM name: " INSTANCE_NAME
  read -p "Enter your GCP zone (e.g., us-central1-a): " ZONE
  gcloud compute start-iap-tunnel "$INSTANCE_NAME" 3000 \
    --local-host-port=localhost:3000 \
    --zone="$ZONE" &
  sleep 4
  echo -e "${GREEN}✅ Access your login at: ${CYAN}http://localhost:3000${NC}"
}

# Start Gensyn Node
start_gensyn() {
  echo -e "${CYAN}🔁 Starting Gensyn node...${NC}"
  # Replace this with your actual node start command if different:
  gensyn-node start
}

# Main Script
echo -e "${GREEN}🚀 Launching Gensyn Node + Tunnel Setup...${NC}"

start_gensyn

if is_gcp; then
  echo -e "${YELLOW}⚠️ GCP environment detected.${NC}"
  setup_iap_tunnel
  exit 0
fi

# Outside GCP: offer tunnel method
echo -e "${CYAN}Choose a tunnel method to expose your Gensyn login page:${NC}"
echo "1) Cloudflared"
echo "2) Ngrok"
echo "3) LocalTunnel"
echo "4) Auto (try all)"
read -p "Enter choice [1-4]: " CHOICE

case $CHOICE in
  1)
    TUNNEL_URL=$(start_cloudflared)
    ;;
  2)
    TUNNEL_URL=$(start_ngrok)
    ;;
  3)
    TUNNEL_URL=$(start_localtunnel)
    ;;
  4|*)
    TUNNEL_URL=$(start_localtunnel)
    if [ -z "$TUNNEL_URL" ]; then
      echo -e "${YELLOW}⚠️ LocalTunnel failed, trying Cloudflared...${NC}"
      TUNNEL_URL=$(start_cloudflared)
    fi
    if [ -z "$TUNNEL_URL" ]; then
      echo -e "${YELLOW}⚠️ Cloudflared failed, trying Ngrok...${NC}"
      TUNNEL_URL=$(start_ngrok)
    fi
    ;;
esac

# Show tunnel result
if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}✅ Tunnel established at: ${CYAN}$TUNNEL_URL${NC}"
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}🧠 Open this in your browser to access Gensyn login.${NC}"
  echo -e "${GREEN}🎥 Guide: https://youtu.be/0vwpuGsC5nE${NC}"
  echo -e "${GREEN}=========================================${NC}"
else
  echo -e "${RED}❌ Failed to establish a tunnel. Check logs or try again.${NC}"
fi
