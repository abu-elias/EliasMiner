#!/bin/bash
# ==========================================
# 💎 EliasMiner v3.4 - Smart Monitor Edition
# Author: Elias
# ==========================================

# ---------- STYLING ----------
RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6); MAGENTA=$(tput setaf 5); RESET=$(tput sgr0); BOLD=$(tput bold)
spinner() { local pid=$!; local spin='🌑🌒🌓🌔🌕🌖🌗🌘'; local i=0
while kill -0 $pid 2>/dev/null; do i=$(((i + 1) % 8))
printf "\r${CYAN}${spin:$i:1}${RESET} Installing..."; sleep 0.1; done
printf "\r${GREEN}✅ Done!${RESET}\n"; }

banner() {
clear; echo -e "${CYAN}"
echo "───────────────────────────────────────────────"
echo "        💎 E L I A S  M I N E R  v3.4"
echo "───────────────────────────────────────────────"
echo -e "${RESET}${BOLD}Smart. Fast. Auto-Healing.${RESET}\n"
sleep 0.5; }

ok() { echo -e " ${GREEN}✅${RESET} $1"; }
info() { echo -e " ${CYAN}💡${RESET} $1"; }
warn() { echo -e " ${YELLOW}⚠️${RESET} $1"; }
err() { echo -e " ${RED}❌${RESET} $1"; }

banner

# ---------- CONFIG DETECTION ----------
CONFIG_FILE="/opt/xmrig/.elias_config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    echo -e "${YELLOW}Using existing configuration...${RESET}"
else
    echo ""
    echo -e "${BOLD}${MAGENTA}Let's set up your miner!${RESET}\n"
    echo "───────────────────────────────────────────────"
    echo " 💎 Choose the coin you want to mine"
    echo "───────────────────────────────────────────────"
    echo " [1] TRX | [2] BTC | [3] ETH | [4] LTC"
    echo " [5] DOGE | [6] SHIB | [7] XRP | [8] BNB"
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

# ---------- SMART WORKER NAME ----------
HOST_ID=$(hostname | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
DATE_ID=$(date +%d%b)
HASH_ID=$(echo "$HOSTNAME-$RANDOM-$(date +%s)" | md5sum | cut -c1-4 | tr '[:lower:]' '[:upper:]')
DEFAULT_WORKER="Elias-${COIN}-${HOST_ID}-${DATE_ID}-${HASH_ID}"
read -rp "Enter Worker name [default=$DEFAULT_WORKER]: " WORKER
WORKER=${WORKER:-$DEFAULT_WORKER}
ok "Selected Worker name: $WORKER"

mkdir -p /opt/xmrig
echo "COIN=$COIN" > /opt/xmrig/.elias_config
echo "WALLET=$WALLET" >> /opt/xmrig/.elias_config
echo "WORKER=$WORKER" >> /opt/xmrig/.elias_config

# ---------- INSTALL DEPENDENCIES ----------
info "Installing dependencies..."
(apt update -y && apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev curl jq > /dev/null 2>&1) & spinner

# ---------- BUILD OR DETECT XMRIG ----------
info "Building or detecting XMRig..."
mkdir -p /opt/xmrig && cd /opt/xmrig
if [ ! -f /opt/xmrig/xmrig ] && [ ! -f /opt/xmrig/build/xmrig ] && [ ! -f /opt/xmrig/src/build/xmrig ]; then
    git clone https://github.com/xmrig/xmrig.git src > /dev/null 2>&1
    mkdir -p src/build && cd src/build
    cmake .. > /dev/null 2>&1 && make -j$(nproc) > /dev/null 2>&1 & spinner
else
    ok "Using existing XMRig files."
fi

# Auto detect build path
if [ -f /opt/xmrig/build/xmrig ]; then
  XMRIG_PATH="/opt/xmrig/build/xmrig"
elif [ -f /opt/xmrig/src/build/xmrig ]; then
  XMRIG_PATH="/opt/xmrig/src/build/xmrig"
else
  XMRIG_PATH="$(find /opt/xmrig -type f -name xmrig | head -n 1)"
fi
ok "Detected xmrig path: $XMRIG_PATH"

# ---------- AUTO POOL ----------
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
info "Analyzing CPU cores..."
PHYSICAL_CORES=$(lscpu | awk -F: '/Core\(s\) per socket/ {c=$2} /Socket\(s\)/ {s=$2} END{print c*s}' | xargs)
LOGICAL_CORES=$(nproc)
[ -z "$PHYSICAL_CORES" ] && PHYSICAL_CORES=$LOGICAL_CORES
THREADS=$((PHYSICAL_CORES>1 ? PHYSICAL_CORES-1 : 1))
if grep -q avx2 /proc/cpuinfo; then BOOST="AVX2"; elif grep -q sse4_2 /proc/cpuinfo; then BOOST="SSE4.2"; else BOOST="Generic"; fi
ok "CPU: $(lscpu | awk -F: '/Model name/ {print $2}' | xargs)"
ok "Threads: $THREADS | Feature: $BOOST"

# ---------- CONFIG ----------
cat > /opt/xmrig/config.json <<EOF
{
  "autosave": true,
  "cpu": { "enabled": true, "huge-pages": true, "max-threads-hint": 100 },
  "pools": [{
    "algo": "rx/0",
    "url": "$POOL",
    "user": "$COIN:$WALLET.$WORKER",
    "pass": "x",
    "tls": true
  }]
}
EOF
ok "Config created."

# ---------- SYSTEMD SERVICE ----------
cat > /etc/systemd/system/xmrig-elias@.service <<EOF
[Unit]
Description=EliasMiner %i
After=network.target

[Service]
ExecStart=$XMRIG_PATH -c /opt/xmrig/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ---------- MONITOR SERVICE ----------
cat > /etc/systemd/system/elias-monitor.service <<EOF
[Unit]
Description=EliasMiner Auto Monitor
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c '
  while true; do
    HASH=\$(grep "speed 10s" /var/log/syslog | tail -n1 | awk "{print \$9}")
    if [ -z "\$HASH" ] || [ "\$HASH" -lt 100 ]; then
      echo "\$(date) - Low hashrate detected (\$HASH). Restarting miner..." >> /opt/xmrig/hashrate.log
      systemctl restart xmrig-elias@1
    else
      echo "\$(date) - Hashrate OK: \$HASH H/s" >> /opt/xmrig/hashrate.log
    fi
    sleep 60
  done'
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# ---------- ENABLE SERVICES ----------
systemctl daemon-reload
systemctl enable xmrig-elias@1.service > /dev/null 2>&1
systemctl start xmrig-elias@1.service
systemctl enable elias-monitor.service > /dev/null 2>&1
systemctl start elias-monitor.service

# ---------- SUMMARY ----------
echo ""
echo -e "${CYAN}┌────────────────────────────────────────────┐${RESET}"
echo -e "${CYAN}│ 🚀 ${BOLD}EliasMiner v3.4 - Setup Complete!${RESET}${CYAN}       │${RESET}"
echo -e "${CYAN}└────────────────────────────────────────────┘${RESET}"
echo " Coin     : $COIN"
echo " Pool     : $POOL"
echo " Worker   : $WORKER"
echo " Threads  : $THREADS"
echo "---------------------------------------------"
echo " 🧠  Miner   : xmrig-elias@1.service"
echo " 🧩  Monitor : elias-monitor.service"
echo " 📊  Log     : /opt/xmrig/hashrate.log"
echo "---------------------------------------------"
ok "Mining started automatically and monitored in real-time!"
echo -e "${MAGENTA}${BOLD}💎 Happy Mining, Elias! 💎${RESET}\n"
