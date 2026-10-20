"""Builds the three v3 directions (a, b, c) from shared parts. Run: python3 build.py"""
import json, pathlib

ROOT = pathlib.Path(__file__).parent
P = json.load(open(ROOT / 'shared/parts.json'))
APPLE, LOGO, FAQ, LOG, T = P['APPLE'], P['LOGO'], P['FAQ'], P['LOG'], P['T']
V = '1'

def head(title, extra_css=''):
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="Otto is a free Mac app that lives in the notch: to-dos, notes and meetings, one hover away.">
<link rel="icon" href="../shared/otto-icon-512.png">
<link rel="stylesheet" href="../shared/otto-ui.css?v={V}">
<link rel="stylesheet" href="../shared/base.css?v={V}">
<style>{extra_css}</style>
</head>
<body>'''

def nav(links=True):
    l = '<div class="links"><a href="#features">Features</a><a href="#new">What’s new</a><a href="#faq">FAQ</a></div>' if links else '<div></div>'
    return f'''<header class="nav"><a class="brand" href="#top" aria-label="Otto, back to top">{LOGO}</a>{l}<a class="btn small" href="../downloads/Otto.dmg">{APPLE}Download</a></header>'''

def cta(big=False):
    return f'''<a class="btn{'' if big else ''}" href="../downloads/Otto.dmg">{APPLE}Download for Mac</a>
<div class="assure"><span>Free, no account</span><span>Nothing leaves your Mac</span><span>macOS 13 or later</span></div>'''

def menubar():
    return f'''<div class="menubar"><div>{APPLE.replace('class="apple"', 'class="apple"')}<b>Otto</b></div><div class="r"><span>Thu Oct 8</span><span>08:08</span></div></div>'''

def new_faq(cls=''):
    return f'''<section class="block {cls}" id="new"><div class="narrow">
  <h2 class="h2 rv">What’s new</h2><p class="lede rv">Otto ships often, and updates itself.</p>
  <div class="log rv">{LOG}</div></div></section>
<section class="block {cls}" id="faq"><div class="narrow">
  <h2 class="h2 rv">Questions, answered.</h2>
  <div class="faq rv">{FAQ}</div></div></section>'''

def footer(mega=True):
    m = '<div class="wrap"><div class="mega" data-logo="currentColor" aria-hidden="true"></div></div>' if mega else ''
    return f'''<footer class="foot"><div class="wrap">
  <div class="foot-row"><span>A free Mac app for to-dos, notes and meetings. Made by Marcello Zanetta.</span>
  <nav><a href="#features">Features</a><a href="#faq">FAQ</a><a href="../privacy.html">Privacy</a><a href="mailto:marcello.zanetta1@gmail.com">Contact</a><a href="https://buymeacoffee.com/YOUR_HANDLE">Buy me a coffee</a></nav></div>
  <div class="foot-legal">© 2026 Otto. Mac and macOS are trademarks of Apple Inc. Google Meet is a trademark of Google LLC.</div>
</div>{m}</footer>'''

def scripts(extra=''):
    return f'''<script>window.OTTO_T_PATH = "{T}";</script>
<script src="../shared/otto-ui.js?v={V}"></script>
<script src="../shared/common.js?v={V}"></script>
<script>{extra}</script>
</body></html>'''

FEATURES = [
    ('capture', 'Catch it before it’s gone.', 'Press ⌃⇧N from any app, type, press return. Steps, links, images and dates live right in the line.'),
    ('notes', 'Notes, next to the list.', 'Jot things down without opening another app. Headings, lists, links and code, saved as you type.'),
    ('meeting', 'Know before the meeting.', 'A quiet countdown sits in the notch. Five minutes before, Otto opens with Join and Snooze.'),
    ('layout', 'In the notch, or floating.', 'No notch, or you’d rather not use it? The same Otto, as a floating panel.'),
    ('keys', 'One shortcut, from anywhere.', 'The notch opens with your cursor already in a new to-do. Everything else works from the keyboard too.'),
    ('files', 'Plain files, on your Mac.', 'Everything is also saved as Markdown in a folder you choose. No account, no server, nothing to sync.'),
]

# ======================================================================== A
A_CSS = '''
.hero { padding: 150px 0 0; text-align: center; }
.hero h1 { font-size: clamp(3rem, 7.2vw, 6.2rem); line-height: .98; letter-spacing: -.05em; }
.hero .sub { margin: 22px auto 34px; font-size: 20px; color: var(--muted); }
.stagebox { margin: 72px auto 0; border-radius: 32px; overflow: hidden; height: min(620px, 72vh); position: relative; box-shadow: 0 0 0 1px rgba(0,0,0,.04); }
.stagebox .hero-otto { position: absolute; top: 0; left: 0; right: 0; }
.hint { position: absolute; bottom: 22px; left: 50%; transform: translateX(-50%); font-size: 14px; color: var(--muted); white-space: nowrap; }
.block { padding: 150px 0 0; }
.feat { text-align: center; }
.feat h2 { font-size: clamp(2.2rem, 4.6vw, 3.6rem); line-height: 1.04; }
.feat p { margin: 18px auto 48px; max-width: 30em; color: var(--muted); font-size: 19px; }
.feat .frame { width: min(860px, 100%); margin: 0 auto; }
.h2 { font-size: clamp(2.2rem, 4.4vw, 3.4rem); }
.close { padding: 190px 0 40px; text-align: center; }
.close h2 { font-size: clamp(2.8rem, 6.4vw, 5.4rem); line-height: .98; letter-spacing: -.05em; margin-bottom: 36px; }
@media (max-width: 760px) {
  .hero { padding-top: 120px; }
  .stagebox { height: 560px; border-radius: 22px; margin-top: 52px; }
  .block { padding-top: 110px; }
  .feat .frame { border-radius: 22px; }
}'''
a_feats = '\n'.join(f'''<section class="block feat"{' id="features"' if i == 0 else ''}><div class="wrap">
  <h2 class="rv">{t}</h2><p class="rv">{s}</p>
  <div class="frame paper rv"><div data-demo="{k}"></div></div></div></section>''' for i, (k, t, s) in enumerate(FEATURES))
A = head('Otto · Your day lives in the notch', A_CSS) + nav() + f'''
<main id="top">
<section class="hero"><div class="wrap">
  <h1 class="rv">Your day lives<br>in the notch.</h1>
  <p class="sub rv">To-dos, notes and meetings, one hover away.</p>
  <div class="rv">{cta()}</div>
  <div class="stagebox paper rv">{menubar()}<div class="hero-otto"><div id="live"></div></div><span class="hint">It’s live. Hover the notch, type a to-do, press return.</span></div>
</div></section>
{a_feats}
{new_faq()}
<section class="close"><div class="wrap"><h2 class="rv">Your day lives<br>in the notch.</h2><div class="rv">{cta()}</div></div></section>
</main>
''' + footer() + scripts('Otto3.furniture(); Otto3.liveNotch(document.getElementById("live"), {panelH: 330}); Otto3.demos();')

# ======================================================================== B
B_CSS = '''
body { background: #F1EFEA; }
.hero { min-height: 100svh; display: flex; flex-direction: column; justify-content: flex-end; padding: 140px 0 70px; }
.hero h1 { font-size: clamp(3.6rem, 12.5vw, 12rem); font-weight: 500; line-height: .86; letter-spacing: -.065em; }
.hero .row { display: flex; justify-content: space-between; align-items: flex-end; gap: 32px; margin-top: 44px; flex-wrap: wrap; }
.hero .row p { font-size: 21px; color: var(--muted); margin: 0; max-width: 18em; }
.hero .assure { justify-content: flex-start; }
.top-notch { position: absolute; top: 0; left: 50%; transform: translateX(-50%); width: 200px; height: 32px; background: #000; border-radius: 0 0 12px 12px; z-index: 60; }
.top-notch::before, .top-notch::after { content: ""; position: absolute; top: 0; width: 12px; height: 12px; }
.top-notch::before { left: -12px; background: radial-gradient(circle at 0 100%, transparent 11.5px, #000 12px); }
.top-notch::after { right: -12px; background: radial-gradient(circle at 100% 100%, transparent 11.5px, #000 12px); }
.story { height: 520vh; position: relative; }
.pin { position: sticky; top: 0; height: 100svh; display: grid; grid-template-columns: 1fr 1.05fr; align-items: center; gap: 40px; }
.words { position: relative; height: 1.1em; font-size: clamp(3.4rem, 9vw, 8.6rem); font-weight: 500; letter-spacing: -.06em; line-height: 1; }
.words span { position: absolute; left: 0; top: 0; opacity: 0; transform: translateY(40%); transition: opacity .6s var(--ease), transform .8s var(--ease); }
.words span.on { opacity: 1; transform: none; }
.words span.past { opacity: 0; transform: translateY(-40%); }
.lines { position: relative; margin-top: 26px; min-height: 5em; }
.lines p { position: absolute; margin: 0; max-width: 22em; font-size: 19px; color: var(--muted); opacity: 0; transition: opacity .6s var(--ease); }
.lines p.on { opacity: 1; transition-delay: .15s; }
.prog { display: flex; gap: 6px; margin-top: 30px; }
.prog i { width: 22px; height: 4px; border-radius: 2px; background: var(--line); transition: background .4s, width .5s var(--ease); }
.prog i.on { background: var(--ink); width: 44px; }
.scene { position: relative; height: min(560px, 78svh); border-radius: 32px; overflow: hidden; }
.scene .ot-host { position: absolute; top: 0; left: 0; right: 0; }
.scene .md { position: absolute; left: 50%; top: 120px; margin: 0; transform: translate(-50%, 30px); opacity: 0; transition: opacity .7s var(--ease), transform .9s var(--ease); width: min(440px, 88%); }
.scene.keep .md { opacity: 1; transform: translate(-50%, 0); }
.scene .ot-mcard { position: relative; }
.float-obj { position: absolute; border-radius: 14px; background: #fff; box-shadow: 0 20px 40px -14px rgba(0,0,0,.2); font-size: 13px; padding: 10px 14px; display: flex; align-items: center; gap: 8px; transition: transform 1.2s var(--ease), opacity .8s; }
.also { padding: 160px 0 40px; }
.also .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-top: 40px; }
.also .frame { min-height: 400px; }
.also h3 { font-size: 26px; margin: 22px 0 6px; } .also p { color: var(--muted); margin: 0; }
.block { padding: 150px 0 0; }
.h2 { font-size: clamp(2.6rem, 6vw, 5rem); font-weight: 500; letter-spacing: -.055em; }
.close { padding: 170px 0 30px; text-align: center; }
.close .eyes { width: min(760px, 86%); margin: 0 auto 50px; color: var(--ink); }
.close h2 { font-size: clamp(2.8rem, 7vw, 6rem); font-weight: 500; letter-spacing: -.06em; line-height: .92; margin-bottom: 36px; }
@media (max-width: 900px) {
  .pin { grid-template-columns: 1fr; align-content: center; gap: 22px; padding-top: 70px; }
  .scene { height: 52svh; border-radius: 22px; }
  .lines { min-height: 3.6em; } .lines p { font-size: 16px; }
  .also .grid { grid-template-columns: 1fr; }
  .hero { justify-content: center; }
}
@media (prefers-reduced-motion: reduce) { .story { height: auto; } .pin { position: static; } }'''
SCENES = [('Capture.', 'Press ⌃⇧N anywhere. Type it, press return, back to work.'),
          ('Write.', 'Notes sit next to your to-dos. Headings, lists, links, code.'),
          ('Join.', 'The notch counts down to your next meeting, then opens with Join.'),
          ('Keep.', 'Everything is a plain Markdown file on your Mac. No account, ever.')]
B = head('Otto · Your day, in the notch', B_CSS) + '<div class="top-notch" aria-hidden="true"></div>' + nav(False) + f'''
<main id="top">
<section class="hero"><div class="wrap">
  <h1 class="rv">Your day,<br>in the notch.</h1>
  <div class="row rv"><p>To-dos, notes and meetings, one hover away.</p><div>{cta()}</div></div>
</div></section>
<section class="story" id="features"><div class="wrap pin">
  <div>
    <div class="words">{''.join(f'<span>{w}</span>' for w, _ in SCENES)}</div>
    <div class="lines">{''.join(f'<p>{s}</p>' for _, s in SCENES)}</div>
    <div class="prog">{'<i></i>' * len(SCENES)}</div>
  </div>
  <div class="scene paper">{menubar()}<div class="ot-host"></div><div data-demo="files"></div></div>
</div></section>
<section class="also"><div class="wrap">
  <h2 class="h2 rv">And the rest.</h2>
  <div class="grid">
    <div class="rv"><div class="frame paper"><div data-demo="layout"></div></div><h3>In the notch, or floating.</h3><p>The same Otto, as a floating panel if you prefer.</p></div>
    <div class="rv"><div class="frame paper"><div data-demo="keys"></div></div><h3>One shortcut, from anywhere.</h3><p>⌃⇧N opens Otto with your cursor in a new to-do.</p></div>
  </div>
</div></section>
{new_faq()}
<section class="close"><div class="wrap"><div class="eyes" data-logo="currentColor" aria-hidden="true"></div><h2 class="rv">Say hi<br>to Otto.</h2><div class="rv">{cta()}</div></div></section>
</main>
''' + footer(False) + scripts('''
Otto3.furniture(); Otto3.demos();
(() => {
  const story = document.querySelector('.story'), scene = document.querySelector('.scene');
  const words = [...document.querySelectorAll('.words span')], lines = [...document.querySelectorAll('.lines p')], prog = [...document.querySelectorAll('.prog i')];
  const host = scene.querySelector('.ot-host');
  const o = Otto3.staticOtto(host, { presence: true, panelH: 330 });
  host.insertAdjacentHTML('beforeend', window.OttoUI.Otto.prototype.meetHTML.call({}));
  const card = host.querySelector('.ot-mcard');
  let cur = -1, typing = null;
  const set = async (i) => {
    if (i === cur) return; cur = i;
    words.forEach((w, k) => { w.classList.toggle('on', k === i); w.classList.toggle('past', k < i); });
    lines.forEach((l, k) => l.classList.toggle('on', k === i));
    prog.forEach((p, k) => p.classList.toggle('on', k === i));
    scene.classList.toggle('keep', i === 3);
    card.classList.toggle('show', i === 2);
    card.style.width = Math.min(540, host.clientWidth - 24) + 'px';
    if (i === 0) { o.s.active = 'work'; o.s.view = 'list'; o.o.panelH = 330; o.render(); o.setState('open'); if (!Otto3.reduce) { o.touched = false; const sp = o.space(); sp.items = sp.items.filter((t) => t.title !== 'Water the plants'); o.render(); await Otto3.sleep(700); if (cur === 0) o.demo('Water the plants'); } }
    if (i === 1) { o.touched = true; o.s.active = 'notes'; o.s.view = 'page'; o.s.page = o.s.notes[0].id; o.o.panelH = 330; o.render(); o.setState('open'); }
    if (i === 2 || i === 3) { o.touched = true; o.setState('idle'); }
  };
  const onScroll = () => {
    const r = story.getBoundingClientRect(), total = r.height - innerHeight;
    const p = Math.min(.999, Math.max(0, -r.top / total));
    set(Math.floor(p * words.length));
  };
  addEventListener('scroll', onScroll, { passive: true }); onScroll(); set(0);
})();''')

# ======================================================================== C
C_CSS = '''
body { background: #F5F3EF; }
.hero { min-height: 100svh; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; padding: 110px 0 60px; }
.big-eyes { width: min(620px, 78vw); color: var(--ink); opacity: 0; transform: scale(.96); transition: opacity 1.6s var(--soft), transform 2s var(--soft); }
.loaded .big-eyes { opacity: 1; transform: none; }
.hero h1 { margin-top: 64px; font-size: clamp(2rem, 3.6vw, 3rem); line-height: 1.1; }
.hero .sub { margin: 10px 0 34px; color: var(--muted); font-size: 18px; }
.quiet { opacity: 0; transform: translateY(10px); transition: opacity 1.4s var(--soft) .5s, transform 1.6s var(--soft) .5s; }
.loaded .quiet { opacity: 1; transform: none; }
.scroll-cue { margin-top: 60px; font-size: 13px; color: var(--faint); letter-spacing: .02em; }
.meet-otto { padding: 120px 0 0; text-align: center; }
.meet-otto p { color: var(--muted); font-size: 18px; margin: 0 0 40px; }
.stagebox { border-radius: 36px; height: min(600px, 74vh); position: relative; overflow: hidden; }
.stagebox .hero-otto { position: absolute; top: 0; left: 0; right: 0; }
.rv { transition-duration: 1.6s, 1.8s; transition-timing-function: var(--soft); }
.feat { padding: 190px 0 0; }
.feat .row { display: grid; grid-template-columns: 1fr 1.25fr; gap: 72px; align-items: center; }
.feat.flip .row > :first-child { order: 2; }
.feat h2 { font-size: clamp(2rem, 3.6vw, 2.9rem); line-height: 1.06; }
.feat p { color: var(--muted); font-size: 18px; margin: 16px 0 0; max-width: 24em; }
.list { padding: 190px 0 0; }
.list ul { list-style: none; margin: 34px 0 0; padding: 0; border-top: 1px solid var(--line); }
.list li { display: grid; grid-template-columns: 1fr 1.4fr; gap: 24px; padding: 26px 0; border-bottom: 1px solid var(--line); font-size: 19px; }
.list li span { color: var(--muted); font-size: 17px; }
.block { padding: 190px 0 0; }
.h2 { font-size: clamp(2rem, 3.6vw, 2.9rem); }
.close { padding: 200px 0 20px; text-align: center; }
.close .eyes { width: min(300px, 60vw); margin: 0 auto 44px; }
.close h2 { font-size: clamp(2rem, 3.6vw, 3rem); margin-bottom: 30px; }
@media (max-width: 860px) {
  .feat .row { grid-template-columns: 1fr; gap: 30px; }
  .feat.flip .row > :first-child { order: 0; }
  .list li { grid-template-columns: 1fr; gap: 4px; }
  .stagebox { height: 560px; border-radius: 24px; }
}'''
c_feats = ''
for i, (k, t, s) in enumerate([FEATURES[0], FEATURES[2], FEATURES[1]]):
    c_feats += f'''<section class="feat{' flip' if i % 2 else ''}"{' id="features"' if i == 0 else ''}><div class="wrap row">
  <div class="rv"><h2>{t}</h2><p>{s}</p></div>
  <div class="frame paper rv"><div data-demo="{k}"></div></div></div></section>'''
C = head('Otto', C_CSS) + nav() + f'''
<main id="top">
<section class="hero"><div class="wrap" style="display:flex;flex-direction:column;align-items:center">
  <div class="big-eyes" data-logo="currentColor" role="img" aria-label="Otto"></div>
  <h1 class="quiet">Your day lives in the notch.</h1>
  <p class="sub quiet">To-dos, notes and meetings, one hover away.</p>
  <div class="quiet">{cta()}</div>
  <div class="scroll-cue quiet">Scroll to meet it</div>
</div></section>
<section class="meet-otto"><div class="wrap">
  <p class="rv">This is Otto. Hover the notch.</p>
  <div class="stagebox paper rv">{menubar()}<div class="hero-otto"><div id="live"></div></div></div>
</div></section>
{c_feats}
<section class="list"><div class="narrow">
  <h2 class="h2 rv">The small things.</h2>
  <ul class="rv">
    <li>In the notch, or floating<span>No notch? The same Otto as a floating panel.</span></li>
    <li>Keyboard first<span>⌃⇧N from any app. Tab switches list, space ticks it off.</span></li>
    <li>Plain files<span>Markdown in a folder you choose. Open it anywhere.</span></li>
    <li>Private<span>No account, no server. Your to-dos and notes stay on your Mac.</span></li>
  </ul></div></section>
{new_faq()}
<section class="close"><div class="wrap"><div class="eyes" data-logo="currentColor" aria-hidden="true"></div><h2 class="rv">Your day lives in the notch.</h2><div class="rv">{cta()}</div></div></section>
</main>
''' + footer(False) + scripts('Otto3.furniture(); Otto3.demos(); Otto3.liveNotch(document.getElementById("live"), {panelH: 330}); requestAnimationFrame(() => document.body.classList.add("loaded"));')

# ======================================================================== index
IDX = head('Otto · three directions', '''
.idx { padding: 120px 0; } .idx h1 { font-size: clamp(2.4rem, 5vw, 4rem); }
.idx ul { list-style: none; padding: 0; margin: 40px 0 0; border-top: 1px solid var(--line); }
.idx li a { display: grid; grid-template-columns: 60px 1fr; gap: 10px; padding: 26px 0; border-bottom: 1px solid var(--line); text-decoration: none; font-size: 22px; letter-spacing: -.02em; }
.idx li span { color: var(--muted); font-size: 16px; display: block; margin-top: 4px; letter-spacing: 0; }''') + '''
<main class="idx narrow"><h1>Otto, three directions.</h1>
<ul>
<li><a href="a/"><b>A</b><div>Calm<span>Supaste-like. Headline, CTA, a clean notch, then one section per feature with a short loop.</span></div></a></li>
<li><a href="b/"><b>B</b><div>Narrative scroll<span>FacilPay-like. A giant word per scene, one notch that changes as you scroll.</span></div></a></li>
<li><a href="c/"><b>C</b><div>Eyes first<span>La Nube-like. Otto’s eyes open the page; the notch arrives as you scroll.</span></div></a></li>
</ul></main></body></html>'''

for name, html in (('a', A), ('b', B), ('c', C)):
    (ROOT / name).mkdir(exist_ok=True)
    (ROOT / name / 'index.html').write_text(html)
(ROOT / 'index.html').write_text(IDX)
print('ok')
