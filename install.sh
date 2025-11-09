#!/usr/bin/env bash
#
# EliasMiner v3.2 - Smart Auto Mining Installer
# Author: Elias
# Description: Automatic optimized CPU mining setup using XMRig with smart CPU analysis (no benchmark needed)
#

set -euo pipefail
IFS=$'\n\t'

# ---------- Styling ----------
BOLD="\e[1m"; RESET="\e[0m"
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"
info(){ printf "${CYAN}💡 %s${RESET}\n" "$1"; }
ok(){ printf "${GREEN}✅ %s${RESET}\n" "$1"; }
warn(){ printf "${YELLOW}⚠️  %s${RESET}\n" "$1"; }
err(){ printf "${RED}❌ %s${RESET}\n" "$1"; }

# ---------- Check root ----------
if [[ $EUID -ne 0 ]]; then
  err "Run as root: sudo bash install.sh"
  exit 1
fi

# ---------- Paths ----------
XMRIG_DIR="/opt/xmrig"
CONF_FILE="$XMRIG_DIR/.elias_config"
LOG_FILE="$XMRIG_DIR/setup.log"
SYSTEMD_SERVICE="/etc/systemd/system/xmrig-elias@.service"
MONITOR_SERVICE="/etc/systemd/system/elias-monitor.service"
USER="miner"

mkdir -p "$XMRIG_DIR" && touch "$LOG_FILE"

echo -e "${BOLD}${CYAN}───────────────────────────────────────────────"
echo -e " 💎 EliasMiner v3.2 - Smart CPU Auto Setup"
echo -e "───────────────────────────────────────────────${RESET}"

# ---------- Coin Selection ----------
if [[ -f "$CONF_FILE" ]]; then
  source "$CONF_FILE"
  info "Using existing configuration."
else
  echo -e "${CYAN}Select coin to mine:${RESET}"
  echo " [1] TRX  (Tron)"
  echo " [2] BTC  (Bitcoin)"
  echo " [3] ETH  (Ethereum)"
  echo " [4] LTC  (Litecoin)"
  echo " [5] DOGE (Dogecoin)"
  echo " [6] SHIB (Shiba Inu)"
  echo " [7] XRP  (Ripple)"
  echo " [8] BNB  (Binance Coin)"
  echo " [9] USDT (Tether)"
  echo " [10] ADA (Cardano)"
  echo " [11] XMR (Monero)"
  echo " [12] SOL (Solana)"
  echo " [13] AVAX (Avalanche)"
  echo " [14] MATIC (Polygon)"
  echo " [15] DOT (Polkadot)"
  read -rp "👉 Enter number [default=1]: " choice
  case "${choice:-1}" in
    1|"") COIN="TRX" ;;
    2) COIN="BTC" ;;
    3) COIN="ETH" ;;
    4) COIN="LTC" ;;
    5) COIN="DOGE" ;;
    6) COIN="SHIB" ;;
    7) COIN="XRP" ;;
    8) COIN="BNB" ;;
    9) COIN="USDT" ;;
    10) COIN="ADA" ;;
    11) COIN="XMR" ;;
    12) COIN="SOL" ;;
    13) COIN="AVAX" ;;
    14) COIN="MATIC" ;;
    15) COIN="DOT" ;;
    *) COIN="TRX" ;;
  esac
  read -rp "Wallet address (no prefix): " WALLET
  if [[ -z "$WALLET" ]]; then err "Wallet required."; exit 1; fi
  echo "COIN=\"$COIN\"" > "$CONF_FILE"
  echo "WALLET=\"$WALLET\"" >> "$CONF_FILE"
fi

ok "Selected coin: $COIN"
ok "Wallet: ${WALLET:0:10}..."

# ---------- Install dependencies ----------
info "Installing dependencies..."
apt update -y >> "$LOG_FILE" 2>&1
apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev \
pkg-config wget curl jq bc lm-sensors util-linux netcat-openbsd linux-tools-common linux-tools-generic >> "$LOG_FILE" 2>&1
ok "Dependencies installed."

# ---------- User setup ----------
if ! id -u "$USER" >/dev/null 2>&1; then
  info "Creating user '$USER'"
  useradd -m -s /bin/bash "$USER"
fi

# ---------- Build XMRig ----------
if [[ ! -x "$XMRIG_DIR/xmrig" ]]; then
  info "Building XMRig..."
  TMP=$(mktemp -d)
  pushd "$TMP" >/dev/null
  git clone https://github.com/xmrig/xmrig.git >> "$LOG_FILE" 2>&1
  mkdir xmrig/build && cd xmrig/build
  cmake .. >> "$LOG_FILE" 2>&1
  make -j$(nproc) >> "$LOG_FILE" 2>&1
  cp xmrig "$XMRIG_DIR/"
  popd >/dev/null
  rm -rf "$TMP"
  chown -R "$USER":"$USER" "$XMRIG_DIR"
  ok "XMRig built successfully."
else
  ok "Using existing XMRig binary."
fi

# ---------- Detect country & best pool ----------
info "Detecting location & selecting best pool..."
COUNTRY=$(curl -s ipinfo.io/country || echo "EU")
POOLS=("rx-eu.unmineable.com:443" "rx-us.unmineable.com:443" "rx-asia.unmineable.com:443" "rx-br.unmineable.com:443" "rx-au.unmineable.com:443")
BEST_POOL="rx-eu.unmineable.com:443"
BEST_LAT=99999

for p in "${POOLS[@]}"; do
  HOST=${p%%:*}
  PORT=${p##*:}
  START=$(date +%s%3N)
  if echo > /dev/tcp/$HOST/$PORT 2>/dev/null; then
    END=$(date +%s%3N)
    LAT=$((END - START))
    [[ $LAT -lt $BEST_LAT ]] && BEST_LAT=$LAT && BEST_POOL=$p
  fi
done

ok "Selected pool: $BEST_POOL (latency: ${BEST_LAT}ms)"

# ---------- Enable HugePages & Governor ----------
sysctl -w vm.nr_hugepages=$(nproc) >> "$LOG_FILE" 2>&1
ok "HugePages enabled."
cpupower frequency-set -g performance >/dev/null 2>&1 || true
ok "Governor set to performance (if supported)."

# ---------- Smart CPU analysis (no benchmark) ----------
info "Analyzing CPU cores using lscpu..."
PHYSICAL_CORES=$(lscpu | awk -F: '/Core\(s\) per socket/ {c=$2} /Socket\(s\)/ {s=$2} END{print c*s}' | xargs)
LOGICAL_CORES=$(nproc)
if [[ -z "$PHYSICAL_CORES" || "$PHYSICAL_CORES" -le 0 ]]; then
  PHYSICAL_CORES=$LOGICAL_CORES
fi
if [[ "$PHYSICAL_CORES" -gt 1 ]]; then
  THREADS=$((PHYSICAL_CORES - 1))
else
  THREADS=1
fi
if grep -q avx2 /proc/cpuinfo; then
  BOOST="AVX2"
elif grep -q sse4_2 /proc/cpuinfo; then
  BOOST="SSE4.2"
else
  BOOST="Generic"
fi

ok "CPU Model: $(lscpu | awk -F: '/Model name/ {print $2}' | xargs)"
ok "Cores detected: $PHYSICAL_CORES physical / $LOGICAL_CORES logical"
ok "Feature set: $BOOST"
ok "Recommended threads: $THREADS"

# ---------- Generate config ----------
cat > "$XMRIG_DIR/config-Elias1.json" <<EOF
{
 "autosave": true,
 "cpu": { "enabled": true, "huge-pages": true, "max-threads-hint": $THREADS },
 "pools": [
   {
     "algo": "rx",
     "url": "$BEST_POOL",
     "user": "$COIN:$WALLET.Elias1",
     "pass": "x",
     "keepalive": true,
     "tls": true
   }
 ]
}
EOF
chown "$USER":"$USER" "$XMRIG_DIR/config-Elias1.json"

# ---------- systemd services ----------
cat > "$SYSTEMD_SERVICE" <<'SERVICE'
[Unit]
Description=Elias XMRig instance %i
After=network.target

[Service]
User=miner
WorkingDirectory=/opt/xmrig
ExecStart=/opt/xmrig/xmrig -c /opt/xmrig/config-Elias%i.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable xmrig-elias@1.service --now
ok "Mining service started."

# ---------- Auto monitor ----------
cat > "$XMRIG_DIR/elias_monitor.sh" <<'MON'
#!/usr/bin/env bash
while true; do
  for u in $(systemctl list-units --type=service --no-legend 'xmrig-elias@*' | awk '{print $1}'); do
    if ! systemctl is-active --quiet "$u"; then
      systemctl restart "$u"
    fi
  done
  sleep 30
done
MON

chmod +x "$XMRIG_DIR/elias_monitor.sh"

cat > "$MONITOR_SERVICE" <<'MONS'
[Unit]
Description=EliasMiner Auto Monitor
After=network.target

[Service]
User=miner
ExecStart=/opt/xmrig/elias_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
MONS

systemctl enable --now elias-monitor.service

# ---------- Summary ----------
echo -e "${GREEN}┌────────────────────────────────────────────┐${RESET}"
echo -e "${GREEN}│ 🚀 EliasMiner v3.2 - Setup Complete!       │${RESET}"
echo -e "${GREEN}└────────────────────────────────────────────┘${RESET}"
echo -e "${CYAN}Coin:${RESET} $COIN"
echo -e "${CYAN}Pool:${RESET} $BEST_POOL"
echo -e "${CYAN}Threads:${RESET} $THREADS"
echo -e "${CYAN}Service:${RESET} xmrig-elias@1.service"
echo -e "${CYAN}Monitor:${RESET} elias-monitor.service"
echo -e "${CYAN}Logs:${RESET} journalctl -u xmrig-elias@1 -f"
echo -e "${CYAN}Uninstall:${RESET} sudo rm -rf /opt/xmrig /etc/systemd/system/xmrig-elias@.service /etc/systemd/system/elias-monitor.service"
ok "Mining started automatically and enabled on boot!"
