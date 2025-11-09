#!/bin/bash
# ==========================================================
# 💬 EliasMiner Telegram Bot Auto Installer
# Author: Elias | Version: v1.5
# ==========================================================

CYAN=$(tput setaf 6)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
RESET=$(tput sgr0)
BOLD=$(tput bold)

clear
echo -e "${CYAN}"
echo "───────────────────────────────────────────────"
echo "       💬  E L I A S  M I N E R  B O T"
echo "───────────────────────────────────────────────"
echo -e "${RESET}${BOLD}Telegram Control + Live Monitor${RESET}\n"

# ---------- Step 1: Dependencies ----------
echo -e "${CYAN}📦 Installing dependencies...${RESET}"
apt update -y >/dev/null 2>&1
apt install -y python3 python3-pip curl >/dev/null 2>&1
pip3 install requests python-telegram-bot==13.15 >/dev/null 2>&1
echo -e "${GREEN}✅ Dependencies installed.${RESET}\n"

# ---------- Step 2: Configuration ----------
read -rp "🤖 Enter Telegram Bot Token: " TOKEN
read -rp "👤 Enter Your Telegram Chat ID: " CHATID

if [ -z "$TOKEN" ] || [ -z "$CHATID" ]; then
    echo -e "${RED}❌ Missing token or chat ID. Aborting.${RESET}"
    exit 1
fi

mkdir -p /opt/xmrig
tee /opt/xmrig/bot.conf > /dev/null <<EOF
TELEGRAM_BOT_TOKEN=$TOKEN
ADMIN_CHAT_ID=$CHATID
EOF

echo -e "${GREEN}✅ Bot configuration saved.${RESET}\n"

# ---------- Step 3: Download bot file ----------
echo -e "${CYAN}⬇️ Downloading EliasMiner Telegram Bot script...${RESET}"
curl -s -o /opt/xmrig/elias_telegram_bot.py https://raw.githubusercontent.com/abu-elias/EliasMiner/main/elias_telegram_bot.py
chmod +x /opt/xmrig/elias_telegram_bot.py
echo -e "${GREEN}✅ Bot script downloaded successfully.${RESET}\n"

# ---------- Step 4: Create systemd service ----------
echo -e "${CYAN}⚙️ Creating systemd service...${RESET}"
tee /etc/systemd/system/elias-telegram-bot.service > /dev/null <<EOF
[Unit]
Description=EliasMiner Telegram Bot
After=network.target

[Service]
User=root
WorkingDirectory=/opt/xmrig
ExecStart=/usr/bin/python3 /opt/xmrig/elias_telegram_bot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now elias-telegram-bot.service >/dev/null 2>&1

echo -e "${GREEN}✅ Telegram Bot Service created and started.${RESET}\n"
echo -e "${CYAN}───────────────────────────────────────────────${RESET}"
echo -e "${GREEN}🎯 Bot Installed Successfully!"
echo -e "Service: elias-telegram-bot.service"
echo -e "Logs: journalctl -u elias-telegram-bot -f${RESET}"
echo -e "${CYAN}───────────────────────────────────────────────${RESET}"
