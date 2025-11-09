#!/bin/bash
# ==========================================
#  💎 EliasMiner v3.3 - Smart Unique Worker Edition
#  Author: Elias
# ==========================================

# ---------- STYLING & UTILS ----------
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
RESET=$(tput sgr0)
BOLD=$(tput bold)

spinner() {
    local pid=$!
    local spin='🌑🌒🌓🌔🌕🌖🌗🌘'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 8))
        printf "\r${CYAN}${spin:$i:1}${RESET} Installing..."
        sleep 0.1
    done
    printf "\r${GREEN}✅ Done!${RESET}\n"
}

banner() {
    clear
    echo -e "${CYAN}"
    echo "───────────────────────────────────────────────"
    echo "        💎 E L I A S  M I N E R  v3.3"
    echo "───────────────────────────────────────────────"
    echo -e "${RESET}${BOLD}Smart. Fast. Beautiful.${RESET}\n"
    sleep 0.5
}

ok()   { echo -e " ${GREEN}✅${RESET} $1"; }
info() { echo -e " ${CYAN}💡${RESET} $1"; }
warn() { echo -e " ${YELLOW}⚠️${RESET} $1"; }
err()  { echo -e " ${RED}❌${RESET} $1"; }

banner

# ---------- CHECK PREVIOUS CONFIG ----------
CONFIG_FILE="/opt/xmrig/.elias_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${YELLOW}Using existing configuration...${RESET}"
    sleep 1
else
    echo ""
    echo -e "${BOLD}${MAGENTA}Let's set up your miner step by step!${RESET}\n"
    echo "───────────────────────────────────────────────"
    echo " 💎 Choose the coin you want to mine"
    echo "───────────────────────────────────────────────"
    echo " [1] TRX  | [2] BTC  | [3] ETH  | [4] LTC"
    echo " [5] DOGE | [6] SHIB | [7] XRP  | [8] BNB"
    echo " [9] USDT | [10] ADA | [11] XMR | [12] SOL"
    echo "───────────────────────────────────────────────"
    read -rp "👉 Enter number [default=1]: " CHOICE
    CHOICE=${CHOICE:-1}
    COINS=(TRX BTC ETH LTC DOGE SHIB XRP BNB USDT ADA XMR SOL)
    COIN=${COINS[$((CHOICE-1))]}
    echo ""
    read -rp "💰 Wallet address (no prefix): " WALLET
    info "Coin selected: $COIN"
    info "Wallet starts with: ${WALLET:0:10}..."
fi

# ---------- SMART UNIQUE WORKER NAME ----------
echo ""
echo "───────────────────────────────────────────────"
echo " 💡 Worker Naming Setup"
echo "───────────────────────────────────────────────"
HOST_ID=$(hostname | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
DATE_ID=$(date +%d%b)
HASH_ID=$(echo "$HOSTNAME-$RANDOM-$(date +%s)" | md5sum | cut -c1-4 | tr '[:lower:]' '[:upper:]')
DEFAULT_WORKER="Elias-${COIN}-${HOST_ID}-${DATE_ID}-${HASH_ID}"
read -rp "Enter a name for this Worker [default=$DEFAULT_WORKER]: " WORKER
WORKER=${WORKER:-$DEFAULT_WORKER}
ok "Selected Worker name: ${BOLD}${WORKER}${RESET}"

mkdir -p /opt/xmrig
echo "COIN=$COIN" > /opt/xmrig/.elias_config
echo "WALLET=$WALLET" >> /opt/xmrig/.elias_config
echo "WORKER=$WORKER" >> /opt/xmrig/.elias_config

# ---------- INSTALL DEPENDENCIES ----------
info "Installing dependencies..."
(apt update -y && apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev curl jq > /dev/null 2>&1) & spinner

# ---------- INSTALL XMRIG ----------
if [ ! -f /opt/xmrig/xmrig ]; then
    info "Building XMRig..."
    mkdir -p /opt/xmrig && cd /opt/xmrig
    git clone https://github.com/xmrig/xmrig.git src > /dev/null 2>&1
    mkdir build && cd build
    cmake ../src > /dev/null 2>&1 && make -j$(nproc) > /dev/null 2>&1 & spinner
    ok "XMRig built successfully."
else
    ok "Using existing XMRig binary."
fi

# ---------- LOCATION DETECTION ----------
info "Detecting location & selecting best pool..."
LOCATION=$(curl -s ipinfo.io/country)
case "$LOCATION" in
    BR) POOL="rx-br.unmineable.com:443" ;;
    AU) POOL="rx-au.unmineable.com:443" ;;
    US) POOL="rx-us.unmineable.com:443" ;;
    EU|GB|FR|DE) POOL="rx-eu.unmineable.com:443" ;;
    *) POOL="rx-eu.unmineable.com:443" ;;
esac
ok "Detected: ${LOCATION:-Unknown}"
ok "Selected pool: ${POOL}"

# ---------- CPU ANALYSIS ----------
info "Analyzing CPU cores using lscpu..."
PHYSICAL_CORES=$(lscpu | awk -F: '/Core\(s\) per socket/ {c=$2} /Socket\(s\)/ {s=$2} END{print c*s}' | xargs)
LOGICAL_CORES=$(nproc)
[ -z "$PHYSICAL_CORES" ] && PHYSICAL_CORES=$LOGICAL_CORES
THREADS=$((PHYSICAL_CORES>1 ? PHYSICAL_CORES-1 : 1))
if grep -q avx2 /proc/cpuinfo; then
  BOOST="AVX2"
elif grep -q sse4_2 /proc/cpuinfo; then
  BOOST="SSE4.2"
else
  BOOST="Generic"
fi
ok "CPU: $(lscpu | awk -F: '/Model name/ {print $2}' | xargs)"
ok "Cores: $PHYSICAL_CORES | Feature: $BOOST | Threads: $THREADS"

# ---------- CREATE CONFIG ----------
info "Creating optimized config.json..."
cat > /opt/xmrig/config.json <<EOF
{
    "autosave": true,
    "cpu": { "enabled": true, "huge-pages": true, "max-threads-hint": 100 },
    "pools": [
        {
            "algo": "rx/0",
            "coin": null,
            "url": "$POOL",
            "user": "$COIN:$WALLET.$WORKER",
            "pass": "x",
            "tls": true
        }
    ]
}
EOF
ok "Config created."

# ---------- SERVICE SETUP ----------
info "Setting up auto-start service..."
cat > /etc/systemd/system/xmrig-elias@.service <<EOF
[Unit]
Description=EliasMiner %i
After=network.target

[Service]
ExecStart=/opt/xmrig/build/xmrig -c /opt/xmrig/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xmrig-elias@1.service > /dev/null 2>&1
systemctl start xmrig-elias@1.service
ok "Mining service started."

# ---------- COMPLETION ----------
echo ""
echo -e "${CYAN}┌────────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│ 🚀 ${BOLD}EliasMiner v3.3 - Setup Complete!${RESET}${CYAN}       │${RESET}"
echo -e "${CYAN}└────────────────────────────────────────────┘${RESET}"
echo " Coin     : $COIN"
echo " Pool     : $POOL"
echo " Worker   : $WORKER"
echo " Threads  : $THREADS"
echo ""
echo " Service  : xmrig-elias@1.service"
echo " Logs     : journalctl -u xmrig-elias@1 -f"
echo ""
ok "Mining started automatically and enabled on boot!"
echo ""
echo -e "${BOLD}${MAGENTA}💎 Happy Mining, Elias! 💎${RESET}"
