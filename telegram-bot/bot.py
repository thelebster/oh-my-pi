import os
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


@authorized
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text("Hi! I'm your Pi bot. Try /hello")


@authorized
async def hello(update: Update, context: ContextTypes.DEFAULT_TYPE):
    name = update.effective_user.first_name
    await update.message.reply_text(f"Hello {name}!")


def main():
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    app = Application.builder().token(token).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("hello", hello))
    logger.info("Bot starting...")
    app.run_polling()


if __name__ == "__main__":
    main()
