# Telegram Bot

Simple Telegram bot running in Docker on the Pi.

## Commands

- `/start` — welcome message
- `/hello` — greets you by name

## Setup

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Add to `.env`:
   ```
   TELEGRAM_BOT_TOKEN=your-token
   TELEGRAM_ALLOWED_USERS=your_username
   ```
   Multiple users: `TELEGRAM_ALLOWED_USERS=alice,bob`

## Run locally

```bash
docker build -t telegram-bot .
docker run --rm -e TELEGRAM_BOT_TOKEN=your-token -e TELEGRAM_ALLOWED_USERS=your_username telegram-bot
```

## Deploy to Pi

```bash
./play extra telegram-bot
```

## Logs

```bash
./cmd -m shell -a "docker logs telegram-bot"
```
