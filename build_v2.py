"""Build website v2 (site2/) from the v1 build (site/) plus the v2 hero.

Run build.py first; this copies site/ to site2/, swaps the hero for the
centred header + MacBook, and adds v2.css / v2.js.
"""
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).parent
SRC, DST = ROOT / "site", ROOT / "site2"

if DST.exists():
    shutil.rmtree(DST)
shutil.copytree(SRC, DST, ignore=shutil.ignore_patterns("PLAN.md"))

html = (DST / "index.html").read_text()
d = re.search(r'<svg class="apple-logo"[^>]*><path d="([^"]+)"', html).group(1)
logo = lambda w, h: f'<svg class="apple-logo" width="{w}" height="{h}" viewBox="0 0 814 1000" fill="currentColor" aria-hidden="true"><path d="{d}"/></svg>'

hero = (ROOT / "v2" / "hero.html").read_text()
hero = hero.replace("{{APPLE}}", logo(15, 18)).replace("{{APPLE_MENU}}", logo(13, 16))

a = html.index('<!-- ================= HERO')
b = html.index('</section>', a) + len('</section>')
html = html[:a] + hero.strip() + html[b:]

html = html.replace('<link rel="stylesheet" href="css/otto-ui.css?v=9">',
                    '<link rel="stylesheet" href="css/otto-ui.css?v=9">\n<link rel="stylesheet" href="css/v2.css?v=1">')
html = html.replace('<script src="js/site.js?v=9"></script>',
                    '<script src="js/site.js?v=9"></script>\n<script src="js/v2.js?v=1"></script>')
html = html.replace('<title>', '<title>[v2] ', 1)
(DST / "index.html").write_text(html)

shutil.copy(ROOT / "v2" / "v2.css", DST / "css" / "v2.css")
shutil.copy(ROOT / "v2" / "v2.js", DST / "js" / "v2.js")
assert 'v2.css' in html and 'v2.js' in html and 'mac-screen' in html
print("ok site2")
