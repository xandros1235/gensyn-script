# GENSYN Setup Guide

This guide walks you through setting up gensyn.

---

## Step 1: Install Dependencies

Update and upgrade your system, then install required packages:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install nano curl screen git ufw -y
```
---

If sudo: command not found:
```bash
apt install sudo
```
---

## Step 2: Clone the Repository

```bash
git clone https://github.com/CodeDialect/gensyn-script.git
cd gensyn-script
```

## If above command giving you error file already exits then run below command first then run the Step 2 else don't run below command

```bash
rm -rf gensyn-script
```

---

## Step 3: Make Scripts Executable

```bash
chmod +x setup_gensyn.sh
```

---

If you are using vps then
## Step 4: Enable Firewall & Open Required Ports

```bash
# Basic SSH Access
sudo ufw allow 22
sudo ufw allow ssh
sudo ufw allow 3000

# Enable Firewall
sudo ufw enable
```
---

## Step 5: Run the GENSYN

```bash
./setup_gensyn.sh
```
---

## Fix RuntimeError: DHTNode bootstrap failed

Full error:
> **RuntimeError: DHTNode bootstrap failed: none of the initial_peers responded to the ping. (set ensure_bootstrap_success=False to ignore)**

1. Open the file `testnet_grpo_runner.py`
``` bash
nano $HOME/rl-swarm/hivemind_exp/runner/gensyn/testnet_grpo_runner.py
```

3. Find the line:
`dht = hivemind.DHT(start=True, **self._dht_kwargs(grpo_args))`

4. Replace it with:
```dht = hivemind.DHT(start=True, ensure_bootstrap_success=False, **self._dht_kwargs(grpo_args))```

5. Save your changes and exit the editor:
Press `Ctrl+X` and press `Y` to exit.

6. Go to your screen
```screen -r swarm```

7. Restart the node
Press `Ctrl + C`.
Run command:
```./run_rl_swarm.sh```


**Note:** Press `Ctrl+A` then `D` to detach from the screen session. Reconnect later using:

```bash
screen -r gensyn
```
