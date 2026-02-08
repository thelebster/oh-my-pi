#!/bin/bash
# Wrapper for running Claude CLI with settings from ~/.claude/settings.json
# Usage: claude-run.sh <prompt> [--resume <session-id>]

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
PROMPT_FILE="$HOME/.claude/prompt.md"

# Build --allowedTools flags from settings
tools=()
if [[ -f "$SETTINGS" ]]; then
    while IFS= read -r t; do
        tools+=(--allowedTools "$t")
    done < <(jq -r '.permissions.allow[]' "$SETTINGS" 2>/dev/null)
fi

# Build --append-system-prompt from prompt file
prompt_args=()
if [[ -f "$PROMPT_FILE" ]]; then
    prompt_args=(--append-system-prompt "$(cat "$PROMPT_FILE")")
fi

~/.local/bin/claude -p "$@" --output-format json "${tools[@]}" "${prompt_args[@]}"
