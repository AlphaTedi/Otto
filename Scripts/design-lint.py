#!/usr/bin/env python3
"""Otto design-system lint — flags styling that bypasses DesignSystem/.

Checks only ADDED lines (git diff against HEAD, plus untracked files), so the
existing code never blocks anything; it stops new drift at the door.

  Scripts/design-lint.sh                 every changed Swift file
  Scripts/design-lint.sh Otto/Foo.swift  just these files

A line that genuinely needs a literal carries `// ds-allow: <why>`.
Rules and the replacements are in docs/DESIGN_SYSTEM.md.
"""
import os, re, subprocess, sys

# Compare against HEAD (an agent's uncommitted edit) or, for a whole branch,
# DS_LINT_BASE=main Scripts/design-lint.sh
BASE = os.environ.get("DS_LINT_BASE", "HEAD")
ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
os.chdir(ROOT)

# Out of scope: native Settings, Onboarding's own theme, the debug driver, and
# the design system itself (that is where literals are SUPPOSED to live).
EXEMPT = ("Otto/Settings/", "Otto/Onboarding/", "Otto/Debug/", "Otto/DesignSystem/")
SPACE_SCALE = {"0", "2", "4", "6", "8", "10", "12", "16", "24"}

RULES = [
    (r"\.font\(\s*\.system\(\s*size:", None, "inline font size → DSType role (DSType.body, .label, .rowTitle(surface)…)"),
    (r"cornerRadius:\s*[0-9]", None, "literal corner radius → DSShape.squircle(DSRadius.…)"),
    (r"Color\(hex:", None, "hex colour in a view → a palette role or a DSColor token"),
    (r"(Color\.)?\.?(white|black)\.opacity\(", None, "white/black opacity → a DSPalette role (palette.rowHover, .textSecondary…)"),
    (r"\.(spring|easeOut|easeIn|easeInOut|linear|timingCurve)\(", "Otto/Notch/NotchAnimation.swift",
     "inline animation curve → Motion.* (press, hoverFade, appear, swap, contentHug…)"),
    (r"\bNotchAnimation\.", "Otto/Notch/", "NotchAnimation.* skips Reduce Motion → Motion.*"),
    (r"Image\(systemName:", None, "SF Symbol image → OttoIcon(\"name\", pointSize:)"),
    (r"\bDSDock\.", "Otto/Todos/Dock/", "DSDock outside the dock → @Environment(\\.dsPalette) role"),
    (r"\.help\(", None, ".help() opens behind the notch → .ottoTooltip(label, shortcut:)"),
    (r"\bMenu\s*\{|\bMenu\(", None, "SwiftUI Menu cannot present from the notch → DSMenuRow + .ottoMenuSurface()"),
]
PAD = re.compile(r"\.padding\(\s*(?:\.[a-zA-Z]+\s*,\s*)?([0-9]+(?:\.[0-9]+)?)\s*\)|spacing:\s*([0-9]+(?:\.[0-9]+)?)\b")


def changed_files():
    out = subprocess.run(["git", "diff", "--name-only", BASE, "--", "*.swift"], capture_output=True, text=True).stdout
    new = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", "*.swift"],
                         capture_output=True, text=True).stdout
    return [f for f in (out + new).split() if f]


def added_lines(path):
    tracked = subprocess.run(["git", "ls-files", "--error-unmatch", path], capture_output=True).returncode == 0
    if not tracked:
        try:
            with open(path) as fh:
                return list(enumerate(fh.read().splitlines(), 1))
        except OSError:
            return []
    diff = subprocess.run(["git", "diff", "-U0", BASE, "--", path], capture_output=True, text=True).stdout
    lines, n = [], 0
    for raw in diff.splitlines():
        m = re.match(r"@@ -\S+ \+(\d+)", raw)
        if m:
            n = int(m.group(1)); continue
        if raw.startswith("+") and not raw.startswith("+++"):
            lines.append((n, raw[1:])); n += 1
    return lines


def lint(path):
    path = os.path.relpath(os.path.abspath(path), ROOT)
    if not path.endswith(".swift") or not path.startswith("Otto/") or path.startswith(EXEMPT):
        return []
    found = []
    for n, line in added_lines(path):
        code = line.split("//", 1)[0] if "ds-allow" not in line else ""
        if not code.strip():
            continue
        for pattern, exempt_prefix, message in RULES:
            if exempt_prefix and path.startswith(exempt_prefix):
                continue
            if re.search(pattern, code):
                found.append(f"{path}:{n}: {message}")
        for m in PAD.finditer(code):
            value = (m.group(1) or m.group(2)).rstrip("0").rstrip(".") if "." in (m.group(1) or m.group(2)) else (m.group(1) or m.group(2))
            if value not in SPACE_SCALE:
                found.append(f"{path}:{n}: spacing {value} is off the scale → DSSpace (2·4·6·8·10·12·16·24)")
    return found


def main():
    files = sys.argv[1:] or changed_files()
    problems = [p for f in files for p in lint(f)]
    if problems:
        print("Design-system lint (docs/DESIGN_SYSTEM.md) — fix, or add `// ds-allow: <why>`:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
