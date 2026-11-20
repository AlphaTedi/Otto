#!/bin/bash
# Claude Code PostToolUse hook: lint the Swift file an agent just edited and
# hand the findings back to it (exit 2 = stderr goes to the agent).
file=$(python3 -I -c 'import json,sys; d=json.load(sys.stdin); print((d.get("tool_input") or {}).get("file_path",""))')
case "$file" in *.swift) ;; *) exit 0 ;; esac
"$(dirname "$0")/design-lint.sh" "$file" || exit 2
