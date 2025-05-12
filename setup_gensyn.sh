#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Banner
clear
echo -e "${GREEN}"
cat << "BANNER"
 ______              _         _                                             
|  ___ \            | |       | |                   _                        
| |   | |  ___    _ | |  ____ | | _   _   _  ____  | |_   ____   ____  _____ 
| |   | | / _ \  / || | / _  )| || \ | | | ||  _ \ |  _) / _  ) / ___)(___  )
| |   | || |_| |( (_| |( (/ / | | | || |_| || | | || |__( (/ / | |     / __/ 
|_|   |_| \___/  \____| \____)|_| |_| \____||_| |_| \___)\____)|_|    (_____)
                                                                             
BANNER
echo -e "${NC}"

USER_HOME="/home/$(whoami)"

# Locate swarm.pem file
PEM_PATH=$(find "$USER_HOME" -maxdepth 2 -type f -name "swarm.pem" 2>/dev/null | head -n 1)

if [ -n "$PEM_PATH" ]; then
  if [ "$PEM_PATH" != "${USER_HOME}/swarm.pem" ]; then
    echo -e "${GREEN}Found swarm.pem at $PEM_PATH, copying to ${USER_HOME}/swarm.pem...${NC}"
    cp "$PEM_PATH" "${USER_HOME}/swarm.pem"
  else
    echo -e "${GREEN}swarm.pem already in correct location. Creating .backup...${NC}"
    cp "${USER_HOME}/swarm.pem" "${USER_HOME}/swarm.pem.backup"
  fi
fi

# Remove existing rl-swarm if exists, but backup swarm.pem first
if [ -d "$USER_HOME/rl-swarm" ]; then
  if [ -f "$USER_HOME/rl-swarm/swarm.pem" ]; then
    echo -e "${GREEN}Backing up existing swarm.pem from rl-swarm...${NC}"
    cp "$USER_HOME/rl-swarm/swarm.pem" "$USER_HOME/swarm.pem.backup"
  fi
  echo -e "${GREEN}Removing old rl-swarm directory...${NC}"
  rm -rf "$USER_HOME/rl-swarm"
fi

echo -e "${GREEN}[1/9] Updating system...${NC}"
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

echo -e "${GREEN}[2/9] Installing dependencies...${NC}"
sudo apt install -y -qq sudo nano curl python3 python3-pip python3-venv git screen

echo -e "${GREEN}[3/9] Installing NVM and latest Node.js...${NC}"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm install node
nvm use node

echo -e "${GREEN}[4/9] Cloning rl-swarm repository...${NC}"
git clone https://github.com/gensyn-ai/rl-swarm

if [ -d "$USER_HOME/rl-swarm" ]; then
  echo -e "${GREEN}rl-swarm is already in place. No need to move.${NC}"
else
  mv rl-swarm "$USER_HOME/rl-swarm"
fi

cd "$USER_HOME/rl-swarm"

# Restore swarm.pem if it exists
if [ -f "$USER_HOME/swarm.pem" ]; then
  echo -e "${GREEN}Restoring swarm.pem into rl-swarm folder...${NC}"
  cp "$USER_HOME/swarm.pem" "$USER_HOME/rl-swarm/swarm.pem"
fi

echo -e "${GREEN}[5/9] Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate

echo -e "${GREEN}[6/9] Replacing app/page.tsx with custom content...${NC}"
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
    console.log("signerStatus:", signerStatus);
    console.log("user:", user);
    console.log("createdApiKey:", createdApiKey);
  }, [signerStatus, user, createdApiKey]);

  useEffect(() => {
    if (!user && createdApiKey) {
      setCreatedApiKey(false);
    }
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
        alert(
          "Crypto API is not available. Please access via localhost or HTTPS."
        );
      }
    }
  }, []);

  useEffect(() => {
    if (!signerStatus.isInitializing && !user) {
      openAuthModal();
    }
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
            <p className="text-xl font-bold">
              YOU ARE SUCCESSFULLY LOGGED IN TO THE GENSYN TESTNET
            </p>
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

echo -e "${GREEN}[7/9] Running ./run_rl_swarm.sh in a screen session...${NC}"
screen -dmS gensyn ./run_rl_swarm.sh

echo -e "${GREEN}[8/9] Installing localtunnel (if not installed)...${NC}"
npm install -g localtunnel

echo -e "${GREEN}[9/9] Starting localtunnel on port 3000...${NC}"
screen -dmS lt bash -c 'lt --port 3000 > lt_output.txt'
sleep 6

LT_URL=$(grep -o 'https://[^ ]*' lt_output.txt | head -n1)
rm lt_output.txt

IP=$(curl -s ifconfig.me)

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Localtunnel URL: ${LT_URL}${NC}"
echo -e "${GREEN}Use this IP as password during login: ${IP}${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}🎥 What's Next? Watch this guide to continue:${NC}"
echo -e "${GREEN}https://www.youtube.com/watch?v=dQw4w9WgXcQ${NC}"
echo -e "${GREEN}======================================================${NC}"
