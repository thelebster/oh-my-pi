import os
import re
import json
import shutil
import shlex
import asyncio
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes, filters

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
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
CLAUDE_DANGEROUS_MODE = os.environ.get("CLAUDE_DANGEROUS_MODE", "").lower() == "true"

_sessions: dict[int, list[str]] = {}  # chat_id -> [session_ids]


@authorized
async def throwerr(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = " ".join(context.args) if context.args else "Test error"
    raise RuntimeError(msg)


@authorized
async def chatid(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(f"Chat ID: `{update.effective_chat.id}`", parse_mode="Markdown")


PI_USER = os.environ.get("PI_USER", "pi")
CLAUDE_SETTINGS_PATH = f"{HOSTFS}/home/{PI_USER}/.claude/settings.json"

def _load_settings() -> dict:
    try:
        with open(CLAUDE_SETTINGS_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        logger.warning("Could not load %s", CLAUDE_SETTINGS_PATH)
        return {}

_claude_settings = _load_settings()
CLAUDE_ALLOWED_TOOLS = _claude_settings.get("permissions", {}).get("allow", [])

CLAUDE_PROMPT_PATH = f"{HOSTFS}/home/{PI_USER}/.claude/prompt.md"

def _load_system_prompt() -> str:
    try:
        with open(CLAUDE_PROMPT_PATH) as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""

CLAUDE_SYSTEM_PROMPT = _load_system_prompt()


def _build_claude_args(prompt: str, session_id: str | None = None) -> str:
    parts = [
        "~/.local/bin/claude -p", shlex.quote(prompt),
        "--output-format json",
        *(["--append-system-prompt", shlex.quote(CLAUDE_SYSTEM_PROMPT)] if CLAUDE_SYSTEM_PROMPT else []),
        *(["--dangerously-skip-permissions"] if CLAUDE_DANGEROUS_MODE else []),
        *[f"--allowedTools {shlex.quote(t)}" for t in CLAUDE_ALLOWED_TOOLS],
        *(["--resume", shlex.quote(session_id)] if session_id else []),
    ]
    return " ".join(parts)


def _parse_claude_json(raw: str) -> tuple[str, str | None]:
    """Parse Claude JSON output. Returns (result_text, session_id)."""
    data = json.loads(raw)
    session_id = data.get("session_id")
    result = data.get("result", "")
    if not result:
        result = "(empty response)"
    return result, session_id


async def _run_claude(prompt: str, chat_id: int, msg, session_id: str | None = None):
    cmd = _build_claude_args(prompt, session_id)
    try:
        # Bot runs in Docker — nsenter breaks into host namespaces (PID 1),
        # then su runs the command as the pi user where Claude is installed.
        # Requires pid_mode: host and privileged: true in the container config.
        proc = await asyncio.create_subprocess_exec(
            "nsenter", "-t", "1", "-m", "-u", "-i", "-n", "--",
            "su", "-", PI_USER, "-c", cmd,
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

    raw = stdout.decode().strip()
    if not raw:
        await msg.edit_text("(empty response)")
        return

    try:
        result, new_session_id = _parse_claude_json(raw)
    except (json.JSONDecodeError, KeyError):
        result = raw
        new_session_id = None

    if new_session_id:
        _sessions.setdefault(chat_id, []).append(new_session_id)
        footer = f"\n\nsession: {new_session_id[:8]}"
    else:
        footer = ""

    text = result + footer
    if len(text) > 4096:
        text = text[:4093] + "..."

    await msg.edit_text(text)


@authorized
async def claude_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prompt = " ".join(context.args) if context.args else ""
    if not prompt:
        await update.message.reply_text("Usage: /claude <prompt>")
        return

    msg = await update.message.reply_text("Thinking...")
    await _run_claude(prompt, update.effective_chat.id, msg)


SESSION_PREFIX_RE = re.compile(r"^[0-9a-f]+$", re.IGNORECASE)


def lookup_session(chat_id: int, prefix: str) -> str | None:
    """Find a session by prefix match."""
    for sid in reversed(_sessions.get(chat_id, [])):
        if sid.startswith(prefix):
            return sid
    return None


@authorized
async def claude_resume_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    args = list(context.args) if context.args else []
    if not args:
        await update.message.reply_text("Usage: /cc <prompt> or /cc <session-id> <prompt>")
        return

    chat_id = update.effective_chat.id
    sessions = _sessions.get(chat_id, [])

    if SESSION_PREFIX_RE.match(args[0]) and len(args) > 1:
        session_id = lookup_session(chat_id, args.pop(0))
        prompt = " ".join(args)
        if not session_id:
            await update.message.reply_text("Session not found.")
            return
    else:
        session_id = sessions[-1] if sessions else None
        prompt = " ".join(args)

    if not session_id:
        await update.message.reply_text(
            "No active session.\n"
            "Start one first: /claude <prompt>\n"
            "Then continue with: /cc <prompt>"
        )
        return

    msg = await update.message.reply_text("Continuing...")
    await _run_claude(prompt, chat_id, msg, session_id=session_id)


async def post_init(app):
    await app.bot.set_my_commands([
        ("status", "Pi system info"),
        ("claude", "Ask Claude"),
        ("claude_resume", "Continue Claude conversation"),
        ("cc", "Continue Claude conversation (alias)"),
        ("chatid", "Show chat ID"),
        ("hello", "Say hello"),
        ("throwerr", "Throw a test error"),
    ])


async def error_handler(update, context):
    logger.error("Exception: %s", context.error)
    if update and update.effective_message:
        await update.effective_message.reply_text("Something went wrong.")


def main():
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    app = Application.builder().token(token).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("hello", hello))
    app.add_handler(CommandHandler("status", status))
    app.add_handler(CommandHandler("claude", claude_cmd))
    app.add_handler(CommandHandler("claude_resume", claude_resume_cmd))
    app.add_handler(CommandHandler("cc", claude_resume_cmd))
    app.add_handler(CommandHandler("chatid", chatid))
    app.add_handler(CommandHandler("throwerr", throwerr))
    app.add_error_handler(error_handler)
    logger.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
