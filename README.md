
# 🚀 EliasMiner v1.0  
### *The Ultimate Auto-Optimizer for XMRig CPU Mining*

---

## 🧩 Overview

**EliasMiner** is a fully automated installer and optimizer for [XMRig](https://github.com/xmrig/xmrig) CPU mining.  
It’s designed to work out of the box on any fresh **Ubuntu VPS** or Linux server with minimal input.  

All you do is run **one command**, and it will:
- Automatically install all dependencies.  
- Build the latest XMRig from source.  
- Detect your CPU and optimize threads.  
- Detect your country and select the fastest pool (geo + latency test).  
- Enable HugePages and performance governor.  
- Create multiple XMRig instances (`Elias1`, `Elias2`, …) for multi-core optimization.  
- Start everything automatically and keep it running forever.  
- Add a self-monitor to restart miners if they fail.  

---

## ⚙️ Quick Install

Run this command as **root** or with `sudo`:
```bash
bash <(curl -s https://raw.githubusercontent.com/YourUser/EliasMiner/main/install.sh)

That’s it! 💥
The script will guide you step-by-step the first time only:

1. Choose your coin from a numbered list (TRX, BTC, DOGE, etc.).


2. Enter your wallet address (without coin prefix).


3. Sit back — EliasMiner handles everything else.




---

💰 Supported Coins

When the script starts, you’ll see this menu:

───────────────────────────────
 💎 Choose the coin you want to mine:
───────────────────────────────
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
───────────────────────────────
👉 Enter number [default = 1]:

Default coin: TRX (Tron)
You can modify later by editing:

sudo nano /opt/xmrig/.elias_config


---

🧠 Smart Features

✅ Auto geo-detection:
Detects your VPS country (via ipinfo.io) and pings multiple unMineable pools, choosing the one with the lowest latency.

✅ Smart CPU planning:
Automatically splits CPU cores into up to 4 optimized mining instances.

✅ Benchmarking:
Runs a short 10-second test to determine the best thread count per instance.

✅ HugePages + Performance governor:
Improves CPU efficiency for maximum hashrate.

✅ Auto-recovery monitor:
A background service checks every 30 seconds — if any miner stops or slows down, it restarts automatically.

✅ Auto-start on reboot:
All miners are systemd-enabled and start automatically when your VPS reboots.

✅ Safe non-root mining:
Everything runs under a dedicated Linux user miner.


---

🖥️ Dashboard (after install)

At the end of installation you’ll see something like this:

┌────────────────────────────────────────────┐
│ 🚀 EliasMiner Auto-Optimizer v3.0 - Ready   │
└────────────────────────────────────────────┘

Coin: TRX
Wallet: TXsJ5rau2x...
Pool: rx-eu.unmineable.com:443
Instances: 2
Threads per instance: 8
XMRig path: /opt/xmrig
Logs: /opt/xmrig/logs
Uninstall: /opt/xmrig/uninstall_elias.sh

✅ Setup complete. Miners are running and enabled on boot.


---

🧾 Monitoring & Control

View mining logs:

sudo journalctl -u xmrig-elias@0-3 -f

(replace 0-3 with the CPU range shown during setup)

View all miners:

sudo systemctl status 'xmrig-elias@*'

Stop all miners:

sudo systemctl stop 'xmrig-elias@*'

Restart all miners:

sudo systemctl restart 'xmrig-elias@*'

Monitor service logs:

sudo journalctl -u elias-monitor -f


---

🔄 Uninstall

To remove EliasMiner completely:

sudo bash /opt/xmrig/uninstall_elias.sh

You’ll be asked whether to delete the miner user.


---

🧠 Requirements

Component	Recommended

OS	Ubuntu 20.04 / 22.04 LTS
CPU	2+ cores (8+ preferred)
RAM	1 GB minimum
Privileges	Root (for first run only)



---

🛠️ Files & Structure

/opt/xmrig/
├── xmrig                        # built binary
├── config-Elias1.json           # miner instance 1 config
├── config-Elias2.json           # miner instance 2 config
├── logs/                        # log files
├── elias_monitor.sh             # auto monitor service
├── uninstall_elias.sh           # full cleanup
└── .elias_config                # saved coin + wallet

Systemd services:

xmrig-elias@.service             # template service for miners
elias-monitor.service            # monitor auto-restart service


---

🧩 Credits

XMRig — open-source miner used by EliasMiner.

unMineable — pool for multiple crypto payouts.

Bash / systemd scripting by Elias.



---

⚠️ Disclaimer

> Mining is resource intensive. Ensure your hosting provider allows CPU mining. EliasMiner is provided as-is without warranty; use responsibly. Always monitor CPU temps and usage.




---

💎 License

MIT License © 2025 Elias You’re free to use, modify, and share.


---

✨ Example One-Line Setup

bash <(curl -s https://raw.githubusercontent.com/YourUser/EliasMiner/main/install.sh)


---

Enjoy your optimized mining experience ⚙️
– EliasMiner Team 💚
