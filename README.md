# Otto website (ottotofive.com)

Static site, no build dependencies.

- `site/` — the live site. Cloudflare Pages publishes this folder.
- `index.src.html` + `build.py` — source of `site/index.html` (run `python3 build.py`, then `python3 build_v2.py`).
- `site2/`, `v2/` — v2 variant (MacBook hero).
- `v3/` — three new directions (a, b, c). Build with `python3 v3/build.py`.
- `avatar/` — exploration: Otto's eyes in the notch.

Preview locally: `python3 -m http.server 8000 --directory site`.
