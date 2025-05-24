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
echo -e "${GREEN}🧹 Closing any existing 'gensyn' screen sessions...${NC}"
screen -ls | grep -o '[0-9]*\.gensyn' | while read -r session; do
  screen -S "${session%%.*}" -X quit
done
# Free port 3000 if already in use
echo -e "${GREEN}🔍 Checking if port 3000 is in use...${NC}"
PORT_3000_PID=$(sudo lsof -t -i:3000 2>/dev/null || true)

if [ -n "$PORT_3000_PID" ]; then
  echo -e "${RED}⚠️  Port 3000 is in use by PID $PORT_3000_PID. Terminating...${NC}"
  sudo kill -9 "$PORT_3000_PID" || true
  echo -e "${GREEN}✅ Port 3000 has been freed.${NC}"
else
  echo -e "${GREEN}✅ Port 3000 is already free.${NC}"
fi

echo -e "${GREEN}[9/10] Running rl-swarm in screen session...${NC}"
screen -dmS gensyn bash -c "
cd ~/rl-swarm
source \"$HOME/rl-swarm/.venv/bin/activate\"
./run_rl_swarm.sh || echo '⚠️ run_rl_swarm.sh exited with error code \$?'
exec bash
"

echo -e "${GREEN}[10/10] Attempting to expose localhost:3000...${NC}"
TUNNEL_URL=""

# Try LocalTunnel
echo -e "${GREEN}🌐 Choose a tunnel method to expose port 3000:${NC}"
echo -e "1) LocalTunnel"
echo -e "2) Cloudflared"
echo -e "3) Ngrok"
echo -e "4) Auto fallback (try all methods)"
read -rp "Enter your choice [1-4]: " TUNNEL_CHOICE

TUNNEL_URL=""

start_localtunnel() {
  echo -e "${GREEN}🔌 Starting LocalTunnel...${NC}"
  npm install -g localtunnel > /dev/null 2>&1
  screen -S lt_tunnel -X quit 2>/dev/null
  screen -dmS lt_tunnel bash -c "npx localtunnel --port 3000 > lt.log 2>&1"
  sleep 5
  grep -o 'https://[^[:space:]]*\.loca\.lt' lt.log | head -n 1
}

start_cloudflared() {
  echo -e "${GREEN}🔌 Starting Cloudflared...${NC}"
  if ! command -v cloudflared &> /dev/null; then
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    sudo dpkg -i cloudflared-linux-amd64.deb > /dev/null
    rm -f cloudflared-linux-amd64.deb
  fi
  screen -S cf_tunnel -X quit 2>/dev/null
  screen -dmS cf_tunnel bash -c "cloudflared tunnel --url http://localhost:3000 --logfile cf.log --loglevel info"
  sleep 5
  grep -o 'https://[^[:space:]]*\.trycloudflare\.com' cf.log | head -n 1
}

start_ngrok() {
  echo -e "${GREEN}🔌 Starting Ngrok...${NC}"
  echo -e "${GREEN}🔌 Go to https://dashboard.ngrok.com/get-started/your-authtoken for auth token${NC}"
  if ! command -v ngrok &> /dev/null; then
    npm install -g ngrok > /dev/null
  fi
  read -rp "🔑 Enter your Ngrok auth token: " NGROK_TOKEN
  ngrok config add-authtoken "$NGROK_TOKEN" > /dev/null 2>&1
  screen -S ngrok_tunnel -X quit 2>/dev/null
  screen -dmS ngrok_tunnel bash -c "ngrok http 3000 > /dev/null 2>&1"
  sleep 5
  curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1
}

# Manual selection or fallback logic
case "$TUNNEL_CHOICE" in
  1)
    TUNNEL_URL=$(start_localtunnel)
    ;;
  2)
    TUNNEL_URL=$(start_cloudflared)
    ;;
  3)
    TUNNEL_URL=$(start_ngrok)
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

if [ -n "$TUNNEL_URL" ]; then
  echo -e "${GREEN}✅ Tunnel established at: ${CYAN}$TUNNEL_URL${NC}"
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}🧠 Use this in your browser to access the login page.${NC}"
  echo -e "${GREEN}🎥 Guide: https://youtu.be/XF_HiOfK1PI?si=tnd6b9kytd1RvcME${NC}"
  echo -e "${GREEN}=========================================${NC}"
else
  echo -e "${RED}❌ Failed to establish a tunnel. Please check logs or try again.${NC}"
fi
