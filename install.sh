#!/bin/bash
# ==========================================================
# 💎 EliasMiner v3.5 – Smart Integrated Edition
# Author: Elias
# GitHub: https://github.com/abu-elias/EliasMiner
# ==========================================================

CYAN=$(tput setaf 6); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); RESET=$(tput sgr0); BOLD=$(tput bold)

clear
echo -e "${CYAN}"
echo "───────────────────────────────────────────────"
echo "      💎  E L I A S   M I N E R  v3.5"
echo "───────────────────────────────────────────────"
echo -e "${RESET}${BOLD}Smart Auto Miner + Telegram Integration${RESET}\n"

# ---------- System Preparation ----------
echo -e "${CYAN}⚙️ Updating packages and installing dependencies...${RESET}"
apt update -y >/dev/null 2>&1
apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev curl >/dev/null 2>&1
echo -e "${GREEN}✅ System ready.${RESET}\n"

# ---------- Choose Coin ----------
echo -e "${CYAN}💎 Choose the coin you want to mine${RESET}"
echo "───────────────────────────────────────────────"
coins=("TRX" "BTC" "ETH" "LTC" "DOGE" "SHIB" "XRP" "BNB" "USDT" "ADA" "XMR" "SOL" "AVAX" "MATIC" "DOT")
for i in "${!coins[@]}"; do
    printf " [%d] %s\n" $((i+1)) "${coins[$i]}"
done
echo "───────────────────────────────────────────────"
read -rp "Enter number [default=1]: " choice
choice=${choice:-1}
COIN=${coins[$((choice-1))]}
echo -e "${GREEN}✅ Selected coin: $COIN${RESET}"

# ---------- Wallet ----------
read -rp "💰 Enter your wallet address: " WALLET
if [ -z "$WALLET" ]; then
    echo -e "${RED}❌ Wallet is required.${RESET}"
    exit 1
fi

# ---------- Worker Smart Name ----------
HOST_ID=$(hostname | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
DATE_ID=$(date +%d%b)
HASH_ID=$(echo "$HOSTNAME-$RANDOM-$(date +%s)" | md5sum | cut -c1-4 | tr '[:lower:]' '[:upper:]')
DEFAULT_WORKER="Elias-${COIN}-${HOST_ID}-${DATE_ID}-${HASH_ID}"
read -rp "🖥️ Enter worker name [default=$DEFAULT_WORKER]: " WORKER
WORKER=${WORKER:-$DEFAULT_WORKER}
echo -e "${GREEN}✅ Worker set to: $WORKER${RESET}\n"

# ---------- Download and Build XMRig ----------
echo -e "${CYAN}⬇️ Downloading & building XMRig...${RESET}"
mkdir -p /opt/xmrig && cd /opt/xmrig || exit
git clone https://github.com/xmrig/xmrig.git src >/dev/null 2>&1
mkdir -p src/build && cd src/build
cmake .. >/dev/null 2>&1
make -j$(nproc) >/dev/null 2>&1
cd /opt/xmrig
XMRIG_PATH="/opt/xmrig/src/build/xmrig"
echo -e "${GREEN}✅ XMRig built successfully.${RESET}\n"

# ---------- Auto Detect CPU & Threads ----------
CORES=$(lscpu | awk '/^CPU\(s\):/{print $2}')
THREADS=$((CORES - 1))
echo -e "${GREEN}🧠 CPU detected: $CORES cores, using $THREADS threads.${RESET}\n"

# ---------- Enable HugePages ----------
sysctl -w vm.nr_hugepages=128 >/dev/null 2>&1
echo "vm.nr_hugepages=128" >> /etc/sysctl.conf
echo -e "${GREEN}✅ HugePages enabled.${RESET}\n"

# ---------- Auto Detect Region ----------
COUNTRY=$(curl -s ipinfo.io/country || echo "US")
case $COUNTRY in
    "BR") POOL="rx-br.unmineable.com:443";;
    "EU"|"GB"|"FR"|"DE") POOL="rx-eu.unmineable.com:443";;
    "US") POOL="rx-us.unmineable.com:443";;
    "SG"|"IN") POOL="rx-asia.unmineable.com:443";;
    *) POOL="rx-eu.unmineable.com:443";;
esac
echo -e "${GREEN}🌍 Pool selected: $POOL${RESET}\n"

# ---------- Generate Config ----------
tee /opt/xmrig/config.json >/dev/null <<EOF
{
    "autosave": true,
    "cpu": { "enabled": true, "threads": ${THREADS} },
    "donate-level": 1,
    "pools": [
        { "url": "$POOL", "user": "${COIN}:$WALLET.$WORKER", "pass": "x", "keepalive": true, "tls": true }
    ]
}
EOF
echo -e "${GREEN}✅ Config created.${RESET}\n"

# ---------- Create Mining Service ----------
tee /etc/systemd/system/xmrig-elias@.service >/dev/null <<EOF
[Unit]
Description=EliasMiner %i
After=network.target

[Service]
ExecStart=$XMRIG_PATH -c /opt/xmrig/config.json
WorkingDirectory=/opt/xmrig
Restart=always
RestartSec=10
Nice=10
CPUWeight=90

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xmrig-elias@1.service >/dev/null 2>&1
echo -e "${GREEN}✅ Mining service started.${RESET}\n"

# ---------- Save Info ----------
echo "COIN=$COIN" > /opt/xmrig/.elias_config
echo "WALLET=$WALLET" >> /opt/xmrig/.elias_config
echo "WORKER=$WORKER" >> /opt/xmrig/.elias_config

# ---------- Install Telegram Bot ----------
echo ""
read -rp "💬 Do you want to install Telegram Control Bot? (Y/n): " INSTALL_BOT
INSTALL_BOT=${INSTALL_BOT:-Y}
if [[ "$INSTALL_BOT" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}🚀 Installing Telegram Bot...${RESET}"
    bash <(curl -s https://raw.githubusercontent.com/abu-elias/EliasMiner/main/install_bot.sh)
else
    echo -e "${YELLOW}⏩ Skipped Telegram Bot installation.${RESET}"
fi

# ---------- Done ----------
echo -e "${CYAN}───────────────────────────────────────────────${RESET}"
echo -e "${GREEN}✅ Setup Complete!"
echo -e "Coin: $COIN"
echo -e "Worker: $WORKER"
echo -e "Service: xmrig-elias@1.service"
echo -e "Logs: journalctl -u xmrig-elias@1 -f"
echo -e "${CYAN}───────────────────────────────────────────────${RESET}"
echo -e "${GREEN}💎 Happy Mining, Elias!${RESET}\n"
