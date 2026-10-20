/* Otto website — v2. The MacBook straightens and grows as you scroll into it. */
(() => {
  const mac = document.getElementById('mac');
  const stage = document.getElementById('mac-stage');
  if (!mac || !stage || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  let raf = 0;
  const update = () => {
    raf = 0;
    const r = stage.getBoundingClientRect();
    const vh = innerHeight;
    // 0 while the top of the Mac is at the bottom of the window, 1 once it reaches 12% from the top
    const p = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.88)));
    const e = 1 - Math.pow(1 - p, 2);
    mac.style.transform = `rotateX(${((1 - e) * 22).toFixed(2)}deg) scale(${(0.86 + 0.14 * e).toFixed(4)})`;
  };
  const ask = () => { if (!raf) raf = requestAnimationFrame(update); };
  addEventListener('scroll', ask, { passive: true });
  addEventListener('resize', ask);
  update();
})();
