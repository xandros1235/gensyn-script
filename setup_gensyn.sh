#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
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
USER_HOME="/home/$(whoami)"
PEM_SRC=""
PEM_DEST="$USER_HOME/swarm.pem"
RL_SWARM_DIR="$USER_HOME/rl-swarm"

echo -e "${GREEN}[1/10] Backing up swarm.pem if exists...${NC}"

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

echo -e "${GREEN}[2/10] Updating system silently...${NC}"
sudo apt-get update -qq > /dev/null
sudo apt-get upgrade -y -qq > /dev/null

echo -e "${GREEN}[3/10] Installing dependencies silently...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen > /dev/null

echo -e "${GREEN}[4/10] Installing NVM and latest Node.js...${NC}"
curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node > /dev/null
nvm use node > /dev/null

# Remove old rl-swarm if exists
if [ -d "$RL_SWARM_DIR" ]; then
  echo -e "${GREEN}[5/10] Removing existing rl-swarm folder...${NC}"
  rm -rf "$RL_SWARM_DIR"
fi

echo -e "${GREEN}[6/10] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm "$RL_SWARM_DIR" > /dev/null

# Restore swarm.pem if we had a backup
if [ -f "$PEM_DEST.backup" ]; then
  cp "$PEM_DEST.backup" "$RL_SWARM_DIR/swarm.pem"
  echo "Restored swarm.pem into rl-swarm folder."
fi

cd "$RL_SWARM_DIR"

echo -e "${GREEN}[7/10] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

echo -e "${GREEN}[8/10] Replacing modal-login/app/page.tsx with custom content...${NC}"
mkdir -p modal-login/app
cat > modal-login/app/page.tsx << 'EOF'
"use client";
import {
  useAuthModal,
  useLogout,
  useSigner,
  useSignerStatus,
  useUser,
} from "@account-kit/react";
import { useEffect, useState } from "react";

export default function Home() {
  const user = useUser();
  const { openAuthModal } = useAuthModal();
  const signerStatus = useSignerStatus();
  const { logout } = useLogout();
  const signer = useSigner();

  const [createdApiKey, setCreatedApiKey] = useState(false);

  useEffect(() => {
    if (!user && createdApiKey) setCreatedApiKey(false);
    if (!user || !signer || !signerStatus.isConnected || createdApiKey) return;

    const submitStamp = async () => {
      const whoamiStamp = await signer.inner.stampWhoami();
      const resp = await fetch("/api/get-api-key", {
        method: "POST",
        body: JSON.stringify({ whoamiStamp }),
      });
      return (await resp.json()) as { publicKey: string };
    };

    const createApiKey = async (publicKey: string) => {
      await signer.inner.experimental_createApiKey({
        name: `server-signer-${Date.now()}`,
        publicKey,
        expirationSec: 60 * 60 * 24 * 62,
      });
    };

    const handleAll = async () => {
      try {
        const { publicKey } = await submitStamp();
        await createApiKey(publicKey);
        await fetch("/api/set-api-key-activated", {
          method: "POST",
          body: JSON.stringify({ orgId: user.orgId, apiKey: publicKey }),
        });
        setCreatedApiKey(true);
      } catch (err) {
        console.error("API Key Setup Error:", err);
        alert("Something went wrong during API key setup.");
      }
    };

    handleAll();
  }, [createdApiKey, signer, signerStatus.isConnected, user]);

  useEffect(() => {
    if (typeof window !== "undefined") {
      try {
        if (typeof window.crypto.subtle !== "object") {
          throw new Error("window.crypto.subtle is not available");
        }
      } catch (err) {
        alert("Crypto API is not available. Please access via localhost or HTTPS.");
      }
    }
  }, []);

  useEffect(() => {
    if (!signerStatus.isInitializing && !user) openAuthModal();
  }, [signerStatus.isInitializing, user]);

  return (
    <main className="flex min-h-screen flex-col items-center gap-4 justify-center text-center">
      {signerStatus.isInitializing ? (
        <p className="text-lg font-medium">Initializing signer...</p>
      ) : user && !createdApiKey ? (
        <p className="text-lg font-medium">Creating API key...</p>
      ) : user ? (
        <div className="card">
          <div className="flex flex-col gap-2 p-2">
            <p className="text-xl font-bold">YOU ARE SUCCESSFULLY LOGGED IN TO THE GENSYN TESTNET</p>
            <button className="btn btn-primary mt-6" onClick={() => logout()}>
              Log out
            </button>
          </div>
        </div>
      ) : (
        <div className="card">
          <p className="text-xl font-bold">LOGIN TO THE GENSYN TESTNET</p>
          <div className="flex flex-col gap-2 p-2">
            <button className="btn btn-primary mt-6" onClick={openAuthModal}>
              Login
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
EOF
# Free port 3000 if already in use
echo -e "${GREEN}🔍 Checking if port 3000 is in use...${NC}"
PORT_3000_PID=$(sudo lsof -t -i:3000 2>/dev/null || true)

if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️  Port 3000 is in use by PID $PORT_3000_PID. Terminating process...${NC}"
  sudo kill -9 "$PORT_3000_PID" || true
  echo -e "${GREEN}✅ Port 3000 has been freed.${NC}"
else
  echo -e "${GREEN}✅ Port 3000 is free.${NC}"
fi


echo -e "${GREEN}[9/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn ./run_rl_swarm.sh
echo -e "${GREEN}[10/10] Setting up Tunnel...${NC}"
echo -e "${GREEN}🌐 Attempting to expose localhost:3000 via LocalTunnel...${NC}"
screen -dmS lt_session bash -c "npx localtunnel --port 3000 > lt.log 2>&1"

# Wait for LT
for i in {1..15}; do
  sleep 1
  LT_URL=$(grep -o 'https://[^[:space:]]*' lt.log | head -n 1)
  if [[ "$LT_URL" == https://* ]]; then
    echo -e "${GREEN}✅ LocalTunnel is live at: $LT_URL${NC}"
    TUNNEL_URL="$LT_URL"
    break
  fi
done

if [ -z "$TUNNEL_URL" ]; then
  echo -e "${RED}❌ LocalTunnel failed. Trying Cloudflare Tunnel...${NC}"
  sudo npm install -g cloudflared > /dev/null 2>&1
  screen -dmS cf_tunnel bash -c "cloudflared tunnel --url http://localhost:3000 --logfile cf.log --loglevel info"

  for i in {1..15}; do
    sleep 1
    CF_URL=$(grep -o 'https://[^[:space:]]*.trycloudflare.com' cf.log | head -n 1)
    if [[ "$CF_URL" == https://* ]]; then
      echo -e "${GREEN}✅ Cloudflare Tunnel is live at: $CF_URL${NC}"
      TUNNEL_URL="$CF_URL"
      break
    fi
  done
fi

if [ -z "$TUNNEL_URL" ]; then
  echo -e "${RED}❌ Cloudflare Tunnel failed. Trying Ngrok...${NC}"
  sudo npm install -g ngrok > /dev/null 2>&1
  echo -e "${GREEN}🔐 Enter your Ngrok auth token:${NC}"
  read -rp "Auth Token: " NGROK_TOKEN
  ngrok config add-authtoken "$NGROK_TOKEN"
  screen -dmS ngrok_session bash -c "ngrok http 3000 > /dev/null 2>&1"

  for i in {1..15}; do
    sleep 1
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1)
    if [[ $NGROK_URL == https://* ]]; then
      echo -e "${GREEN}✅ Ngrok is live at: $NGROK_URL${NC}"
      TUNNEL_URL="$NGROK_URL"
      break
    fi
  done
fi

if [ -z "$TUNNEL_URL" ]; then
  echo -e "${RED}❌ All tunneling methods failed. Please check manually.${NC}"
else
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}Public URL: $TUNNEL_URL${NC}"
echo -e "${GREEN}[9/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn ./run_rl_swarm.sh
echo -e "${GREEN}[10/10] Setting up ngrok...${NC}"
echo -e "${GREEN}🌐 Attempting to expose localhost:3000 via LocalTunnel...${NC}"

# Try LocalTunnel
npm install -g localtunnel > /dev/null 2>&1
LT_URL=$(lt --port 3000 --print-requests 2>/dev/null &)
sleep 5
LT_PUBLIC_URL=$(curl -s http://localhost:3000 | grep -o 'https://.*\.loca\.lt' | head -n 1)

if [[ $LT_PUBLIC_URL == https://* ]]; then
  echo -e "${GREEN}✅ LocalTunnel URL: ${LT_PUBLIC_URL}${NC}"
else
  echo -e "${RED}❌ LocalTunnel failed. Uninstalling...${NC}"
  npm uninstall -g localtunnel > /dev/null 2>&1

  echo -e "${GREEN}☁️ Trying Cloudflare Tunnel...${NC}"
  if ! command -v cloudflared &> /dev/null; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb > /dev/null
    rm cloudflared-linux-amd64.deb
  fi

  screen -dmS cftunnel cloudflared tunnel --url http://localhost:3000
  sleep 10

  CF_URL=$(curl -s http://localhost:3000 | grep -o 'https://.*\.trycloudflare\.com' | head -n 1)

  if [[ $CF_URL == https://* ]]; then
    echo -e "${GREEN}✅ Cloudflare Tunnel URL: ${CF_URL}${NC}"
  else
    echo -e "${RED}❌ Cloudflare Tunnel failed. Trying Ngrok...${NC}"

    if ! command -v ngrok &> /dev/null; then
      npm install -g ngrok > /dev/null
    fi

    echo -e "${GREEN}🔑 Enter your Ngrok auth token:${NC}"
    read -rp "Auth Token: " NGROK_TOKEN
    ngrok config add-authtoken "$NGROK_TOKEN"
    screen -dmS ngrok_session bash -c "ngrok http 3000 > /dev/null 2>&1"
    sleep 10

    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1)

    if [[ $NGROK_URL == https://* ]]; then
      echo -e "${GREEN}✅ Ngrok URL: ${NGROK_URL}${NC}"
    else
      echo -e "${RED}❌ All tunneling methods failed.${NC}"
    fi
  fi
fi

  echo -e "${GREEN}Use this in your browser to access the login page.${NC}"
  echo -e "${GREEN}=========================================${NC}"
fi
  echo -e "${GREEN}🎥 What's Next? Watch this guide to continue:${NC}"
  echo -e "${GREEN}https://youtu.be/XF_HiOfK1PI?si=tnd6b9kytd1RvcME${NC}"
  echo -e "${GREEN}=========================================${NC}"
else
  echo -e "${RED}❌ Failed to fetch ngrok URL. Make sure ngrok started correctly.${NC}"
fi
