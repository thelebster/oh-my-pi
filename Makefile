.PHONY: help run check status ping verbose tags sh shell claude reboot poweroff ansible-shell sys-status sys-restart sys-enable sys-logs

-include .env

PI_HOST ?= pihub.local
PI_USER ?= pi
SSH_KEY ?=

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
	ansible pihub -m ping

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
	@ansible pihub -m shell -a "$(filter-out $@,$(MAKECMDGOALS))"

## claude  : Run Claude on Pi. Usage: make claude "hello"
claude:
	@$(SSH) -t 'bash -lc "~/.local/bin/claude -p \"$(filter-out $@,$(MAKECMDGOALS))\""'

## reboot  : Reboot Pi.
reboot:
	$(SSH) sudo reboot

## poweroff : Shutdown Pi.
poweroff:
	$(SSH) sudo poweroff

# === SERVICE SHORTCUTS ===

## sys-status  : Service status. Usage: make sys-status nginx
sys-status:
	@ansible pihub -m shell -a "systemctl status $(filter-out $@,$(MAKECMDGOALS))"

## sys-restart : Restart service. Usage: make sys-restart nginx
sys-restart:
	@ansible pihub -m shell -a "systemctl restart $(filter-out $@,$(MAKECMDGOALS))"

## sys-enable  : Enable service on boot. Usage: make sys-enable nginx
sys-enable:
	@ansible pihub -m shell -a "systemctl enable $(filter-out $@,$(MAKECMDGOALS))"

## sys-logs    : Follow service logs. Usage: make sys-logs nginx
sys-logs:
	@$(SSH) journalctl -u $(filter-out $@,$(MAKECMDGOALS)) -f

%:
	@:
