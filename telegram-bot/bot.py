import os
import shutil
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, filters

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ALLOWED_USERS = os.environ["TELEGRAM_ALLOWED_USERS"].split(",")


def authorized(func):
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        username = update.effective_user.username
        if username not in ALLOWED_USERS:
            logger.warning("Unauthorized: @%s", username)
            return
        return await func(update, context)
    return wrapper


HOSTFS = os.environ.get("HOSTFS_PATH", "/hostfs")


@authorized
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Hi! I'm your Pi bot. Try /status")


@authorized
async def hello(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(f"Hello {name}!")


@authorized
async def status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    lines = []

    # CPU Temperature
    try:
        with open(f"{HOSTFS}/sys/class/thermal/thermal_zone0/temp") as f:
            temp_c = int(f.read().strip()) / 1000
        lines.append(f"Temp: {temp_c:.1f}C")
    except Exception:
        lines.append("Temp: unavailable")

    # CPU Load (1m, 5m, 15m)
    try:
        with open(f"{HOSTFS}/proc/loadavg") as f:
            parts = f.read().strip().split()
        lines.append(f"Load: {parts[0]}, {parts[1]}, {parts[2]}")
    except Exception:
        lines.append("Load: unavailable")

    # Memory
    try:
        meminfo = {}
        with open(f"{HOSTFS}/proc/meminfo") as f:
            for line in f:
                key, val = line.split(":")
                meminfo[key.strip()] = int(val.strip().split()[0])
        total = meminfo["MemTotal"]
        available = meminfo["MemAvailable"]
        used = total - available
        pct = used / total * 100
        lines.append(f"Mem: {used // 1024} / {total // 1024} MB ({pct:.0f}%)")
    except Exception:
        lines.append("Mem: unavailable")

    # Disk
    try:
        usage = shutil.disk_usage(HOSTFS)
        total_gb = usage.total / (1024**3)
        used_gb = usage.used / (1024**3)
        pct = usage.used / usage.total * 100
        lines.append(f"Disk: {used_gb:.1f} / {total_gb:.1f} GB ({pct:.0f}%)")
    except Exception:
        lines.append("Disk: unavailable")

    # Uptime
    try:
        with open(f"{HOSTFS}/proc/uptime") as f:
            seconds = int(float(f.read().strip().split()[0]))
        days, rem = divmod(seconds, 86400)
        hours, rem = divmod(rem, 3600)
        mins, _ = divmod(rem, 60)
        parts = []
        if days:
            parts.append(f"{days}d")
        if hours:
            parts.append(f"{hours}h")
        parts.append(f"{mins}m")
        lines.append(f"Uptime: {' '.join(parts)}")
    except Exception:
        lines.append("Uptime: unavailable")

    await update.message.reply_text("\n".join(lines))


def main():
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("hello", hello))
    app.add_handler(CommandHandler("status", status))
    logger.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
