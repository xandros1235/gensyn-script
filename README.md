# GENSYN Setup Guide

This guide walks you through setting up gensyn.

---

## Step 1: Install Dependencies

Update and upgrade your system, then install required packages:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install nano curl screen git -y
```

If you get `sudo: command not found`, install sudo:

```bash
apt install sudo -y
```

---

## Step 2: Clone the Repository

```bash
git clone https://github.com/CodeDialect/gensyn-script.git
cd gensyn-script
```

---

## Step 3: Make Scripts Executable

```bash
chmod +x setup_gensyn.sh
```

---

If you are using vps then
## Step 6: Enable Firewall & Open Required Ports

```bash
# Basic SSH Access
ufw allow 22
ufw allow ssh
ufw allow 3000

# Enable Firewall
ufw enable
```
---

## Step 8: Run the GENSYN

```bash
./setup_gensyn.sh
```
---

**Note:** Press `Ctrl+A` then `D` to detach from the screen session. Reconnect later using:

```bash
screen -r aztec
```
