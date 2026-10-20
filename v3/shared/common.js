/* Otto v3 — shared behaviour: the logo's eyes, reveals, the live notch and the small looping demos. */
(() => {
  'use strict';
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const $ = (s, r = document) => r.querySelector(s);
  const T_PATH = window.OTTO_T_PATH;

  /* ---------- the logo, with the holes of the two O's as eyes ----------
     Same creature as the current footer: the holes drift toward the cursor with inertia,
     glance around when the cursor rests, blink every few seconds. */
  function OttoLogo(host, o = {}) {
    o = Object.assign({ fill: 'currentColor', follow: 0.1, reach: 0.35 }, o);
    const id = 'm' + Math.random().toString(36).slice(2, 7);
    host.innerHTML = `<svg viewBox="0 0 883 430" role="img" aria-label="Otto">
      <defs><mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="883" height="430">
        <rect width="883" height="430" fill="#fff"/>
        <circle class="eL" r="52.35" fill="#000" transform="translate(167.15 230.9)"/>
        <circle class="eR" r="52.35" fill="#000" transform="translate(761.2 230.9)"/>
      </mask></defs>
      <g fill="${o.fill}" mask="url(#${id})"><path d="${T_PATH}"/><circle cx="144.487" cy="249.857" r="144.487"/><circle cx="738.514" cy="249.857" r="144.487"/></g>
    </svg>`;
    const svg = host.querySelector('svg');
    const eyes = [{ el: svg.querySelector('.eL'), cx: 144.487, cy: 249.857 }, { el: svg.querySelector('.eR'), cx: 738.514, cy: 249.857 }];
    const TRAVEL = 52;
    let cur = [[0.16, -0.13], [0.16, -0.13]], target = null, saccade = [0.16, -0.13], last = 0, blink = 1, busy = false;
    const apply = () => eyes.forEach((e, i) => e.el.setAttribute('transform', `translate(${(e.cx + cur[i][0] * TRAVEL).toFixed(2)} ${(e.cy + cur[i][1] * TRAVEL).toFixed(2)}) scale(1 ${blink.toFixed(3)})`));
    apply();
    const api = {
      svg,
      blink: async () => { if (busy || reduce) return; busy = true; for (let t = 0; t <= 1.001; t += 0.2) { blink = 1 - Math.sin(t * Math.PI) * 0.95; apply(); await sleep(24); } blink = 1; busy = false; apply(); },
      look: (x, y) => { saccade = [x, y]; last = 0; },
    };
    if (reduce) return api;
    addEventListener('pointermove', (ev) => {
      const r = svg.getBoundingClientRect(); last = performance.now();
      target = eyes.map((e) => {
        const sx = r.left + (e.cx / 883) * r.width, sy = r.top + (e.cy / 430) * r.height;
        const dx = ev.clientX - sx, dy = ev.clientY - sy, d = Math.hypot(dx, dy) || 1;
        const m = Math.min(d / (r.width * o.reach), 1);
        return [(dx / d) * m, (dy / d) * m];
      });
    }, { passive: true });
    setInterval(() => { if (Math.random() < 0.8) api.blink(); }, 4300);
    setInterval(() => { saccade = [Math.random() * 1.4 - 0.7, Math.random() * 1.2 - 0.6]; }, 2600);
    let inView = true;
    new IntersectionObserver(([e]) => { inView = e.isIntersecting; }).observe(svg);
    (function tick(now) {
      if (inView) {
        const idle = now - last > 2500;
        cur = cur.map((c, i) => { const t = idle || !target ? saccade : target[i]; return [c[0] + (t[0] - c[0]) * o.follow, c[1] + (t[1] - c[1]) * o.follow]; });
        apply();
      }
      requestAnimationFrame(tick);
    })(performance.now());
    return api;
  }

  /* ---------- page furniture ---------- */
  function furniture() {
    const nav = $('.nav');
    if (nav) { const f = () => nav.classList.toggle('solid', scrollY > 40); f(); addEventListener('scroll', f, { passive: true }); }
    const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }), { threshold: 0.18, rootMargin: '0px 0px -6% 0px' });
    document.querySelectorAll('.rv').forEach((el) => io.observe(el));
    document.querySelectorAll('[data-logo]').forEach((el) => OttoLogo(el, { fill: el.dataset.logo || 'currentColor' }));
  }

  /* ---------- the live notch ---------- */
  function liveNotch(host, o = {}) {
    const UI = window.OttoUI;
    const otto = new UI.Otto(host, Object.assign({ interactive: true, simple: true, notchW: 185, notchH: 32, presence: true, margin: 8, panelH: 340 }, o));
    const start = async () => {
      if (reduce) { otto.open(false); return; }
      await sleep(500); if (otto.state === 'idle') otto.setState('hover');
      await sleep(320); otto.open(false);
      await sleep(1100); otto.demo('Water the plants');
    };
    const io = new IntersectionObserver(([e]) => { if (e.intersectionRatio > 0.4) { io.disconnect(); start(); } }, { threshold: [0, 0.4, 0.8] });
    io.observe(host);
    return otto;
  }

  /* ---------- small looping demos, one idea each ---------- */
  const onView = (el, fn) => {
    let running = false, visible = false;
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible && !running) { running = true; fn(() => visible).finally(() => { running = false; }); } }, { threshold: 0.35 }).observe(el);
  };
  function staticOtto(host, o) {
    const UI = window.OttoUI;
    return new UI.Otto(host, Object.assign({ interactive: false, simple: true, presence: false, notchW: 185, notchH: 32, panelH: 330, openW: 560 }, o));
  }
  const DEMOS = {
    capture(el) {
      const host = document.createElement('div'); el.appendChild(host);
      const o = staticOtto(host, {});
      if (reduce) { o.setState('open', true); return; }
      onView(el, async (vis) => {
        while (vis()) {
          o.s = Object.assign(o.s, { active: 'work', view: 'list' }); o.render();
          o.setState('idle'); await sleep(900); o.setState('hover'); await sleep(350); o.setState('open');
          await sleep(900); o.touched = false; await o.demo('Water the plants');
          await sleep(2600);
          const sp = o.space(); sp.items = sp.items.filter((t) => t.title !== 'Water the plants'); o.render();
        }
      });
    },
    notes(el) {
      const host = document.createElement('div'); el.appendChild(host);
      const o = staticOtto(host, { panelH: 0, notchH: 0, top: true });
      o.s.active = 'notes'; o.s.view = 'page'; o.s.page = o.s.notes[0].id; o.render();
      o.setState('open', true);
    },
    meeting(el) {
      const host = document.createElement('div'); el.appendChild(host);
      const o = staticOtto(host, { presence: true });
      host.insertAdjacentHTML('beforeend', window.OttoUI.Otto.prototype.meetHTML.call({}));
      const card = host.querySelector('.ot-mcard'); card.style.width = '540px';
      if (reduce) { card.classList.add('show'); return; }
      onView(el, async (vis) => {
        while (vis()) { card.classList.add('show'); await sleep(4800); card.classList.remove('show'); await sleep(1600); }
      });
    },
    keys(el) {
      el.innerHTML = `<div class="keys"><span>⌃</span><span>⇧</span><span>N</span></div><div class="keys-otto"></div>`;
      const ks = [...el.querySelectorAll('.keys span')];
      const o = staticOtto(el.querySelector('.keys-otto'), { panelH: 150 });
      o.fakeFocus = true; o.render();
      if (reduce) { o.setState('open', true); return; }
      onView(el, async (vis) => {
        while (vis()) {
          o.setState('idle'); ks.forEach((k) => k.classList.remove('down'));
          await sleep(1100);
          for (const k of ks) { k.classList.add('down'); await sleep(160); }
          await sleep(120); o.setState('open'); await sleep(450); ks.forEach((k) => k.classList.remove('down'));
          await sleep(2600);
        }
      });
    },
    layout(el) {
      el.innerHTML = `<div class="lay-a"></div><div class="lay-b"></div><div class="lay-tag"><b>In the notch</b><b>Floating</b></div>`;
      const a = staticOtto(el.querySelector('.lay-a'), { panelH: 300 }); a.setState('open', true);
      const UI = window.OttoUI; UI.mountFloating(el.querySelector('.lay-b'));
      if (reduce) return;
      onView(el, async (vis) => { while (vis()) { el.classList.remove('alt'); await sleep(3200); el.classList.add('alt'); await sleep(3200); } });
    },
    files(el) {
      el.innerHTML = `<div class="md"><div class="md-bar"><i></i><i></i><i></i><span>Documents/Otto/Work.md</span></div><pre><b># Work</b>

<em>- [ ]</em> Send the proposal to Simon
<em>- [ ]</em> Review the new onboarding
<em>- [ ]</em> Prep for Monday’s standup
    <em>- [ ]</em> Collect updates from the team
    <em>- [ ]</em> Write the agenda
<em>- [x]</em> Book the team offsite</pre></div>`;
    },
  };
  function demos() { document.querySelectorAll('[data-demo]').forEach((el) => DEMOS[el.dataset.demo] && DEMOS[el.dataset.demo](el)); }

  window.Otto3 = { OttoLogo, liveNotch, staticOtto, furniture, demos, reduce, sleep };
})();
