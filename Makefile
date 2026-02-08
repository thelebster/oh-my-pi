.PHONY: \
	help run check status ping verbose tags \
	sh shell ansible-shell claude claude-resume \
	ddns bot bot-build bot-run bot-logs bot-get-chat-id \
	reboot poweroff \
	sys-status sys-restart sys-enable sys-logs

-include .env

export PI_HOST ?= mypi.local
export PI_USER ?= pi
export SSH_KEY ?=

export CF_API_TOKEN ?=
export CF_ZONE_ID ?=
export CF_DOMAIN ?=
export CF_TUNNEL_TOKEN ?=
export CF_TUNNEL_SSH_HOST ?=
export CF_TUNNEL_HTTP_HOST ?=

export TELEGRAM_BOT_TOKEN ?=
export TELEGRAM_ALLOWED_USERS ?=

export CLAUDE_DANGEROUS_MODE ?=

SSH_KEY_OPT := $(if $(SSH_KEY),-i $(SSH_KEY))
SSH = ssh$(if $(SSH_KEY_OPT), $(SSH_KEY_OPT)) $(PI_USER)@$(PI_HOST)

## help    : Print commands help.
help: Makefile
	@sed -n 's/^## *//p' $< | tr -s '\t' ' ' | column -t -s ':'

## run     : Run the playbook.
run:
	ansible-playbook ansible/playbook.yml

## check   : Dry run (check mode).
check:
	ansible-playbook ansible/playbook.yml --check

## status  : Show versions and service status.
status:
	ansible-playbook ansible/playbook.yml --tags "status"

## ping    : Test connection to Pi.
ping:
	ansible mypi -m ping

## verbose : Run playbook with verbose output.
verbose:
	ansible-playbook ansible/playbook.yml -v

## tags    : List all available tags.
tags:
	ansible-playbook ansible/playbook.yml --list-tags

## sh      : SSH into Pi.
sh:
	$(SSH)

## shell   : SSH into Pi (alias for sh).
shell: sh

## ansible-shell : Run command via ansible. Usage: make ansible-shell "ls -la"
ansible-shell:
	@ansible mypi -m shell -a "$(filter-out $@,$(MAKECMDGOALS))"

CLAUDE_DANGER_FLAG := $(if $(filter true,$(CLAUDE_DANGEROUS_MODE)),--dangerously-skip-permissions)

## claude  : Run Claude on Pi. Usage: make claude "hello"
claude:
	@$(SSH) -t 'bash -lc "~/.local/bin/claude-cmd \"$(filter-out $@,$(MAKECMDGOALS))\" $(CLAUDE_DANGER_FLAG) | jq -r \".session_id as \\\$$sid | .result + \\\"\\\\nsession: \\\" + \\\$$sid\""'

## claude-resume : Resume Claude session. Usage: make claude-resume SESSION=<id> "prompt"
claude-resume:
	@$(SSH) -t 'bash -lc "~/.local/bin/claude-cmd \"$(filter-out $@,$(MAKECMDGOALS))\" $(CLAUDE_DANGER_FLAG) --resume $(SESSION) | jq -r \".session_id as \\\$$sid | .result + \\\"\\\\nsession: \\\" + \\\$$sid\""'

## ddns    : Run Cloudflare DDNS update locally.
ddns:
	bash ansible/scripts/cloudflare-ddns.sh

## bot     : Deploy Telegram bot to Pi.
bot:
	./play extra telegram-bot

## bot-build : Build Telegram bot Docker image locally.
bot-build:
	docker build -t telegram-bot telegram-bot/

## bot-run : Run Telegram bot locally in Docker.
bot-run:
	docker run --rm -e TELEGRAM_BOT_TOKEN -e TELEGRAM_ALLOWED_USERS telegram-bot

## bot-logs : Follow Telegram bot logs on Pi.
bot-logs:
	$(SSH) docker logs -f telegram-bot

## bot-get-chat-id : Get chat ID (send a message to bot first).
bot-get-chat-id:
	@echo "Fetching recent messages... (send a message to your bot first)"
	@curl -s "https://api.telegram.org/bot$(TELEGRAM_BOT_TOKEN)/getUpdates" | \
		grep -o '"chat":{"id":[0-9-]*' | \
		sed 's/"chat":{"id":/Chat ID: /' | \
		sort -u

## reboot  : Reboot Pi.
reboot:
	$(SSH) sudo reboot

## poweroff : Shutdown Pi.
poweroff:
	$(SSH) sudo poweroff

# === SERVICE SHORTCUTS ===

## sys-status  : Service status. Usage: make sys-status nginx
sys-status:
	@ansible mypi -m shell -a "systemctl status $(filter-out $@,$(MAKECMDGOALS))"

## sys-restart : Restart service. Usage: make sys-restart nginx
sys-restart:
	@ansible mypi -m shell -a "systemctl restart $(filter-out $@,$(MAKECMDGOALS))"

## sys-enable  : Enable service on boot. Usage: make sys-enable nginx
sys-enable:
	@ansible mypi -m shell -a "systemctl enable $(filter-out $@,$(MAKECMDGOALS))"

## sys-logs    : Follow service logs. Usage: make sys-logs nginx
sys-logs:
	@$(SSH) journalctl -u $(filter-out $@,$(MAKECMDGOALS)) -f

%:
	@:
