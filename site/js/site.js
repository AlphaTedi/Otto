/* Otto website — site.js. No dependencies. */
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  /* ---------- dev only: Agentation feedback toolbar, never loads on the live domain ---------- */
  if (/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname)) {
    const s = document.createElement('script');
    s.src = new URL('../dev/agentation.js', document.currentScript ? document.currentScript.src : location.href).href;
    s.defer = true;
    document.head.appendChild(s);
  }

  /* ---------- hero: the real panel, live. Opens on load, then types one to-do ---------- */
  const UI = window.OttoUI;
  const heroHost = $('#hero-otto');
  if (UI && heroHost) {
    // the notch gets whatever room is left once the meeting card and the copy fit
    const ph = Math.round(Math.max(290, Math.min(380, innerHeight - 28 - 132 - (innerHeight < 840 ? 290 : 400))));
    document.documentElement.style.setProperty('--ph', (ph + 132 + 18) + 'px');
    const o = new UI.Otto(heroHost, { interactive: true, simple: true, notchW: 185, notchH: 32, presence: true, margin: 8, panelH: ph, meeting: true });
    const tip = $('#hero-tip');
    o.onInteract = () => tip && tip.classList.add('used');
    const start = async () => {
      if (reduce) { o.open(false); return; }
      await sleep(700); if (o.state === 'idle') o.setState('hover');
      await sleep(320); o.open(false);
      if (tip) setTimeout(() => tip.classList.add('show'), 2600);
      await sleep(1100); o.demo('Book flights to Lisbon');
    };
    if (heroHost.hasAttribute('data-open-on-view')) {
      // v2: wait until the Mac is properly on screen
      const io = new IntersectionObserver(([e]) => { if (e.intersectionRatio > 0.3) { io.disconnect(); start(); } }, { threshold: [0, 0.3, 0.6] });
      io.observe(heroHost.closest('.mac-screen') || heroHost);
    } else start();
  }

  /* ---------- feature cards: the same components, as still previews ---------- */
  if (UI) {
    document.querySelectorAll('[data-otto]').forEach((el) => {
      const k = el.dataset.otto;
      if (k === 'float') UI.mountFloating(el); else UI.mountStatic(el, k);
    });
  }

  /* ---------- header: hidden at the very top of the landing page, shown on scroll ---------- */
  const header = $('.site-header');
  if (header && $('#hero')) {
    const sync = () => header.classList.toggle('is-hidden', scrollY < 120);
    sync(); addEventListener('scroll', sync, { passive: true });
  }

  /* ---------- layout switcher ---------- */
  const stage = $('#layout-stage');
  if (stage) {
    stage.dataset.mode = 'notch';
    document.querySelectorAll('.seg button').forEach((b) => b.addEventListener('click', () => {
      stage.dataset.mode = b.dataset.mode;
      document.querySelectorAll('.seg button').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
    }));
  }

  /* ---------- footer logo: the holes in the two O's are eyes ---------- */
  const svg = $('#mega');
  if (svg) {
    const eyes = [
      { el: $('#eyeL'), cx: 144.487, cy: 249.857, rest: [167.15, 230.9] },
      { el: $('#eyeR'), cx: 738.514, cy: 249.857, rest: [761.2, 230.9] },
    ];
    const TRAVEL = 52;            // how far a hole can move inside its O
    let target = null;            // unit-ish vector [-1..1]
    let cur = eyes.map((e) => [(e.rest[0] - e.cx) / TRAVEL, (e.rest[1] - e.cy) / TRAVEL]);
    let lastMove = 0, saccade = [0.25, -0.2], blink = 1, blinking = false;

    const apply = () => eyes.forEach((e, i) => {
      const x = e.cx + cur[i][0] * TRAVEL, y = e.cy + cur[i][1] * TRAVEL;
      e.el.setAttribute('transform', `translate(${x.toFixed(2)} ${y.toFixed(2)}) scale(1 ${blink.toFixed(3)})`);
    });
    apply();

    if (!reduce) {
      addEventListener('pointermove', (ev) => {
        const r = svg.getBoundingClientRect(); lastMove = performance.now();
        target = eyes.map((e) => {
          const sx = r.left + (e.cx / 883) * r.width, sy = r.top + (e.cy / 430) * r.height;
          const dx = ev.clientX - sx, dy = ev.clientY - sy, d = Math.hypot(dx, dy) || 1;
          const m = Math.min(d / (r.width * 0.35), 1);
          return [(dx / d) * m, (dy / d) * m];
        });
      }, { passive: true });

      const doBlink = async () => {
        if (blinking) return; blinking = true;
        for (let t = 0; t <= 1; t += 0.2) { blink = 1 - Math.sin(t * Math.PI) * 0.95; await sleep(22); }
        blink = 1; blinking = false;
      };
      setInterval(() => { if (Math.random() < 0.8) doBlink(); }, 4300);
      setInterval(() => { saccade = [Math.random() * 1.4 - 0.7, Math.random() * 1.2 - 0.6]; }, 2600);

      let inView = true;
      new IntersectionObserver(([e]) => { inView = e.isIntersecting; }).observe(svg);
      (function tick(now) {
        if (inView) {
          const idle = now - lastMove > 2500;
          cur = cur.map((c, i) => {
            const t = idle || !target ? saccade : target[i];
            return [c[0] + (t[0] - c[0]) * 0.12, c[1] + (t[1] - c[1]) * 0.12];
          });
          apply();
        }
        requestAnimationFrame(tick);
      })(performance.now());
    }
  }
})();
