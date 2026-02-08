# Telegram Bot

Simple Telegram bot running in Docker on the Pi.

## Commands

- `/start` — welcome message
- `/hello` — greets you by name
- `/status` — Pi system info (temp, load, mem, disk, uptime)
- `/claude <prompt>` — ask Claude (returns session ID)
- `/claude_resume <prompt>` — continue last Claude session
- `/cc <prompt>` — alias for `/claude_resume`
- `/cc <session-id> <prompt>` — resume a specific session by ID prefix
- `/chatid` — show current chat ID
- `/throwerr` — throw a test error

## Setup

1. Create a bot via [@BotFather](https://t.me/BotFather) on Telegram
2. Add to `.env`:
   ```
   TELEGRAM_BOT_TOKEN=your-token
   TELEGRAM_ALLOWED_USERS=your_username
   ```
   Multiple users: `TELEGRAM_ALLOWED_USERS=alice,bob`

## Claude Integration

The bot runs Claude Code on the Pi via `nsenter` (requires `pid_mode: host` and `privileged: true`).

**Configuration:**
- Allowed tools: read from `~/.claude/settings.json` on the Pi (`permissions.allow`)
- System prompt: read from `~/.claude/prompt.md` on the Pi (passed via `--append-system-prompt`)
- `CLAUDE_DANGEROUS_MODE=true` — skip all permission prompts (env var)
- `CLAUDE_TIMEOUT` — max seconds to wait (default: 120)

**Session continuity:**
- `/claude` starts a new session, shows session ID (first 8 chars) in footer
- `/cc` continues the most recent session
- `/cc <prefix>` resumes a specific session by ID prefix match
- Sessions are stored in memory (reset on container restart)

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
