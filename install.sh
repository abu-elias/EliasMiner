#!/usr/bin/env bash
#
# EliasMiner - install.sh (Elias XMRig Auto-Optimizer v3.0 - Ultimate Edition)
# Usage: sudo bash install.sh
#
# What it does (automated):
# - Presents a numbered coin menu (first-run).
# - Installs dependencies, builds XMRig if needed and places it in /opt/xmrig.
# - Creates non-root user "miner" and runs miners under that user.
# - Detects best pool by geo+latency and chooses pool automatically.
# - Enables HugePages and attempts performance governor.
# - Plans CPU split into 1-4 instances and runs quick benchmark to pick best thread split.
# - Creates config-EliasN.json files and systemd units xmrig-elias@<cpu-range>.service.
# - Enables auto-start on boot and starts services.
# - Creates uninstall script /opt/xmrig/uninstall_elias.sh
#
# IMPORTANT:
# - Run as root (sudo).
# - This script tries to be safe: it runs miners as a non-root user "miner".
# - Adjust variables inside the script if you need custom paths.
#
set -euo pipefail
IFS=$'\n\t'

# ---------- Simple styling ----------
BOLD="\e[1m"; RESET="\e[0m"
GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; CYAN="\e[36m"
info(){ printf "${BOLD}${CYAN}[INFO]${RESET} %s\n" "$1"; }
ok(){ printf "${BOLD}${GREEN}[OK]${RESET} %s\n" "$1"; }
warn(){ printf "${BOLD}${YELLOW}[WARN]${RESET} %s\n" "$1"; }
err(){ printf "${BOLD}${RED}[ERROR]${RESET} %s\n" "$1"; }

# ---------- Pre-checks ----------
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root. Use sudo."
  exit 1
fi

# ---------- Defaults & paths ----------
XMRIG_DEST="/opt/xmrig"
MINER_USER="miner"
SYSTEMD_TEMPLATE_PATH="/etc/systemd/system/xmrig-elias@.service"
ELIAS_CONF_FILE="$XMRIG_DEST/.elias_config"
LOG_DIR="$XMRIG_DEST/logs"

# ---------- Coin selection menu ----------
cat <<'MENU'

───────────────────────────────────────────────
 💎 Choose the coin you want to mine (first run)
───────────────────────────────────────────────
 [1] TRX  (Tron)
 [2] BTC  (Bitcoin)
 [3] ETH  (Ethereum)
 [4] LTC  (Litecoin)
 [5] DOGE (Dogecoin)
 [6] SHIB (Shiba Inu)
 [7] XRP  (Ripple)
 [8] BNB  (Binance Coin)
 [9] USDT (Tether)
 [10] ADA (Cardano)
 [11] XMR (Monero)
 [12] SOL (Solana)
 [13] AVAX (Avalanche)
 [14] MATIC (Polygon)
 [15] DOT (Polkadot)
───────────────────────────────────────────────

MENU

# If config exists, read values to avoid asking again
if [[ -f "$ELIAS_CONF_FILE" ]]; then
  source "$ELIAS_CONF_FILE"
  info "Found existing config at $ELIAS_CONF_FILE. Using saved values."
  COIN=${COIN:-TRX}
  WALLET=${WALLET:-""}
else
  read -rp "Enter number [default=1]: " COIN_CHOICE
  case "${COIN_CHOICE:-1}" in
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

  read -rp "Wallet address (no coin prefix) : " WALLET
  if [[ -z "$WALLET" ]]; then
    err "Wallet required. Aborting."
    exit 1
  fi

  # Save config for future runs
  mkdir -p "$XMRIG_DEST"
  cat > "$ELIAS_CONF_FILE" <<EOF
# Elias saved config
COIN="$COIN"
WALLET="$WALLET"
EOF
  ok "Saved selected coin and wallet to $ELIAS_CONF_FILE"
fi

info "Selected coin: $COIN"
info "Wallet (first 10 chars): ${WALLET:0:10}..."

# ---------- Install dependencies ----------
info "Installing packages (apt-get) — this may take a moment..."
apt-get update -y
DEBS=(git build-essential cmake libuv1-dev libssl-dev libhwloc-dev pkg-config wget ca-certificates curl jq bc lm-sensors taskset)
apt-get install -y "${DEBS[@]}"

ok "Packages installed (best-effort)"

# ---------- Create miner user ----------
if ! id -u "$MINER_USER" >/dev/null 2>&1; then
  info "Creating user: $MINER_USER"
  useradd -m -s /bin/bash "$MINER_USER" || true
  ok "User $MINER_USER created"
else
  info "User $MINER_USER already exists"
fi

# ---------- Build or ensure XMRig binary ----------
if [[ ! -x "$XMRIG_DEST/xmrig" ]]; then
  info "XMRig binary not found in $XMRIG_DEST. Building from source..."
  TMPDIR=$(mktemp -d)
  pushd "$TMPDIR" >/dev/null
  git clone https://github.com/xmrig/xmrig.git xmrig-src
  mkdir -p xmrig-src/build
  pushd xmrig-src/build >/dev/null
  cmake .. || { err "cmake failed"; exit 1; }
  make -j"$(nproc)" || { err "make failed"; exit 1; }
  mkdir -p "$XMRIG_DEST"
  cp xmrig "$XMRIG_DEST/"
  popd >/dev/null
  popd >/dev/null
  rm -rf "$TMPDIR"
  chown -R "$MINER_USER":"$MINER_USER" "$XMRIG_DEST"
  chmod +x "$XMRIG_DEST/xmrig"
  ok "Built and installed xmrig to $XMRIG_DEST"
else
  info "Found existing xmrig binary at $XMRIG_DEST/xmrig"
fi

# ---------- Detect public IP / country and choose pool ----------
info "Detecting public IP and country (via ipinfo.io)..."
IPINFO_JSON=$(curl -sS --max-time 6 https://ipinfo.io/json || true)
COUNTRY=$(echo "$IPINFO_JSON" | jq -r .country 2>/dev/null || true)
if [[ -z "$COUNTRY" || "$COUNTRY" == "null" ]]; then
  warn "Couldn't detect country; defaulting to EU pool"
  COUNTRY="EU"
fi
COUNTRY=${COUNTRY^^}
info "Detected country: $COUNTRY"

CANDIDATES=(rx-eu.unmineable.com:443 rx-us.unmineable.com:443 rx-asia.unmineable.com:443 rx-br.unmineable.com:443 rx-au.unmineable.com:443)
PREFERRED=()
case "$COUNTRY" in
  US|CA) PREFERRED=(rx-us.unmineable.com:443 rx-eu.unmineable.com:443 rx-asia.unmineable.com:443) ;;
  BR) PREFERRED=(rx-br.unmineable.com:443 rx-us.unmineable.com:443 rx-eu.unmineable.com:443) ;;
  AU|NZ) PREFERRED=(rx-au.unmineable.com:443 rx-asia.unmineable.com:443) ;;
  CN|JP|KR|IN|SG) PREFERRED=(rx-asia.unmineable.com:443 rx-eu.unmineable.com:443) ;;
  *) PREFERRED=(rx-eu.unmineable.com:443 rx-us.unmineable.com:443) ;;
esac

info "Probing candidate pools for latency (ping). This uses ICMP; may be blocked on some VPS providers."
best_pool=""
best_ms=999999
for p in "${PREFERRED[@]}"; do
  host=${p%%:*}
  ping_out=$(ping -c1 -W1 "$host" 2>/dev/null || true)
  if [[ -n "$ping_out" ]]; then
    rtt=$(echo "$ping_out" | awk -F'/' '/rtt/ {print $5; exit}')
    if [[ -n "$rtt" ]]; then
      rtt_ms=${rtt%.*}
      info "Ping $host => ${rtt} ms"
      # numeric compare
      awk -v a="$rtt" -v b="$best_ms" 'BEGIN{ if(a+0<b+0) exit 0; exit 1 }' && best_pool="$p" && best_ms="$rtt"
    fi
  fi
done
# fallback
if [[ -z "$best_pool" ]]; then best_pool="${PREFERRED[0]}"; fi
ok "Selected pool: $best_pool (approx RTT: ${best_ms} ms)"

# ---------- CPU planning ----------
TOTAL_LOGICAL=$(nproc)
PHYSICAL=$(lscpu | awk -F: '/Core\(s\) per socket/ {c=$2} /Socket\(s\)/ {s=$2} END{gsub(/ /,"",c); gsub(/ /,"",s); if(c!="") print c*s; else print 0}')
if [[ -z "$PHYSICAL" || "$PHYSICAL" -le 0 ]]; then PHYSICAL=$TOTAL_LOGICAL; fi
info "Logical cores: $TOTAL_LOGICAL  |  Physical (approx): $PHYSICAL"

if (( PHYSICAL <= 8 )); then INSTANCES=1
elif (( PHYSICAL <= 16 )); then INSTANCES=2
elif (( PHYSICAL <= 32 )); then INSTANCES=3
else INSTANCES=4
fi
read -rp "Instances to create (recommended $INSTANCES): " UINST
if [[ -n "$UINST" ]]; then INSTANCES=$UINST; fi

THREADS_PER_INSTANCE=$(( PHYSICAL / INSTANCES ))
if (( THREADS_PER_INSTANCE < 1 )); then THREADS_PER_INSTANCE=1; fi
ok "Plan: $INSTANCES instance(s), ~$THREADS_PER_INSTANCE thread(s) each (approx physical cores / instances)"

# ---------- Enable HugePages ----------
info "Enabling HugePages (temporary & persistent)"
sysctl -w vm.nr_hugepages=$(nproc) >/dev/null 2>&1 || true
echo "vm.nr_hugepages=$(nproc)" > /etc/sysctl.d/70-xmrig-hugepages.conf
sysctl --system >/dev/null 2>&1 || true
ok "HugePages configured"

# ---------- Performance governor ----------
info "Attempting to set CPU governor to performance"
if command -v cpupower >/dev/null 2>&1; then
  cpupower frequency-set -g performance >/dev/null 2>&1 || true
elif command -v cpufreq-set >/dev/null 2>&1; then
  cpufreq-set -r -g performance >/dev/null 2>&1 || true
else
  warn "cpupower/cpufreq-set not found; governor may not be changed."
fi
ok "Governor step attempted"

# ---------- Prepare directories & logs ----------
mkdir -p "$LOG_DIR"
chown -R "$MINER_USER":"$MINER_USER" "$XMRIG_DEST" || true
chown -R "$MINER_USER":"$MINER_USER" "$LOG_DIR" || true

# ---------- Quick benchmark function ----------
# Runs xmrig for a short time with given threads and returns reported 10s speed if available.
benchmark_threads(){
  local conf="$1"
  local threads="$2"
  local tmpf
  tmpf=$(mktemp)
  # create ephemeral config based on template but override threads hint
  cat >"$conf" <<EOF
{
  "autosave": true,
  "donate-level": 1,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-threads-hint": $threads,
    "priority": 5
  },
  "pools": [
    {
      "algo": "rx",
      "url": "$best_pool",
      "user": "$COIN:$WALLET.bench",
      "pass": "x",
      "keepalive": true,
      "tls": true
    }
  ]
}
EOF
  # run xmrig briefly
  timeout 12s "$XMRIG_DEST/xmrig" -c "$conf" > "$tmpf" 2>&1 || true
  # parse last reported 10s speed (line contains "speed 10s")
  local speed
  speed=$(awk '/speed 10s/ {print $(NF-2); exit}' "$tmpf" | tr -d ',')
  rm -f "$tmpf"
  printf "%s" "${speed:-0}"
}

# ---------- Benchmark to adjust threads-per-instance (optional quick test) ----------
info "Running quick benchmark to finetune threads per instance (short tests)..."
# We'll test THREADS_PER_INSTANCE and THREADS_PER_INSTANCE-1 if applicable, take best.
TMP_BENCH_CONF="/tmp/bench-xmrig.conf"
BEST_THREADS=$THREADS_PER_INSTANCE
BEST_SPEED=0
CAND_THREADS=("$THREADS_PER_INSTANCE")
if (( THREADS_PER_INSTANCE > 1 )); then CAND_THREADS+=($((THREADS_PER_INSTANCE-1))); fi
if (( THREADS_PER_INSTANCE < PHYSICAL )); then CAND_THREADS+=($((THREADS_PER_INSTANCE+1))); fi

for t in "${CAND_THREADS[@]}"; do
  info "Benchmarking with $t threads..."
  s=$(benchmark_threads "$TMP_BENCH_CONF" "$t")
  info " -> reported speed: ${s} H/s (10s sample)"
  # numeric compare
  awk -v a="$s" -v b="$BEST_SPEED" 'BEGIN{ if(a+0>b+0) exit 0; exit 1 }' && { BEST_SPEED="$s"; BEST_THREADS="$t"; }
done

THREADS_PER_INSTANCE="$BEST_THREADS"
ok "Chosen threads per instance: $THREADS_PER_INSTANCE (benchmark est: ${BEST_SPEED} H/s)"

# ---------- Generate config files Elias1..N ----------
info "Generating config files for each Elias instance..."
for i in $(seq 1 $INSTANCES); do
  CONF="$XMRIG_DEST/config-Elias${i}.json"
  WORKER_NAME="Elias${i}"
  cat > "$CONF" <<EOF
{
  "autosave": true,
  "donate-level": 1,
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-threads-hint": $THREADS_PER_INSTANCE,
    "priority": 5
  },
  "pools": [
    {
      "algo": "rx",
      "url": "$best_pool",
      "user": "$COIN:$WALLET.$WORKER_NAME",
      "pass": "x",
      "keepalive": true,
      "tls": true
    }
  ]
}
EOF
  chown "$MINER_USER":"$MINER_USER" "$CONF" || true
  ok "Created $CONF (worker: $WORKER_NAME)"
done

# ---------- systemd template service (non-root miner user) ----------
info "Writing systemd template: $SYSTEMD_TEMPLATE_PATH"
cat > "$SYSTEMD_TEMPLATE_PATH" <<'SERVICE'
[Unit]
Description=Elias XMRig instance for CPU range %i
After=network.target

[Service]
Type=simple
User=miner
WorkingDirectory=/opt/xmrig
# %i is CPU-range like 0-3; systemd will substitute
ExecStart=/usr/bin/taskset -c %i /opt/xmrig/xmrig -c /opt/xmrig/config-Elias%i.json
Restart=always
RestartSec=10
Nice=-10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
ok "Systemd template written"

# ---------- Enable and start units using CPU ranges ----------
info "Enabling and starting systemd units for each instance (CPU pinning ranges)"
CORES_PER_INSTANCE=$(( PHYSICAL / INSTANCES ))
START=0
for i in $(seq 1 $INSTANCES); do
  END=$(( START + CORES_PER_INSTANCE - 1 ))
  # clamp to available logical cores
  if (( END >= TOTAL_LOGICAL )); then END=$(( TOTAL_LOGICAL - 1 )); fi
  RANGE="${START}-${END}"
  systemctl enable "xmrig-elias@${RANGE}.service" --now || true
  ok "Enabled and started xmrig-elias@${RANGE}.service"
  START=$(( END + 1 ))
done

# ---------- Self-monitor systemd unit (optional lightweight) ----------
# Create a small monitor service that ensures units are active; will restart unit(s) if they fail repeatedly.
MONITOR_PATH="/opt/xmrig/elias_monitor.sh"
cat > "$MONITOR_PATH" <<'MON'
#!/usr/bin/env bash
# Simple monitor: if any xmrig-elias@*.service is not active, attempt restart
while true; do
  for unit in $(systemctl list-units --type=service --no-legend 'xmrig-elias@*' | awk '{print $1}'); do
    state=$(systemctl is-active "$unit" || true)
    if [[ "$state" != "active" ]]; then
      echo "$(date) - $unit state=$state - attempting restart"
      systemctl restart "$unit"
    fi
  done
  sleep 30
done
MON
chmod +x "$MONITOR_PATH"
chown "$MINER_USER":"$MINER_USER" "$MONITOR_PATH" || true

cat > /etc/systemd/system/elias-monitor.service <<'MDS'
[Unit]
Description=Elias Miner Monitor (restarts xmrig-elias units if they fail)
After=network.target

[Service]
Type=simple
User=miner
ExecStart=/opt/xmrig/elias_monitor.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
MDS

systemctl daemon-reload
systemctl enable --now elias-monitor.service || true
ok "Installed elias-monitor.service"

# ---------- Uninstall helper ----------
UNINSTALL_PATH="/opt/xmrig/uninstall_elias.sh"
cat > "$UNINSTALL_PATH" <<'UNINST'
#!/usr/bin/env bash
set -euo pipefail
echo "Stopping services..."
systemctl stop elias-monitor || true
systemctl disable elias-monitor || true
for u in $(systemctl list-units --type=service --no-legend 'xmrig-elias@*' | awk '{print $1}'); do
  systemctl stop "$u" || true
  systemctl disable "$u" || true
done
rm -f /etc/systemd/system/xmrig-elias@.service
rm -f /etc/systemd/system/elias-monitor.service
systemctl daemon-reload
echo "Removing /opt/xmrig (will remove XMRig, configs, logs)..."
rm -rf /opt/xmrig
echo "Optionally remove miner user? (y/N)"
read -rp "" CH
if [[ "${CH^^}" == "Y" ]]; then
  userdel -r miner || true
fi
echo "Uninstall complete."
UNINST
chmod +x "$UNINSTALL_PATH"
chown "$MINER_USER":"$MINER_USER" "$UNINSTALL_PATH" || true
ok "Created uninstall script at $UNINSTALL_PATH"

# ---------- Final Dashboard ----------
cat <<EOF

${GREEN}┌────────────────────────────────────────────┐${RESET}
${GREEN}│ 🚀 EliasMiner Auto-Optimizer v3.0 - Ready   │${RESET}
${GREEN}└────────────────────────────────────────────┘${RESET}

Coin: ${CYAN}$COIN${RESET}
Wallet first chars: ${CYAN}${WALLET:0:10}...${RESET}
Pool: ${CYAN}$best_pool${RESET}
Instances: ${CYAN}$INSTANCES${RESET}
Threads per instance: ${CYAN}$THREADS_PER_INSTANCE${RESET}
XMRig path: ${CYAN}$XMRIG_DEST${RESET}
Logs: ${CYAN}$LOG_DIR${RESET}
Uninstall script: ${CYAN}$UNINSTALL_PATH${RESET}

To view miner logs for a given CPU range (example 0-3):
  sudo journalctl -u xmrig-elias@0-3 -f

To view monitor logs:
  sudo journalctl -u elias-monitor -f

To stop mining:
  sudo systemctl stop xmrig-elias@0-3  # or stop all with:
  sudo systemctl stop 'xmrig-elias@*'

To uninstall:
  sudo bash $UNINSTALL_PATH

${GREEN}✅ Setup complete. Miners should be running and enabled on boot.${RESET}

EOF

exit 0
