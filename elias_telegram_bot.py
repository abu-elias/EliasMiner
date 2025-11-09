#!/usr/bin/env python3
# ==========================================================
# 💬 EliasMiner Telegram Bot v1.5
# Author: Elias | Smart Mining Control Bot
# GitHub: https://github.com/abu-elias/EliasMiner
# ==========================================================

import os, subprocess, time, threading, requests
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update, ParseMode
from telegram.ext import Updater, CommandHandler, CallbackQueryHandler, CallbackContext

# ---------- Load Config ----------
CONFIG_PATH = "/opt/xmrig/bot.conf"
MINER_CONFIG = "/opt/xmrig/.elias_config"

def load_env(path):
    if not os.path.exists(path):
        return {}
    env = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                env[k] = v
    return env

env = load_env(CONFIG_PATH)
bot_token = env.get("TELEGRAM_BOT_TOKEN")
admin_id = env.get("ADMIN_CHAT_ID")

miner_env = load_env(MINER_CONFIG)
COIN = miner_env.get("COIN", "N/A")
WORKER = miner_env.get("WORKER", "N/A")

# ---------- Helpers ----------
def run_cmd(cmd):
    try:
        output = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT, text=True)
        return output.strip()
    except subprocess.CalledProcessError as e:
        return e.output.strip()

def get_status():
    status = run_cmd("systemctl is-active xmrig-elias@1.service")
    hashrate = run_cmd("grep -m1 'speed' /var/log/syslog | tail -n1") or "No hashrate yet"
    return f"🪙 *Coin:* {COIN}\n🧠 *Worker:* {WORKER}\n⚙️ *Status:* `{status}`\n📈 *Hashrate:* `{hashrate}`"

def get_logs(n=15):
    logs = run_cmd(f"journalctl -u xmrig-elias@1 -n {n} --no-pager | tail -n {n}")
    return f"🧾 *Last {n} log lines:*\n```\n{logs}\n```"

# ---------- Bot Commands ----------
def start(update: Update, context: CallbackContext):
    if str(update.effective_user.id) != admin_id:
        update.message.reply_text("🚫 Access denied.")
        return

    keyboard = [
        [InlineKeyboardButton("⚙️ Status", callback_data="status"),
         InlineKeyboardButton("📈 Hashrate", callback_data="hash")],
        [InlineKeyboardButton("▶️ Start", callback_data="start"),
         InlineKeyboardButton("⏸ Stop", callback_data="stop"),
         InlineKeyboardButton("🔁 Restart", callback_data="restart")],
        [InlineKeyboardButton("🧾 Logs", callback_data="logs")]
    ]
    update.message.reply_text(
        f"💎 *EliasMiner Control Panel*\n🪙 Coin: *{COIN}*\n🖥 Worker: *{WORKER}*",
        parse_mode=ParseMode.MARKDOWN,
        reply_markup=InlineKeyboardMarkup(keyboard)
    )

def button(update: Update, context: CallbackContext):
    query = update.callback_query
    data = query.data
    query.answer()

    if data == "status":
        query.edit_message_text(get_status(), parse_mode=ParseMode.MARKDOWN)
    elif data == "hash":
        query.edit_message_text(get_status(), parse_mode=ParseMode.MARKDOWN)
    elif data == "start":
        run_cmd("systemctl start xmrig-elias@1.service")
        query.edit_message_text("✅ Mining started.")
    elif data == "stop":
        run_cmd("systemctl stop xmrig-elias@1.service")
        query.edit_message_text("🛑 Mining stopped.")
    elif data == "restart":
        run_cmd("systemctl restart xmrig-elias@1.service")
        query.edit_message_text("🔁 Miner restarting...")
    elif data == "logs":
        query.edit_message_text(get_logs(15), parse_mode=ParseMode.MARKDOWN)

# ---------- Auto Monitor ----------
def monitor_loop():
    while True:
        time.sleep(180)
        status = run_cmd("systemctl is-active xmrig-elias@1.service")
        if status != "active":
            run_cmd("systemctl restart xmrig-elias@1.service")
            msg = f"⚠️ Miner was down on {WORKER}. Restarted automatically."
            requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={admin_id}&text={msg}")
        else:
            hashrate = run_cmd("grep -m1 'speed' /var/log/syslog | tail -n1")
            msg = f"✅ Miner running normally.\n📈 {hashrate}"
            requests.get(f"https://api.telegram.org/bot{bot_token}/sendMessage?chat_id={admin_id}&text={msg}")

# ---------- Main ----------
def main():
    updater = Updater(bot_token, use_context=True)
    dp = updater.dispatcher
    dp.add_handler(CommandHandler("start", start))
    dp.add_handler(CallbackQueryHandler(button))
    threading.Thread(target=monitor_loop, daemon=True).start()
    updater.start_polling()
    updater.idle()

if __name__ == "__main__":
    main()
