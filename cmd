#!/usr/bin/env bash
# Wrapper for ansible ad-hoc commands against the Pi.
# Sources .env so secrets and config are available.
#
# Usage:
#   ./cmd -m ping                        # all hosts
#   ./cmd -m ping --limit mypi           # single host
#   ./cmd -m shell -a 'uptime'
#   ./cmd -m shell -a 'ls -la /home/pi' -e ansible_become=false
#   ./cmd -m apt -a 'name=htop state=present'

set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

ansible all "$@"
