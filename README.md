# GENSYN Setup Guide

This guide walks you through setting up gensyn.

---

## Step 1: Install Dependencies

Update and upgrade your system, then install required packages:

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt install nano curl screen git -y
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

**Note:** Press `Ctrl+A` then `D` to detach from the screen session. Reconnect later using:

```bash
screen -r gensyn
```



**Note:** Run only if the screen shows current_batch variable error:

```bash
chmod +x $HOME/gensyn-script/batch_error.sh
$HOME/gensyn-script/batch_error.sh
```
