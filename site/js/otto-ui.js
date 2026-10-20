/* Otto UI — an interactive replica of the app's "In the notch" layout.
   Mirrors TodoBrowsingView / NotesSpaceView / UpNextSection. No dependencies. */
(() => {
  'use strict';

  /* ---------------- icons (Lucide, as in the app since 2026-09-27) ---------------- */
  const P = {
    check: '<path d="M20 6 9 17l-5-5"/>',
    plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
    gear: '<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915"/><circle cx="12" cy="12" r="3"/>',
    chevR: '<path d="m9 18 6-6-6-6"/>',
    chevD: '<path d="m6 9 6 6 6-6"/>',
    chevL: '<path d="m15 18-6-6 6-6"/>',
    ellipsis: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    align: '<path d="M21 5H3"/><path d="M15 12H3"/><path d="M17 19H3"/>',
    note: '<path d="M21 9a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 15 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2z"/><path d="M15 3v5a1 1 0 0 0 1 1h5"/>',
    chart: '<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    keyboard: '<path d="M10 8h.01"/><path d="M12 12h.01"/><path d="M14 8h.01"/><path d="M16 12h.01"/><path d="M18 8h.01"/><path d="M6 8h.01"/><path d="M7 16h10"/><path d="M8 12h.01"/><rect width="20" height="16" x="2" y="4" rx="2"/>',
    folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    sliders: '<path d="M10 5H3"/><path d="M12 19H3"/><path d="M14 3v4"/><path d="M16 17v4"/><path d="M21 12h-9"/><path d="M21 19h-5"/><path d="M21 5h-7"/><path d="M8 10v4"/><path d="M8 12H3"/>',
    power: '<path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/>',
    calendar: '<path d="M8 2v4"/><path d="M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
    notepad: '<path d="M8 2v4"/><path d="M12 2v4"/><path d="M16 2v4"/><rect width="16" height="18" x="4" y="4" rx="2"/><path d="M8 10h6"/><path d="M8 14h8"/><path d="M8 18h5"/>',
    list: '<path d="M3 5h.01"/><path d="M3 12h.01"/><path d="M3 19h.01"/><path d="M8 5h13"/><path d="M8 12h13"/><path d="M8 19h13"/>',
    listOrdered: '<path d="M11 5h10"/><path d="M11 12h10"/><path d="M11 19h10"/><path d="M4 4h1v5"/><path d="M4 9h2"/><path d="M6.5 20H3.4c0-1 2.6-1.925 2.6-3.5a1.5 1.5 0 0 0-2.6-1.02"/>',
    listChecks: '<path d="M13 5h8"/><path d="M13 12h8"/><path d="M13 19h8"/><path d="m3 17 2 2 4-4"/><path d="m3 7 2 2 4-4"/>',
    type: '<path d="M12 4v16"/><path d="M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2"/><path d="M9 20h6"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    code: '<path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/>',
    quote: '<path d="M16 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/><path d="M5 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/>',
    braces: '<path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/><path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/>',
    download: '<path d="M12 15V3"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/>',
    image: '<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
  };
  const ic = (n, cls = '') => `<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true">${P[n]}</svg>`;
  const MEET = '<svg class="meet" viewBox="0 0 87.5 72" aria-hidden="true"><path fill="#00832D" d="M49.5 36L58.03 45.75L69.5 53.08L71.5 36.06L69.5 19.42L57.81 25.86Z"/><path fill="#0066DA" d="M0 51.5V66C0 69.315 2.685 72 6 72H20.5L23.5 61.04L20.5 51.5L10.55 48.5Z"/><path fill="#E94235" d="M20.5 0L0 20.5L10.55 23.5L20.5 20.5L23.45 11.09Z"/><path fill="#2684FC" d="M0 20.5H20.5V51.5H0Z"/><path fill="#00AC47" d="M82.6 8.68L69.5 19.42V53.08L82.66 63.87C84.63 65.41 87.51 64.005 87.51 61.5V11C87.51 8.465 84.565 7.075 82.6 8.68Z M49.5 36V51.5H20.5V72H63.5C66.815 72 69.5 69.315 69.5 66V53.08Z"/><path fill="#FFBA00" d="M63.5 0H20.5V20.5H49.5V36L69.5 19.43V6C69.5 2.685 66.815 0 63.5 0Z"/></svg>';
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  /* ---------------- section colours (SpaceTint, dark appearance) ---------------- */
  const TINTS = {
    grocery: { sec: '#9FE0B0', base: '#78D796' },
    work: { sec: '#9CC0FF', base: '#699BFF' },
    personal: { sec: '#FFB0C9', base: '#FF87AF' },
    violet: { sec: '#C6B4FF', base: '#A082FF' },
    coral: { sec: '#FFBFA8', base: '#FF9678' },
    sky: { sec: '#A8D6FF', base: '#6EBEFF' },
    lime: { sec: '#D6EB9F', base: '#B9D76E' },
    notes: { sec: '#FFD49A', base: '#FFC36E' },
  };
  const PALETTE = ['grocery', 'work', 'personal', 'violet', 'coral', 'sky', 'lime', 'teal', 'amber'];
  /* DockTint: the B3 dock's swatches; light = base mixed half-way to white */
  const SW = { grocery: 0x9EE0B0, work: 0x8FB8FF, personal: 0xF4A9C4, violet: 0xC3B1FF, coral: 0xF5C2A6, sky: 0xA9D8FF, lime: 0xD9EBA3, teal: 0x8FE0D6, amber: 0xF5D68A, notes: 0xE5B66B };
  const dock = (k) => {
    const h = SW[k] || SW.work, r = h >> 16, g = (h >> 8) & 255, b = h & 255;
    const m = (v) => Math.round((v + 255) / 2);
    return { base: `rgb(${r},${g},${b})`, light: `rgb(${m(r)},${m(g)},${m(b)})`, rgb: `${r},${g},${b}` };
  };

  const chip = ([k, v]) => {
    const icon = { date: 'calendar', link: 'link', img: 'image' }[k];
    return `<span class="dk-chip ${k}">${icon ? ic(icon) : '@'}${esc(v)}</span>`;
  };
  let uid = 0;
  const id = () => 'o' + (++uid);
  const todo = (title, steps = [], extra = {}) => ({ id: id(), title, done: false, steps: steps.map((t) => (typeof t === 'string' ? { t, done: false } : t)), note: '', ...extra });

  function seed() {
    return {
      spaces: [
        { id: 'work', name: 'Work', tint: 'work', items: [
          todo('Send the proposal to Simon', [], { chips: [['date', 'today']] }),
          todo('Review the new onboarding', [], { chips: [['link', 'figma.com/onboarding']] }),
          todo('Fix the pricing table', [], { pre: [['img', 'Screenshot']] }),
          todo('Prep for Monday’s standup', ['Collect updates from the team', 'Write the agenda', 'Book the room', 'Share the doc in #team'], { note: 'Keep it to 15 minutes' }),
          todo('Call', [], { chips: [['at', 'matt']] }),
          todo('Book the team offsite', [], { chips: [['date', 'fri']] }),
          todo('Reply to Anna about the brief'),
        ] },
        { id: 'personal', name: 'Personal', tint: 'personal', items: [
          todo('Call the dentist', [], { chips: [['date', 'tomorrow']] }),
          todo('Book the flat in Lisbon', [], { chips: [['link', 'airbnb.com/rooms/482']] }),
          todo('Expense the team dinner', [], { pre: [['img', 'Receipt']] }),
          todo('Plan Saturday dinner', ['Buy wine', 'Ask Sara about the dessert']),
          todo('Renew passport'),
          todo('Birthday gift for', [], { chips: [['at', 'mom']] }),
          todo('Water the plants'),
        ] },
        { id: 'side', name: 'Side project', tint: 'violet', items: [
          todo('Ship the new landing page', ['Write the FAQ', 'Record the demo video', 'Set up analytics']),
          todo('Reply to beta testers', [], { chips: [['at', 'leo']] }),
          todo('Steal this hover effect', [], { chips: [['link', 'skiper-ui.com']] }),
          todo('Fix the dock tooltip', [], { pre: [['img', 'Screenshot']] }),
          todo('Post the launch on X', [], { chips: [['date', 'mon']] }),
          todo('Draft the newsletter'),
        ] },
      ],
      notes: [
        { id: id(), title: 'Monday sync', preview: 'Agenda: Q4 priorities, hiring update from Matt, launch date with Simon.', stamp: '14:05', doc: 'sync' },
        { id: id(), title: 'Lisbon trip', preview: 'Flights on Friday morning. Hotel near Alfama. Ask Simon about the tram pass.', stamp: 'yesterday 18:04' },
        { id: id(), title: 'Onboarding copy', preview: 'Shorter first screen. Say what the notch does before asking for calendar access.', stamp: '29 Sep' },
        { id: id(), title: 'Books to read', preview: 'The Design of Everyday Things, Shape Up, Working in Public.', stamp: '26 Sep' },
      ],
      completed: [
        { title: 'Buy oat milk', time: '09:12' },
        { title: 'Reply to Simon about Thursday', time: '10:47' },
      ],
      week: [3, 5, 0, 2, 6, 1],   // the six days before today, for the sparkline
      active: 'work',
      completedOpen: false,
      openRow: null,
      focus: -1,                  // -1 = the draft field, n = row n
      view: 'list',               // 'list' | 'page'
      page: null,
      kind: 'Notes',
    };
  }

  /* ---------------- natural-language dates (NLDateParser) ---------------- */
  const MON = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  const MONTHS = 'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
  const DAYS = { sun: 0, sunday: 0, mon: 1, monday: 1, tue: 2, tues: 2, tuesday: 2, wed: 3, wednesday: 3, thu: 4, thur: 4, thurs: 4, thursday: 4, fri: 5, friday: 5, sat: 6, saturday: 6 };
  const RE = new RegExp(
    '\\b(?:(today|tod)|(tomorrow|tom)|(next week)|(next\\s+)?(' + Object.keys(DAYS).sort((a, b) => b.length - a.length).join('|') + ')|(' + MONTHS + ')\\s+(\\d{1,2})|(\\d{1,2})\\s+(' + MONTHS + '))\\b', 'gi');
  const fmtShort = (d) => d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  function parseDate(text, now = new Date()) {
    let m, last = null;
    RE.lastIndex = 0;
    while ((m = RE.exec(text))) last = m;
    if (!last) return null;
    const base = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    let d = new Date(base), label;
    if (last[1]) label = 'Today';
    else if (last[2]) { d.setDate(d.getDate() + 1); label = 'Tomorrow'; }
    else if (last[3]) d.setDate(d.getDate() + 7);
    else if (last[5]) {
      const target = DAYS[last[5].toLowerCase()];
      let diff = (target - base.getDay() + 7) % 7 || 7;
      if (last[4]) diff += 7;
      d.setDate(d.getDate() + diff);
    } else {
      const mon = MON.indexOf((last[6] || last[9]).slice(0, 3).toLowerCase());
      const day = +(last[7] || last[8]);
      d = new Date(base.getFullYear(), mon, day);
      if (d < base) d.setFullYear(d.getFullYear() + 1);
    }
    const wd = d.toLocaleDateString('en-US', { weekday: 'short' });
    return { start: last.index, end: last.index + last[0].length, label: `${label || wd}, ${fmtShort(d)}` };
  }

  /* ---------------- the panel ---------------- */
  class Otto {
    constructor(host, opts = {}) {
      this.host = host;
      this.o = Object.assign({ interactive: true, notchW: 185, notchH: 32, openW: 596, panelH: 470, presence: true, top: true }, opts);
      this.s = Object.assign(seed(), opts.state || {});
      if (this.o.simple) this.simplify();
      this.state = 'idle';
      this.fresh = new Set();
      this.build();
    }

    /* the hero shows a short panel: two to-dos (one with steps), two notes, no Completed */
    simplify() { this.s.completed = []; }

    space(idv = this.s.active) { return this.s.spaces.find((x) => x.id === idv); }
    tint(sp = this.space()) { return TINTS[sp ? sp.tint : 'notes']; }
    get isNotes() { return this.s.active === 'notes'; }
    remaining(sp) { return sp.items.filter((t) => !t.done).length; }

    build() {
      const o = this.o;
      this.host.classList.add('ot', 'ot-dock');
      if (!o.interactive) this.host.classList.add('ot-static');
      if (o.simple) this.host.classList.add('ot-simple');
      this.host.innerHTML = `
        <div class="ot-notch${o.presence ? ' has-presence' : ''}" role="${o.interactive ? 'application' : 'img'}" aria-label="Otto, open in the notch" tabindex="-1">
          <div class="ot-body">
            <div class="ot-presence" aria-hidden="true">
              <span class="wing l">${MEET}</span><span class="wing"><span class="count"><i></i>in 34′</span></span>
            </div>
            <div class="ot-content${o.top ? '' : ' no-top'}"><div class="ot-enter"></div></div>
          </div>
        </div>`;
      if (o.meeting) this.host.insertAdjacentHTML('beforeend', this.meetHTML());
      this.notch = this.host.querySelector('.ot-notch');
      this.content = this.host.querySelector('.ot-content');
      this.stack = this.host.querySelector('.ot-enter');
      this.notch.style.setProperty('--nh', o.notchH + 'px');
      this.render();
      new ResizeObserver(() => this.hug()).observe(this.content);
      if (o.interactive) this.wire();
      this.setState(o.open ? 'open' : 'idle', true);
    }

    /* ---------- geometry ---------- */
    openWidth() {
      if (!this.o.interactive) return this.o.openW;
      const avail = (this.host.clientWidth || this.o.openW + 24) - 24 - (this.o.margin || 0);
      return Math.min(this.o.openW, avail);
    }
    hug() {
      if (this.state !== 'open') return;
      this.notch.style.setProperty('--h', (this.o.panelH || this.content.offsetHeight) + 'px');
    }
    setState(st, instant) {
      const n = this.notch, o = this.o;
      const prev = this.state;
      this.state = st;
      n.classList.toggle('is-open', st === 'open');
      const mc = this.host.querySelector('.ot-mcard');
      if (mc) { mc.style.width = this.openWidth() + 'px'; mc.classList.toggle('show', st === 'open'); }
      n.classList.toggle('is-hover', st === 'hover');
      const extra = o.presence ? 106 : 0;
      if (st === 'open') {
        n.style.setProperty('--w', this.openWidth() + 'px');
        n.style.setProperty('--r', '30px');
        this.hug();
      } else if (st === 'hover') {
        n.style.setProperty('--w', o.notchW + Math.max(28, extra) + 'px');
        n.style.setProperty('--h', o.notchH + 6 + 'px');
        n.style.setProperty('--r', '12px');
      } else {
        n.style.setProperty('--w', o.notchW + extra + 'px');
        n.style.setProperty('--h', o.notchH + 'px');
        n.style.setProperty('--r', '10px');
      }
      if (!instant && prev !== st && (st === 'open' || prev === 'open')) {
        n.classList.remove('squish-open', 'squish-close');
        void n.offsetWidth;
        n.classList.add(st === 'open' ? 'squish-open' : 'squish-close');
      }
    }
    open(focusField) {
      if (this.state === 'open') return;
      this.setState('open');
      if (focusField) setTimeout(() => this.focusField(), 120);
    }
    close() {
      this.closeMenu();
      this.s.focus = -1;
      this.setState('idle');
      if (document.activeElement && this.host.contains(document.activeElement)) document.activeElement.blur();
    }

    /* ---------- rendering ---------- */
    render() {
      const s = this.s;
      const sp = this.space();
      const t = this.tint(sp);
      this.host.style.setProperty('--sec', t.sec);
      this.host.style.setProperty('--sec-base', t.base);
      this.host.style.setProperty('--dk', dock(this.isNotes ? 'notes' : (sp ? sp.tint : 'work')).rgb);
      let html = '';
      if (s.view === 'page') {
        html = this.pageHTML();
      } else {
        html = `<div class="dk-scroll">${this.fieldHTML()}${this.isNotes ? this.notesHTML() : `<div class="ot-list">${this.listHTML(sp)}</div>`}</div>
          <div class="dk-foot" aria-hidden="true"></div>${this.barHTML()}`;
      }
      this.stack.innerHTML = html;
      [...this.stack.children].forEach((c, i) => c.style.setProperty('--i', i));
      this.stack.querySelectorAll('.ot-row, .ot-note').forEach((r, i) => r.style.setProperty('--i', i + 2));
      this.fresh.clear();
      this.afterRender();
    }

    meetHTML() {
      return `<div class="ot-mcard" aria-label="Upcoming meeting">
          <span class="mi">${MEET}</span>
          <div class="mc">
            <div class="r1"><span class="tm">9:30 – 10:00</span><span class="now">in 5 min</span></div>
            <h6>Design sync</h6>
            <div class="r3">
              <button class="mb">Notes</button>
              <button class="mb join">Join <kbd>⌘</kbd><kbd>↩</kbd></button>
              <button class="mb ghost">Snooze <kbd>S</kbd></button>
              <span class="avs"><span style="background:#D9CCF5;color:#5B3FA0">R</span><span style="background:#DDEBB8;color:#4C6420">W</span><span style="background:#F3CADB;color:#8A2F57">G</span><span class="plus">+1</span></span>
            </div>
          </div>
        </div>`;
    }

    barHTML() {
      const s = this.s, notes = this.isNotes;
      const items = s.spaces.map((sp) => {
        const d = dock(sp.tint);
        return `<button class="dk-item${s.active === sp.id ? ' on' : ''}" data-space="${sp.id}" style="--b:${d.base};--l:${d.light};--rgb:${d.rgb}" aria-label="${esc(sp.name)}"><i></i><span>${esc(sp.name)}</span></button>`;
      }).join('');
      return `<div class="dk-bar">
          <button class="dk-round dk-notes${notes ? ' on' : ''}" data-space="${notes ? (this.lastSpace || 'work') : 'notes'}" aria-label="Notes">${ic('notepad')}</button>
          <div class="dk-dock${notes ? ' dim' : ''}">${items}<button class="dk-plus" data-act="new" aria-label="New space">${ic('plus')}</button></div>
          <button class="dk-round ot-gear${this.menuOpen ? ' open' : ''}" data-act="gear" aria-label="Settings">${ic('gear')}</button>
        </div>`;
    }

    fieldHTML() {
      const notes = this.isNotes;
      const d = this.draft || '';
      const sp = this.space();
      return `
        <div class="ot-field dk-first${notes ? ' notes' : ''}">
          <span class="dk-dash"></span>
          <span class="ed${d ? ' has-text' : ''}">
            <span class="ph">${notes ? 'Title of a new note…' : `Add to ${esc(sp ? sp.name : '')}…`}</span>
            <span class="mirror"></span>
            <input type="text" spellcheck="false" autocomplete="off" aria-label="${notes ? 'New note' : 'New to-do'}" value="${esc(d)}" ${this.o.interactive ? '' : 'tabindex="-1"'}>
            <span class="date"></span>
          </span>
        </div>`;
    }

    oldFieldHTML() {
      const notes = this.isNotes;
      const d = this.draft || '';
      return `
        <div class="ot-field${notes ? ' notes' : ''}">
          ${notes ? `<span class="cb">${ic('note')}</span>` : '<span class="ot-cb cb"></span>'}
          <span class="ed${d ? ' has-text' : ''}">
            <span class="ph">${notes ? 'What’s on your mind?' : 'What needs doing?'}</span>
            <span class="mirror"></span>
            <input type="text" spellcheck="false" autocomplete="off" aria-label="${notes ? 'New note' : 'New to-do'}" value="${esc(d)}" ${this.o.interactive ? '' : 'tabindex="-1"'}>
            <span class="date"></span>
          </span>
          <span class="hint">${notes ? 'Save <span class="ot-cap">↩</span>' : '<span class="sw">Switch space</span> <span class="ot-cap">Tab</span>'}</span>
        </div>`;
    }

    tabsHTML() {
      const s = this.s;
      const pills = s.spaces.map((sp) => {
        const n = this.remaining(sp);
        const ind = sp.items.length === 0 ? '' : n === 0 ? ic('check', 'done-mark') : `<em>${n}</em>`;
        return `<button class="ot-pill${s.active === sp.id ? ' on' : ''}" data-space="${sp.id}" style="--pill:${TINTS[sp.tint].sec}">${esc(sp.name)}${ind}</button>`;
      }).join('');
      const newPill = this.naming
        ? `<span class="ot-pill new" style="border-style:solid"><input class="namer" placeholder="Section name" style="width:96px;font-size:13px;font-weight:500"></span>`
        : `<button class="ot-pill new" data-act="new">${ic('plus')}New section</button>`;
      return `
        <div class="ot-tabs">
          <button class="ot-pill notes${this.isNotes ? ' on' : ''}" data-space="notes">Notes<em>${s.notes.length}</em></button>
          <span class="rule"></span>
          <div class="scroller">${pills}${newPill}</div>
          <button class="ot-gear${this.menuOpen ? ' open' : ''}" data-act="gear" aria-label="Settings">${ic('gear')}</button>
        </div>`;
    }

    listHTML(sp) {
      if (!sp.items.length) {
        return `<div class="ot-empty">
          <svg viewBox="0 0 120 96" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <g class="page"><rect x="24" y="30" width="64" height="56" rx="10" stroke-width="2.2"/><path d="M36 50 Q42 55 48 50 M64 50 Q70 55 76 50 M50 70 Q56 67 62 70" stroke-width="2.2"/></g>
            <path class="z1" d="M88 22 L98 22 L88 34 L98 34" stroke-width="2"/><path class="z2" d="M102 6 L109 6 L102 14 L109 14" stroke-width="1.6"/>
          </svg>
          <h4>This list is napping</h4><p>Wake it up with your first to-do.</p></div>`;
      }
      return sp.items.map((t, i) => this.rowHTML(t, i)).join('');
    }

    rowHTML(t, i) {
      const open = this.s.openRow === t.id;
      const focus = this.s.focus === i;
      let below = '';
      if (open || t.steps.length) {
        const shown = open ? t.steps : t.steps.slice(0, this.o.simple ? 1 : 2);
        const more = t.steps.length - shown.length;
        below = `<div class="ot-steps">
          ${open ? `<div class="ot-note-field"><input data-note="${t.id}" placeholder="Add a note…" value="${esc(t.note)}"></div>` : ''}
          ${shown.map((st, k) => `<div class="ot-step${st.done ? ' done' : ''}"><button class="sb" data-step="${t.id}:${k}" aria-label="Complete step">${ic('check')}</button><span>${esc(st.t)}</span></div>`).join('')}
          ${more > 0 ? `<div class="ot-more" data-open="${t.id}">${ic('ellipsis')}${more} more step${more === 1 ? '' : 's'}</div>` : ''}
          ${open ? `<div class="ot-step draft"><span class="sb"></span><input data-newstep="${t.id}" placeholder="Type to add a step"></div>` : ''}
        </div>`;
      }
      return `
        <div class="ot-row${open ? ' open' : ''}${focus ? ' focus' : ''}${t.done ? ' done' : ''}${this.fresh.has(t.id) ? ' enter' : ''}" data-row="${t.id}">
          <div class="line">
            <button class="ot-cb${t.done ? ' on' : ''}" data-check="${t.id}" aria-label="Complete">${ic('check')}</button>
            <span class="title">${(t.pre || []).map(chip).join('')}${esc(t.title)}${(t.chips || []).map(chip).join('')}</span>
            <span class="gutter">${t.note && !open ? `<span class="has-note">${ic('align')}</span>` : ''}<span class="badge">⌘↵</span><span class="grip"><i></i><i></i><i></i><i></i><i></i><i></i></span></span>
          </div>${below}
        </div>`;
    }

    completedHTML() {
      const s = this.s;
      if (this.o.simple || !s.completed.length) return '';
      const today = s.completed.length;
      const all = s.week.concat(today);
      const max = Math.max(...all, 1);
      const bars = all.map((v, k) => {
        if (!v) return '<i style="height:3px;background:rgba(255,255,255,.08)"></i>';
        const h = Math.max(3, Math.round((v / max) * 16));
        const op = k === all.length - 1 ? 1 : 0.30 + 0.30 * (v / max);
        return `<i style="height:${h}px;opacity:${op}"></i>`;
      }).join('');
      const entries = s.completedOpen
        ? `<div class="entries">${s.completed.slice().reverse().map((c) => `<div class="entry"><span class="eb">${ic('check')}</span><span>${esc(c.title)}</span><time>${c.time}</time></div>`).join('')}</div>`
        : '';
      return `<div class="ot-completed${s.completedOpen ? ' open' : ''}">
        <button class="head" data-act="completed" aria-expanded="${s.completedOpen}">${ic('chevR', 'chev')}<span class="lbl">Completed</span><span class="n">${today + s.week.reduce((a, b) => a + b, 0)}</span><span class="ot-spark" aria-hidden="true">${bars}</span></button>
        ${entries}</div>`;
    }

    notesHTML() {
      const kind = '';
      return `${kind}
        <div class="ot-stream${this.draft ? ' dim' : ''}">${this.s.notes.map((n, i) => `
          <div class="ot-note${this.s.focus === i ? ' focus' : ''}${n.landing ? ' landing' : ''}${this.fresh.has(n.id) ? ' enter' : ''}" data-notei="${n.id}">
            <span class="ng">${ic('note')}</span><span class="txt"><b>${esc(n.title)}</b><small>${esc(n.preview || '')}</small></span><time>${n.stamp}</time>
          </div>`).join('')}</div>`;
    }

    docHTML(n) {
      if (n.doc === 'sync') {
        return `<h5>Agenda</h5><ul><li>Q4 priorities</li><li>Hiring update from Matt</li><li>Launch date with Simon</li></ul>
          <p><br></p><p>Draft lives in <code>launch-plan.md</code>.</p>`;
      }
      return `<p>${esc(n.preview || '')}</p>`;
    }

    pageHTML() {
      const n = this.s.notes.find((x) => x.id === this.s.page);
      const B = (lbl, g) => `<button class="dk-tool" aria-label="${lbl}">${g}</button>`;
      const rule = '<span class="dk-div"></span>';
      return `<div class="dk-scroll dk-page">
          <div class="dk-head">
            <input class="dk-title" value="${esc(n.title)}" aria-label="Note title" data-title="${n.id}" ${this.o.interactive ? '' : 'tabindex="-1"'}>
            <div class="dk-date">Monday, Oct 12</div>
          </div>
          <div class="ot-doc" ${this.o.interactive ? 'contenteditable="true"' : ''} spellcheck="false">${this.docHTML(n)}</div>
        </div>
        <div class="dk-foot" aria-hidden="true"></div>
        <div class="dk-bar">
          <button class="dk-round" data-act="back" aria-label="Back">${ic('chevL')}</button>
          <div class="dk-dock dk-fmt">
            ${B('Text style', '<b class="aa">Aa</b>')}${rule}
            ${B('Bulleted list', ic('list'))}${B('Numbered list', ic('listOrdered'))}${B('Checklist', ic('listChecks'))}${rule}
            ${B('Bold, italic, underline', ic('type'))}${B('Link', ic('link'))}${rule}
            ${B('Inline code', ic('code'))}${B('Quote', ic('quote'))}${B('Code block', ic('braces'))}
          </div>
          <button class="dk-round" aria-label="Export">${ic('download')}</button>
        </div>`;
    }

    afterRender() {
      const f = this.stack.querySelector('.ot-field');
      if (f) this.syncField();
      const sc = this.stack.querySelector('.scroller');
      if (sc) sc.classList.toggle('fits', sc.scrollWidth <= sc.clientWidth + 1);
      const doc = this.stack.querySelector('.ot-doc');
      if (doc) this.countWords(doc);
      if (this.o.interactive && this.wantFocus) {
        const w = this.wantFocus; this.wantFocus = null;
        const el = this.stack.querySelector(w);
        if (el) el.focus({ preventScroll: true });
      }
      if (this.o.interactive && this.s.focus >= 0 && document.activeElement !== this.notch && !this.stack.contains(document.activeElement)) {
        this.notch.focus({ preventScroll: true });
      }
      if (this.menuOpen) this.positionMenu();
    }

    countWords(doc) {
      const n = (doc.innerText.match(/\S+/g) || []).length;
      const wc = this.stack.querySelector('.wc');
      if (wc) wc.textContent = `${n} word${n === 1 ? '' : 's'}`;
    }

    /* ---------- draft field ---------- */
    get input() { return this.stack.querySelector('.ot-field input'); }
    focusField() {
      this.s.focus = -1;
      this.stack.querySelectorAll('.ot-row.focus, .ot-note.focus').forEach((r) => r.classList.remove('focus'));
      const i = this.input;
      if (i) i.focus({ preventScroll: true });
    }
    syncField() {
      const f = this.stack.querySelector('.ot-field');
      const input = f.querySelector('input');
      const ed = f.querySelector('.ed');
      const mirror = f.querySelector('.mirror');
      const v = input.value;
      this.draft = v;
      ed.classList.toggle('has-text', !!v);
      const hit = null;
      mirror.innerHTML = hit ? esc(v.slice(0, hit.start)) + '<mark>' + esc(v.slice(hit.start, hit.end)) + '</mark>' + esc(v.slice(hit.end)) : esc(v);
      mirror.scrollLeft = input.scrollLeft;
      f.classList.toggle('has-date', !!hit);
      f.querySelector('.date').textContent = hit ? '→ ' + hit.label : '';
      const real = document.activeElement === input;
      f.classList.toggle('is-focus', real || !!this.fakeFocus);
      f.classList.toggle('fake', !real && !!this.fakeFocus);
      const stream = this.stack.querySelector('.ot-stream');
      if (stream) stream.classList.toggle('dim', !!v);
    }
    commit() {
      const v = (this.draft || '').trim();
      if (!v) return;
      if (this.isNotes) {
        const n = { id: id(), title: v.length > 42 ? v.slice(0, 40).trim() + '…' : v, preview: v.length > 42 ? v : '', stamp: 'just now', landing: true };
        this.s.notes.unshift(n);
        this.fresh.add(n.id);
        setTimeout(() => { n.landing = false; const el = this.stack.querySelector(`[data-notei="${n.id}"]`); if (el) el.classList.remove('landing'); }, 1600);
      } else {
        const hit = null;
        let title = hit ? (v.slice(0, hit.start) + v.slice(hit.end)).replace(/\s{2,}/g, ' ').trim() : v;
        if (!title) title = v;
        const sp = this.space();
        const t = todo(title);
        sp.items.unshift(t);
        this.fresh.add(t.id);
      }
      this.draft = '';
      this.wantFocus = '.ot-field input';
      this.render();
    }
    cycle(dir) {
      const order = ['notes', ...this.s.spaces.map((x) => x.id)];
      let k = order.indexOf(this.s.active) + dir;
      k = (k + order.length) % order.length;
      this.switchTo(order[k], true);
    }
    switchTo(spaceId, keepField) {
      if (this.s.active === spaceId && this.s.view === 'list') return;
      const hadFocus = keepField && document.activeElement === this.input;
      const wasNotes = this.isNotes;
      if (!wasNotes) this.lastSpace = this.s.active;
      this.s.active = spaceId;
      this.s.view = 'list';
      this.s.openRow = null;
      this.s.focus = -1;
      if (wasNotes !== this.isNotes) this.draft = '';
      this.render();
      const list = this.stack.querySelector('.ot-list, .ot-stream');
      if (list) list.classList.add('swap-in');
      if (hadFocus || keepField) this.focusField();

    }

    /* ---------- to-dos ---------- */
    find(tid) { for (const sp of this.s.spaces) { const t = sp.items.find((x) => x.id === tid); if (t) return { sp, t }; } return {}; }
    complete(tid) {
      const { sp, t } = this.find(tid);
      if (!t || t.leaving) return;
      t.done = true; t.leaving = true;
      const row = this.stack.querySelector(`[data-row="${tid}"]`);
      if (row) {
        row.classList.add('done');
        row.querySelector('.ot-cb').classList.add('on');
      }
      const pill = this.stack.querySelector(`.ot-pill[data-space="${sp.id}"] em`);
      if (pill) pill.textContent = this.remaining(sp);
      setTimeout(() => {
        if (row) { row.style.maxHeight = row.offsetHeight + 'px'; void row.offsetHeight; row.classList.add('leave'); }
        setTimeout(() => {
          if (row) { row.style.maxHeight = '0px'; row.style.minHeight = '0px'; row.style.paddingTop = '0px'; row.style.paddingBottom = '0px'; row.style.marginBottom = '-6px'; row.style.overflow = 'hidden'; }
        }, 120);
        setTimeout(() => {
          sp.items = sp.items.filter((x) => x.id !== tid);
          const now = new Date();
          this.s.completed.push({ title: t.title, time: now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) });
          if (this.s.openRow === tid) this.s.openRow = null;
          const len = sp.items.length;
          if (this.s.focus >= len) this.s.focus = len - 1;
          this.render();
        }, 460);
      }, 350);
    }
    toggleOpen(tid) {
      this.s.openRow = this.s.openRow === tid ? null : tid;
      this.render();
    }

    /* ---------- menu ---------- */
    toggleMenu() {
      if (this.menuOpen) return this.closeMenu();
      this.menuOpen = true;
      if (!this.menu) {
        this.menu = document.createElement('div');
        this.menu.className = 'ot-menu';
        this.menu.innerHTML = `
          <button class="mi">${ic('chart')}<b style="font-weight:500">Insights</b><span class="k"><b>⌘</b><b>I</b></span></button><hr>
          <button class="mi">${ic('sliders')}Preferences<span class="k"><b>⌘</b><b>,</b></span></button>
          <button class="mi">${ic('keyboard')}Keyboard shortcuts<span class="k"><b>?</b></span></button>
          <button class="mi">${ic('folder')}Notes folder<span class="d">Otto</span></button><hr>
          <button class="mi">${ic('power')}Quit Otto<span class="k"><b>⌘</b><b>Q</b></span></button>`;
        this.menu.addEventListener('click', () => this.closeMenu());
        this.host.appendChild(this.menu);
      }
      this.positionMenu();
      requestAnimationFrame(() => this.menu.classList.add('open'));
      const g = this.stack.querySelector('.ot-gear'); if (g) g.classList.add('open');
    }
    positionMenu() {
      const g = this.stack.querySelector('.ot-gear');
      if (!g || !this.menu) return;
      const hr = this.host.getBoundingClientRect(), gr = g.getBoundingClientRect();
      this.menu.style.top = (gr.top - hr.top - 8 - (this.menu.offsetHeight || 230)) + 'px';
      this.menu.style.left = (gr.right - hr.left - 276) + 'px';
    }
    closeMenu() {
      if (!this.menuOpen) return;
      this.menuOpen = false;
      if (this.menu) this.menu.classList.remove('open');
      const g = this.stack.querySelector('.ot-gear'); if (g) g.classList.remove('open');
    }

    /* ---------- events ---------- */
    wire() {
      const n = this.notch;
      let hoverTimer;
      n.addEventListener('mouseenter', () => {
        if (this.state !== 'idle') return;
        this.setState('hover');
        hoverTimer = setTimeout(() => this.open(false), 260);
      });
      n.addEventListener('mouseleave', () => { clearTimeout(hoverTimer); if (this.state === 'hover') this.setState('idle'); });
      n.addEventListener('click', (e) => {
        if (this.state !== 'open') { clearTimeout(hoverTimer); this.open(true); return; }
        this.onClick(e);
      });
      this.host.addEventListener('input', (e) => {
        if (e.target.matches('.ot-field input')) { this.interacted(); this.syncField(); }
        if (e.target.matches('[data-note]')) { const { t } = this.find(e.target.dataset.note); if (t) t.note = e.target.value; }
        if (e.target.matches('[data-title]')) { const nn = this.s.notes.find((x) => x.id === e.target.dataset.title); if (nn) nn.title = e.target.value; }
        if (e.target.closest('.ot-doc')) this.countWords(e.target.closest('.ot-doc'));
      });
      this.host.addEventListener('scroll', (e) => { if (e.target.matches && e.target.matches('.ot-field input')) this.syncField(); }, true);
      this.host.addEventListener('focusin', (e) => { if (e.target.matches('.ot-field input')) { this.s.focus = -1; this.syncField(); } });
      this.host.addEventListener('focusout', (e) => { if (e.target.matches('.ot-field input')) setTimeout(() => { const f = this.stack.querySelector('.ot-field'); if (f) this.syncField(); }, 0); });
      this.host.addEventListener('keydown', (e) => this.onKey(e));
      this.host.addEventListener('pointerdown', () => this.interacted());
      document.addEventListener('pointerdown', (e) => { if (this.menuOpen && !this.menu.contains(e.target) && !e.target.closest('.ot-gear')) this.closeMenu(); });
      window.addEventListener('resize', () => { if (this.state === 'open') this.notch.style.setProperty('--w', this.openWidth() + 'px'); });
    }
    interacted() { this.touched = true; if (this.onInteract) this.onInteract(); }

    onClick(e) {
      const el = (sel) => e.target.closest(sel);
      let x;
      if ((x = el('[data-check]'))) { e.stopPropagation(); return this.complete(x.dataset.check); }
      if ((x = el('[data-step]'))) {
        const [tid, k] = x.dataset.step.split(':');
        const { t } = this.find(tid); t.steps[+k].done = !t.steps[+k].done; return this.render();
      }
      if ((x = el('[data-open]'))) return this.toggleOpen(x.dataset.open);
      if ((x = el('[data-space]'))) return this.switchTo(x.dataset.space, false);
      if ((x = el('[data-act]'))) {
        const a = x.dataset.act;
        if (a === 'gear') return this.o.simple ? undefined : this.toggleMenu();
        if (a === 'completed') { this.s.completedOpen = !this.s.completedOpen; return this.render(); }
        if (a === 'new') {
          const used = new Set(this.s.spaces.map((x) => x.tint));
          const tint = PALETTE.find((k) => !used.has(k)) || PALETTE[this.s.spaces.length % PALETTE.length];
          const sp = { id: id(), name: 'New space', tint, items: [] };
          this.s.spaces.push(sp); this.s.active = sp.id; this.render(); this.focusField(); return;
        }
        if (a === 'back') { this.s.view = 'list'; this.s.page = null; return this.render(); }
        if (a === 'kind') return;
      }
      if ((x = el('[data-fmt]'))) { e.preventDefault(); document.execCommand(x.dataset.fmt === 'formatBlock' ? 'formatBlock' : x.dataset.fmt, false, x.dataset.fmt === 'formatBlock' ? 'h5' : null); return; }
      if ((x = el('[data-notei]'))) { this.s.view = 'page'; this.s.page = x.dataset.notei; this.s.focus = -1; return this.render(); }
      if (el('input, [contenteditable], .ot-field')) {
        if (el('.ot-field') && !el('input')) this.focusField();
        return;
      }
      if ((x = el('[data-row]'))) return this.toggleOpen(x.dataset.row);
    }

    onKey(e) {
      const s = this.s;
      const t = e.target;
      if (this.state !== 'open') return;
      if (t.matches('.namer')) {
        if (e.key === 'Enter') {
          const name = t.value.trim();
          this.naming = false;
          if (name) {
            const tint = PALETTE[this.s.spaces.length % PALETTE.length];
            const sp = { id: id(), name, tint, items: [] };
            this.s.spaces.push(sp);
            this.s.active = sp.id;
          }
          this.render(); this.focusField();
        } else if (e.key === 'Escape') { this.naming = false; this.render(); }
        return;
      }
      if (t.matches('[data-newstep]')) {
        if (e.key === 'Enter' && t.value.trim()) {
          const { t: item } = this.find(t.dataset.newstep);
          item.steps.push({ t: t.value.trim(), done: false });
          this.wantFocus = `[data-newstep="${item.id}"]`;
          this.render();
        } else if (e.key === 'Escape') { s.openRow = null; this.render(); this.notch.focus(); }
        return;
      }
      if (t.matches('[data-note], [data-title]')) { if (e.key === 'Enter' || e.key === 'Escape') { t.blur(); this.notch.focus({ preventScroll: true }); } return; }
      if (t.closest('.ot-doc')) {
        if (e.key === 'Escape') { s.view = 'list'; s.page = null; this.render(); this.focusField(); }
        return;
      }
      const inField = t.matches('.ot-field input');
      const cmd = e.metaKey || e.ctrlKey;
      if (e.key === 'Tab') { e.preventDefault(); return this.cycle(e.shiftKey ? -1 : 1); }
      if (s.view === 'page') { if (e.key === 'Escape') { s.view = 'list'; this.render(); } return; }
      const rows = this.isNotes ? s.notes : (this.space() ? this.space().items : []);
      if (inField) {
        if (e.key === 'Enter') { e.preventDefault(); return this.commit(); }
        if (e.key === 'Escape') { e.preventDefault(); if (t.value) { t.value = ''; this.syncField(); } else this.close(); return; }
        if (!t.value && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) { e.preventDefault(); return this.cycle(e.key === 'ArrowLeft' ? -1 : 1); }
        if (e.key === 'ArrowDown' && rows.length) { e.preventDefault(); s.focus = 0; t.blur(); this.notch.focus({ preventScroll: true }); return this.paintFocus(); }
        return;
      }
      // keyboard navigation in the list
      if (e.key === 'ArrowDown') { e.preventDefault(); s.focus = Math.min(rows.length - 1, s.focus + 1); return this.paintFocus(); }
      if (e.key === 'ArrowUp') { e.preventDefault(); if (s.focus <= 0) return this.focusField(); s.focus -= 1; return this.paintFocus(); }
      if (e.key === 'Escape') { e.preventDefault(); if (s.openRow) { s.openRow = null; return this.render(); } return this.focusField(); }
      const cur = rows[s.focus];
      if (!cur) return;
      if (this.isNotes) {
        if (e.key === 'Enter') { s.view = 'page'; s.page = cur.id; this.render(); }
        return;
      }
      if (e.key === ' ' || (e.key === 'Enter' && cmd)) { e.preventDefault(); return this.complete(cur.id); }
      if (e.key === 'Enter' || e.key === 'ArrowRight') { e.preventDefault(); s.openRow = cur.id; return this.render(); }
      if (e.key === 'ArrowLeft') { e.preventDefault(); if (s.openRow) { s.openRow = null; return this.render(); } return this.cycle(-1); }
    }
    paintFocus() {
      this.stack.querySelectorAll('.ot-row, .ot-note').forEach((r, i) => r.classList.toggle('focus', i === this.s.focus));
      this.syncField();
    }

    /* ---------- scripted demo: types a to-do and saves it ---------- */
    async demo(text) {
      const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
      const input = this.input;
      if (!input || this.touched) return;
      this.fakeFocus = true;
      for (const ch of text) {
        if (this.touched) { this.fakeFocus = false; this.syncField(); return; }
        input.value += ch; this.syncField();
        await sleep(55 + Math.random() * 55);
      }
      await sleep(700);
      if (this.touched) { this.fakeFocus = false; return; }
      this.commit();
      this.fakeFocus = false;
      this.syncField();
      if (document.activeElement === this.input && !this.touched) this.input.blur();
    }
  }

  /* ---------------- static previews for the feature cards ---------------- */
  function meetingCardHTML() {
    return `<div class="ot-meet">
      <span class="ic">${MEET}</span>
      <div class="col">
        <div class="r1"><span class="tm">9:30 – 10:30</span><span class="cd">Starting in 2 min</span></div>
        <h6>Weekly product sync</h6>
        <div class="acts">
          <button class="ot-join">Join <kbd>⌘</kbd><kbd>↩</kbd></button>
          <button class="ot-snooze">Snooze 5m</button>
          <span class="ot-avs"><span style="background:#B9D4FF;color:#1F3F7A">S</span><span style="background:#F7C6D9;color:#7A2346">M</span><span style="background:#C9EBC8;color:#1E5A2B">J</span><span class="plus">+2</span></span>
        </div>
      </div></div>`;
  }

  function fit(stage, inner, nativeW, pad = 0) {
    const apply = () => {
      const w = stage.clientWidth;
      if (!w) return;
      const k = Math.min(1, w / nativeW);
      inner.style.width = nativeW + 'px';
      inner.style.transform = `translateX(-50%) scale(${k})`;
      stage.style.height = Math.ceil(inner.offsetHeight * k + pad) + 'px';
    };
    new ResizeObserver(apply).observe(stage);
    new ResizeObserver(apply).observe(inner);
    apply();
  }

  function mountStatic(stage, kind) {
    stage.classList.add('ot-fit');
    const inner = document.createElement('div');
    inner.className = 'ot-fit-inner';
    stage.appendChild(inner);
    const host = document.createElement('div');
    inner.appendChild(host);
    const W = { tasks: 596, notes: 540, meeting: 540, notch: 596 }[kind] || 596;
    const base = { interactive: false, open: true, presence: false, notchH: 0, top: true, openW: W, panelH: { tasks: 400, notch: 360, notes: 340 }[kind] || 0 };
    let o;
    if (kind === 'tasks') {
      o = new Otto(host, Object.assign(base, { state: { openRow: null } }));
      o.render();
    } else if (kind === 'notes') {
      o = new Otto(host, base);
      o.s.active = 'notes'; o.s.view = 'page'; o.s.page = o.s.notes[0].id;
      o.render();
    } else if (kind === 'meeting') {
      // the closed notch counting down, and the card that comes 5 minutes before
      stage.classList.add('ot-meet-stage');
      inner.innerHTML = `<div class="ot-mini"><div class="ot-mini-host"></div></div>
        <div class="ot ot-mc-wrap">${Otto.prototype.meetHTML.call({})}</div>`;
      new Otto(inner.querySelector('.ot-mini-host'), { interactive: false, presence: true, notchW: 185, notchH: 32 });
      inner.querySelector('.ot-mcard').classList.add('show');
      fit(stage, inner, W + 48, 0);
      return null;
    } else if (kind === 'notch') {
      o = new Otto(host, base);
      o.s.completed = [];
      o.render();
    }
    host.style.padding = '0 12px';
    fit(stage, inner, W + 48, kind === 'notch' ? 0 : 22);
    return o;
  }

  function mountFloating(stage) {
    stage.classList.add('ot-fit');
    const inner = document.createElement('div');
    inner.className = 'ot-fit-inner';
    inner.innerHTML = `<div class="ot ot-static" style="--sec:#9CC0FF;padding:0 0 30px">
      <div class="ot-notch" style="--w:213px;--h:38px;--r:12px;margin-bottom:28px"><div class="ot-body"></div></div>
      <div class="ot-float">
        <div class="cap"><span class="dotslot"><i></i></span><span class="ph">Add a to-do…</span><span class="hint">Switch space <span class="k">tab</span></span></div>
        <div class="ot-list">
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title">Send the proposal to Simon</span><span class="gutter"></span></div></div>
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title">Review Matt’s feedback</span><span class="gutter"></span></div></div>
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title">Prep for Monday’s standup</span><span class="gutter"></span></div></div>
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title">Call <span class="dk-chip at">@matt</span></span><span class="gutter"></span></div></div>
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title"><span class="dk-chip img">${ic('image')}Screenshot</span>Fix the pricing table</span><span class="gutter"></span></div></div>
          <div class="ot-row"><div class="line"><span class="ot-cb"></span><span class="title">Book the team offsite <span class="dk-chip date">${ic('calendar')}fri</span></span><span class="gutter"></span></div></div>
        </div>
        <div class="ot-tabs"><span class="ot-pill notes">Notes<em>4</em></span><span class="rule"></span><span class="ot-pill on">Work<em>7</em></span><span class="ot-pill">Personal<em>7</em></span><span class="ot-pill">Side project<em>6</em></span><span class="ot-gear">${ic('gear')}</span></div>
      </div></div>`;
    stage.appendChild(inner);
    fit(stage, inner, 657);
  }

  window.OttoUI = { Otto, mountStatic, mountFloating, parseDate };
})();
