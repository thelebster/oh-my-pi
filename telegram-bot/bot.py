import os
import shutil
import shlex
import asyncio
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


CLAUDE_TIMEOUT = int(os.environ.get("CLAUDE_TIMEOUT", "120"))


@authorized
async def claude_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prompt = " ".join(context.args) if context.args else ""
    if not prompt:
        await update.message.reply_text("Usage: /claude <prompt>")
        return

    msg = await update.message.reply_text("Thinking...")

    try:
        proc = await asyncio.create_subprocess_exec(
            "nsenter", "-t", "1", "-m", "-u", "-i", "-n", "--",
            "su", "-", "pi", "-c", f"claude -p {shlex.quote(prompt)}",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=CLAUDE_TIMEOUT
        )
    except asyncio.TimeoutError:
        proc.kill()
        await msg.edit_text(f"Timed out ({CLAUDE_TIMEOUT}s limit).")
        return
    except Exception as e:
        await msg.edit_text(f"Error: {e}")
        return

    if proc.returncode != 0:
        error = stderr.decode().strip() or "Unknown error"
        if len(error) > 4000:
            error = error[:4000] + "\n...(truncated)"
        await msg.edit_text(f"Error (exit {proc.returncode}):\n{error}")
        return

    result = stdout.decode().strip()
    if not result:
        result = "(empty response)"
    if len(result) > 4096:
        result = result[:4093] + "..."

    await msg.edit_text(result)


async def post_init(app):
    await app.bot.set_my_commands([
        ("status", "Pi system info"),
        ("claude", "Ask Claude"),
        ("hello", "Say hello"),
    ])


def main():
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("hello", hello))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("claude", claude_cmd))
    logger.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
