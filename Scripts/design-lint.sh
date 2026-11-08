#!/bin/bash
# Otto design-system lint. See Scripts/design-lint.py and docs/DESIGN_SYSTEM.md.
exec python3 -I "$(dirname "$0")/design-lint.py" "$@"
