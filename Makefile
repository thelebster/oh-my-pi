.PHONY: help run check status ping verbose tags shell

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

## shell   : Run shell command on Pi. Usage: make shell "ls -la"
shell:
	@ansible pihub -m shell -a "$(filter-out $@,$(MAKECMDGOALS))"

%:
	@:
