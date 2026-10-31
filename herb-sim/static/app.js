/* Logsperity + HERB simulator — app shell (design §7 screen map).
   Tabs: Today · Log · Reports · Coach · More. Each tab keeps its own navigation stack. */
(function () {
  const { esc, fmt } = W;
  const $ = s => document.querySelector(s);

  const ICONS = {
    today: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>',
    log: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/></svg>',
    reports: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
    coach: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/></svg>',
    more: '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
    mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
    stop: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="7" y="7" width="10" height="10" rx="2"/></svg>',
    prospects: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="10" cy="8" r="4"/><path d="M2 21a8 8 0 0 1 16 0M19 8v6M16 11h6"/></svg>',
    closings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 12l5 5L20 6"/></svg>',
    income: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2v20M17 6H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>',
    expenses: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 2h12v20l-3-2-3 2-3-2-3 2z"/><path d="M9 7h6M9 11h6M9 15h4"/></svg>',
    trips: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 17h14l-2-7H7z"/><circle cx="8" cy="18" r="2"/><circle cx="16" cy="18" r="2"/></svg>',
    activities: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/></svg>',
  };
  const LOG_META = {
    prospects: { name: 'Prospects', color: '#2c5fd6', bg: '#e8eefc' }, closings: { name: 'Closings', color: '#12806a', bg: '#e3f4ef' },
    income: { name: 'Income', color: '#6b4bd8', bg: '#efeafc' }, expenses: { name: 'Expenses', color: '#c2412d', bg: '#fbe9e6' },
    trips: { name: 'Mileage', color: '#c98a12', bg: '#fdf3e1' }, activities: { name: 'Activity', color: '#0f5c4d', bg: '#e6f0ee' },
  };
  const TABS = [['today', 'Today'], ['log', 'Log'], ['reports', 'Reports'], ['coach', 'Coach'], ['more', 'More']];
  const PERIODS = [['ytd', 'Year to date'], ['month', 'This month'], ['last30', 'Last 30 days'], ['q', 'This quarter'], ['year', 'Full year']];

  const App = {
    T: null, today: new Date().toISOString().slice(0, 10), plan: null, account: null, cache: {},
    tab: 'today', stacks: { today: [{ name: 'today' }], log: [{ name: 'log' }], reports: [{ name: 'reports' }], coach: [{ name: 'coach' }], more: [{ name: 'more' }] },
    reviewCount: 0, herbDraft: null, herbDialog: null, herbVoiceTurn: false,
  };
  window.App = App;

  // ---------- API ----------
  App.api = async function (path, { method = 'GET', body } = {}) {
    const res = await fetch(path, { method, headers: body ? { 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined, cache: 'no-store' });
    let data = null; try { data = await res.json(); } catch (e) { /* empty */ }
    if (!res.ok) throw new Error((data && data.error) || res.statusText);
    return data;
  };
  const periodParam = key => {
    const d = App.today;
    if (key === 'q') return `q:${d.slice(0, 4)}-${Math.floor((+d.slice(5, 7) - 1) / 3) + 1}`;
    if (key === 'year') return `year:${d.slice(0, 4)}`;
    return key;
  };

  // ---------- navigation ----------
  App.view = () => { const s = App.stacks[App.tab]; return s[s.length - 1]; };
  App.push = (name, params = {}) => { App.stacks[App.tab].push({ name, params }); App.render(); $('#screen').scrollTop = 0; };
  App.pop = () => { const s = App.stacks[App.tab]; if (s.length > 1) s.pop(); const v = App.view(); delete v.data; App.render(); };
  App.go = (tab, name, params) => {
    App.tab = tab;
    App.stacks[tab] = [App.stacks[tab][0]];
    delete App.stacks[tab][0].data;
    if (name && name !== App.stacks[tab][0].name) App.stacks[tab].push({ name, params: params || {} });
    App.render(); $('#screen').scrollTop = 0;
  };

  App.toast = function (msg) {
    const t = $('#toast'); t.textContent = msg; t.classList.add('show');
    clearTimeout(App._toast); App._toast = setTimeout(() => t.classList.remove('show'), 2600);
  };

  App.render = async function ({ keepScroll = false, focus = null } = {}) {
    renderTabbar();
    const v = App.view(), def = VIEWS[v.name];
    const scr = $('#screen'), top = scr.scrollTop;
    if (!def) { scr.innerHTML = `<div class="empty">Unknown screen ${esc(v.name)}</div>`; return; }
    if (def.load && v.data === undefined) {
      if (!keepScroll) scr.innerHTML = titlebar(v, def) + '<div class="loading">Loading…</div>';
      // overlapping renders of the same screen share one request
      v._loading = v._loading || Promise.resolve(def.load(v.params || {}, v)).finally(() => { v._loading = null; });
      try { const d = await v._loading; if (v.data === undefined) v.data = d; }
      catch (e) { if (App.view() === v) scr.innerHTML = titlebar(v, def) + `<div class="warn">Couldn't load: ${esc(e.message)}. Is the server running?</div>`; return; }
      if (App.view() !== v) return;     // user navigated away while loading
    }
    scr.innerHTML = titlebar(v, def) + def.html(v.data, v.params || {}, v);
    if (keepScroll) scr.scrollTop = top;
    if (focus) { const el = scr.querySelector(`[data-k="${focus.k}"][data-i="${focus.i || 0}"]`); if (el) { el.focus(); try { const n = el.value.length; el.setSelectionRange(n, n); } catch (e) {} } }
  };

  function titlebar(v, def) {
    const stack = App.stacks[App.tab];
    if (stack.length === 1 || def.noBar) return '';
    const title = typeof def.title === 'function' ? def.title(v.params || {}, v.data) : def.title || '';
    const prev = stack[stack.length - 2], prevTitle = VIEWS[prev.name] ? (typeof VIEWS[prev.name].title === 'function' ? VIEWS[prev.name].title(prev.params || {}, prev.data) : VIEWS[prev.name].title) : 'Back';
    const right = def.right ? def.right(v.params || {}, v.data) : '';
    return `<div class="titlebar"><button class="back" data-act="back">‹ ${esc(String(prevTitle || 'Back').slice(0, 14))}</button><span class="ttl">${esc(title)}</span><span>${right}</span></div>`;
  }

  function renderTabbar() {
    $('#tabbar').innerHTML = TABS.map(([id, name]) => `<button class="tab ${App.tab === id ? 'on' : ''}" data-act="tab" data-tab="${id}">${ICONS[id]}${name}
      ${id === 'today' && App.reviewCount ? `<span class="badge">${App.reviewCount}</span>` : ''}</button>`).join('');
  }

  App.refreshBadges = async function () {
    try { const r = await App.api('/api/review'); App.reviewCount = r.length; renderTabbar(); } catch (e) { /* ignore */ }
    for (const t of Object.keys(App.stacks)) App.stacks[t].forEach(v => { if (v !== App.view()) delete v.data; });
  };

  // ---------- helpers ----------
  const initials = n => (n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(x => x[0].toUpperCase()).join('') || '?';
  const avColor = n => ['#c2412d', '#2c5fd6', '#6b4bd8', '#12806a', '#c98a12', '#0f5c4d'][[...(n || '')].reduce((a, c) => a + c.charCodeAt(0), 0) % 6];
  const chipCls = c => ({ late: 'c-red', overdue: 'c-red', new: 'c-red', today: 'c-gold', soon: 'c-blue', hot: 'c-red', red_hot: 'c-red', medium: 'c-gold', cold: 'c-blue', no_go: 'c-grey' }[c] || 'c-grey');
  const money0 = v => fmt(Number(v || 0), 'money0');
  const shortDate = iso => iso ? new Date(iso + 'T12:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : '';
  const nameOf = r => r.name || r.prospect_name || r.prospectName || [r.first_names, r.last_name].filter(Boolean).join(' ') || r.last_name || '';
  const strengthOf = id => (App.T.picklists.strength || []).map(x => typeof x === 'string' ? { id: x, name: x } : x).find(s => s.id === id);
  const catName = id => ((App.T.categories.find(c => c.id === id) || {}).name) || '';
  const actName = id => ((App.T.activities.find(c => c.id === id) || {}).name) || '';
  const capChip = r => r.capture && r.capture !== 'manual' ? `<span class="auto">${esc(r.capture)}</span>` : '';

  // ---------- views ----------
  const VIEWS = {};

  VIEWS.today = {
    load: () => App.api('/api/today'),
    html: d => {
      const kpis = (d.kpis || []).slice(0, 6);
      return `<div class="sub">${esc(new Date(App.today + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' }))}</div>
      <h1>${esc(d.greeting || 'Good morning')}</h1>
      <button class="ask" data-act="herb-open"><span class="mic">${ICONS.mic}</span>
        <span><span style="font-weight:700;font-size:15px;display:block">Ask HERB</span><span style="font-size:12.5px;opacity:.85">“What should I focus on this week?”</span></span></button>
      <div class="kpis ${kpis.length % 2 === 0 && kpis.length % 3 !== 0 ? 'k2' : ''}">${kpis.map(k => `<div class="kpi" data-act="kpi" data-k="${esc(k.key)}"><b>${esc(k.display ?? fmt(k.value))}</b><span>${esc(k.label)}${k.sub ? ' · ' + esc(k.sub) : ''}</span></div>`).join('')}</div>
      ${d.reviewCount ? `<button class="card mt12 row" style="width:100%;text-align:left" data-act="review"><span class="av" style="background:var(--violet)">${d.reviewCount}</span>
        <span class="t" style="flex:1"><b style="display:block">HERB logged things for you</b><span class="small muted">Review ${d.reviewCount} item${d.reviewCount > 1 ? 's' : ''} — about a minute</span></span><span class="chev">›</span></button>` : ''}
      ${d.focus && d.focus.length ? `<h2>This week's focus <small data-act="herb-ask" data-q="What should I focus on this week?">Ask why</small></h2>
        <div class="card flush">${d.focus.map((f, i) => `<div class="li" data-act="herb-ask" data-q="${esc(f.title)}"><span class="av" style="background:var(--brand2)">${i + 1}</span><div class="t"><b>${esc(f.title)}</b><span>${esc(f.why || '')}</span></div>${f.value ? `<span class="chip c-green">${esc(f.value)}</span>` : ''}</div>`).join('')}</div>` : ''}
      <h2>Follow-ups due <small>${(d.followUps || []).length}</small></h2>
      <div class="card flush">${(d.followUps || []).length ? d.followUps.slice(0, 8).map(f => `<div class="li" data-act="${f.prospectId ? 'open-prospect' : 'noop'}" data-id="${esc(f.prospectId || '')}">
          <div class="av" style="background:${avColor(f.name)}">${esc(initials(f.name))}</div>
          <div class="t"><b>${esc(f.name)}</b><span>${esc(f.reason || '')}</span></div><span class="chip ${chipCls(f.chip)}">${esc(f.dueLabel || f.chip || shortDate(f.due))}</span></div>`).join('')
        : '<div class="empty">Nothing due. Nice.</div>'}</div>
      ${d.insight ? `<h2>HERB noticed</h2><div class="insight ${esc(d.insight.level || '')}"><div class="k">${esc(d.insight.title || 'Herb noticed')}</div>${esc(d.insight.text)}</div>` : ''}
      <h2>Quick add</h2>
      <div class="qa">${Object.entries(LOG_META).map(([k, m]) => `<button data-act="new" data-log="${k}"><i style="background:${m.bg};color:${m.color}">${ICONS[k]}</i>${m.name === 'Prospects' ? 'Prospect' : m.name === 'Closings' ? 'Closing' : m.name}</button>`).join('')}</div>
      <div class="note center mt16">Logsperity Index ${d.index ? esc(Math.round(d.index.value)) : '—'} · synthetic data</div>`;
    },
  };

  VIEWS.log = {
    load: async () => {
      const out = {};
      await Promise.all(Object.keys(LOG_META).map(async k => { try { out[k] = await App.api(`/api/${k}?period=ytd&limit=1`); } catch (e) { out[k] = null; } }));
      return out;
    },
    html: d => `<h1>Log</h1><div class="sub">Six logs · year to date</div>
      <div class="card flush mt12">${Object.entries(LOG_META).map(([k, m]) => {
        const t = (d[k] && d[k].totals) || {};
        const extra = k === 'closings' ? money0(t.income) + ' income' : k === 'income' ? money0(t.amount) : k === 'expenses' ? money0(t.amount)
          : k === 'trips' ? fmt(t.miles || 0, 'miles') : k === 'activities' ? fmt((t.hours ?? (t.minutes || 0) / 60), 'hours') : (t.conversion != null ? fmt(t.conversion, 'pct') + ' convert' : '');
        return `<div class="li" data-act="open-log" data-log="${k}"><span class="qa" style="display:block"><i style="background:${m.bg};color:${m.color};margin:0">${ICONS[k]}</i></span>
          <div class="t"><b>${m.name}</b><span>${esc(t.count ?? 0)} entries${extra ? ' · ' + esc(extra) : ''}</span></div>
          <button class="chip c-green" data-act="new" data-log="${k}">+ Add</button><span class="chev">›</span></div>`; }).join('')}</div>
      <h2>Review queue <small data-act="review">${App.reviewCount} waiting</small></h2>
      <div class="note">Entries HERB captured on its own (GPS trips, bank charges, calendar meetings, voice) wait in the Review queue until you confirm them.</div>`,
  };

  VIEWS.logList = {
    title: p => LOG_META[p.log].name,
    right: p => `<button class="link" data-act="new" data-log="${p.log}" style="font-size:22px;line-height:1">+</button>`,
    load: (p, v) => App.api(`/api/${p.log}?period=${periodParam(v.period || 'ytd')}&limit=400${v.q ? '&q=' + encodeURIComponent(v.q) : ''}`),
    html: (d, p, v) => {
      const rows = d.rows || [], t = d.totals || {};
      const per = v.period || 'ytd';
      const line = r => {
        switch (p.log) {
          case 'prospects': { const s = strengthOf(r.strength); return [nameOf(r), `${shortDate(r.date)} · ${r.categoryName || catName(r.category_id)} · ${r.sourceName || ''}`, s ? `<span class="chip" style="background:${s.color}22;color:${s.color}">${esc(s.name)}</span>` : '', r.closing_id || r.closed ? '<span class="chip c-green">Closed</span>' : ''] }
          case 'closings': return [nameOf(r) || 'Closing', `${shortDate(r.date)} · ${r.categoryName || catName(r.category_id)} · ${r.sourceName || ''}`, `<span class="amt">${money0(r.income)}<br><span class="small muted">${money0(r.transaction_size)}</span></span>`];
          case 'income': return [nameOf(r) || r.typeName || r.type || 'Income', `${shortDate(r.date)} · ${r.mode === 'transaction' ? 'Transaction' : r.mode === 'batch' ? `Batch of ${r.transaction_count}` : (r.typeName || r.type || '')}${r.payer ? ' · ' + r.payer : ''}`, `<span class="amt">${money0(r.amount)}</span>`];
          case 'expenses': return [r.vendor, `${shortDate(r.date)} · ${r.categoryName || ''}${r.irs ? ' · ' + r.irs : ''}${!r.has_receipt && r.amount >= 75 ? ' · ⚠ no receipt' : ''}`, `<span class="amt">${fmt(r.amount, 'money')}</span>`];
          case 'trips': return [r.destination || 'Trip', `${shortDate(r.date)} · ${r.reason || ''}${r.is_business ? '' : ' · personal'}`, `<span class="amt">${fmt(r.miles ?? r.gps_miles ?? 0, 'num1')} mi</span>`];
          case 'activities': return [r.activityName || actName(r.activity_id), `${shortDate(r.date)} · ${r.pillarName || r.pillar}${r.sourceName ? ' · ' + r.sourceName : ''}`, `<span class="amt">${fmt((r.minutes || 0) / 60, 'hours')}</span>`];
        }
        return [JSON.stringify(r).slice(0, 40), '', ''];
      };
      const sum = p.log === 'prospects' ? `${t.count || 0} prospects${t.conversion != null ? ' · ' + fmt(t.conversion, 'pct') + ' converted' : ''}`
        : p.log === 'closings' ? `${t.count || 0} closings · ${money0(t.volume ?? t.transaction_size)} volume · ${money0(t.income)} income`
        : p.log === 'income' || p.log === 'expenses' ? `${t.count || 0} entries · ${money0(t.amount)}`
        : p.log === 'trips' ? `${t.count || 0} trips · ${fmt(t.miles || 0, 'miles')}${t.deduction != null ? ' · ' + money0(t.deduction) + ' deduction' : ''}`
        : `${t.count || 0} entries · ${fmt(t.hours ?? (t.minutes || 0) / 60, 'hours')}`;
      return `<div class="rep-period">${PERIODS.map(([k, n]) => `<button class="${per === k ? 'on' : ''}" data-act="list-period" data-v="${k}">${n}</button>`).join('')}</div>
        <input class="search" placeholder="Search ${esc(LOG_META[p.log].name.toLowerCase())}" value="${esc(v.q || '')}" data-search="1">
        <div class="sub" style="margin:0 2px 8px">${esc(sum)}</div>
        <div class="card flush">${rows.length ? rows.map(r => { const [a, b, c, e] = line(r);
          return `<div class="li" data-act="edit-row" data-log="${p.log}" data-id="${r.id}"><div class="t"><b>${esc(a)}${capChip(r)}${r.reviewed === 0 ? ' <span class="chip c-violet">review</span>' : ''}</b><span>${esc(b)}</span></div>${c || ''}${e || ''}</div>`; }).join('')
          : '<div class="empty">No entries in this period.</div>'}</div>`;
    },
  };

  VIEWS.form = {
    title: p => (F.state && F.state.id ? 'Edit ' : 'New ') + (F.LOGS[p.log] ? F.LOGS[p.log].title : ''),
    html: () => F.html(),
  };

  VIEWS.review = {
    title: 'Review',
    load: () => App.api('/api/review'),
    html: items => {
      if (!items.length) return `<div class="ok">All caught up — nothing waiting for review.</div>`;
      return `<div class="sub" style="margin-bottom:8px">HERB logged these on its own. Confirm, fix or dismiss each one.</div>
        ${items.map(it => `<div class="card"><div class="row"><span class="chip c-violet">${esc(it.capture)}</span><span class="small muted">${esc(LOG_META[it.log] ? LOG_META[it.log].name : it.log)}</span></div>
          <div style="font-weight:700;margin-top:6px">${esc(it.title)}</div><div class="small muted">${esc(it.subtitle || '')}</div>
          ${it.question ? `<div class="mt8" style="font-size:14px">${esc(it.question)}</div>` : ''}
          ${it.suggestions && Object.keys(it.suggestions).length ? `<div class="mt8">${Object.entries(it.suggestions).map(([k, val]) => `<div class="field"><span>${esc(k)}</span><b>${esc(val)}</b></div>`).join('')}</div>` : ''}
          <div class="btns"><button class="btn primary small" style="flex:1" data-act="review-ok" data-id="${esc(it.id)}">Confirm</button>
            <button class="btn ghost small" style="flex:1" data-act="review-edit" data-id="${esc(it.id)}">Edit</button>
            <button class="btn danger small" style="flex:1" data-act="review-no" data-id="${esc(it.id)}">${it.log === 'trips' ? 'Personal' : 'Dismiss'}</button></div></div>`).join('')}
        <button class="btn ghost mt12" data-act="review-all">Confirm all ${items.length}</button>`;
    },
  };

  VIEWS.reports = {
    load: () => App.api('/api/reports'),
    html: (menu, p, v) => {
      const groups = menu.groups || [];
      const g = groups.find(x => x.id === (v.group || 'detailed')) || groups[0] || { items: [] };
      v.sel = v.sel || new Set();
      return `<h1>Reports</h1><div class="sub">View one, or check several to print or email</div>
        <button class="card mt12 row" style="width:100%;text-align:left" data-act="annual" data-v="complete">
          <span class="av" style="background:var(--rep-blue)">AR</span><span class="t" style="flex:1"><b style="display:block">${esc(App.today.slice(0, 4))} Annual Report</b><span class="small muted">Complete · Streamlined · YTD</span></span><span class="chev">›</span></button>
        <div class="seg mt12">${groups.map(x => `<button class="${x.id === g.id ? 'on' : ''}" data-act="rep-group" data-v="${esc(x.id)}">${esc(x.title)}</button>`).join('')}</div>
        <div class="card flush mt8">${g.items.map(it => `<div class="menu-item"><input type="checkbox" data-sel="${esc(it.key)}" ${v.sel.has(it.key) ? 'checked' : ''}>
          <button class="go" data-act="open-report" data-key="${esc(it.key)}">${esc(it.title)}</button><span class="chev">›</span></div>`).join('')}</div>
        <div class="btns"><button class="btn ghost" data-act="print-sel">Print${v.sel.size ? ' (' + v.sel.size + ')' : ''}</button><button class="btn ghost" data-act="email-sel">Email${v.sel.size ? ' (' + v.sel.size + ')' : ''}</button></div>
        <div class="note center mt12">On a phone the menu is four pages (Logs · Quick Stats · Detailed · Monthly & YTD); on iPad and Mac it's one page.</div>`;
    },
  };

  VIEWS.report = {
    title: (p, d) => (d && d.title) || 'Report',
    right: p => `<button class="link" data-act="report-more" data-key="${esc(p.key)}">⋯</button>`,
    load: (p, v) => App.api(`/api/reports/${encodeURIComponent(p.key)}?period=${periodParam(v.period || p.period || 'ytd')}`),
    html: (d, p, v) => `<div class="rep-period">${PERIODS.map(([k, n]) => `<button class="${(v.period || p.period || 'ytd') === k ? 'on' : ''}" data-act="rep-period" data-v="${k}">${n}</button>`).join('')}</div>
      <div class="sub" style="margin:0 2px 8px">${esc((d.period && d.period.label) || '')}</div>
      ${W.render(d.widgets)}
      <div class="btns"><button class="btn ghost" data-act="report-print">Print</button><button class="btn ghost" data-act="report-email">Email</button><button class="btn primary" data-act="report-explain">Explain</button></div>`,
  };

  VIEWS.annual = {
    title: 'Annual Report',
    load: p => App.api(`/api/annual-report?version=${p.version || 'complete'}`),
    html: (d, p) => `<div class="seg">${[['complete', 'Complete'], ['streamlined', 'Streamlined'], ['ytd', 'YTD']].map(([k, n]) => `<button class="${(p.version || 'complete') === k ? 'on' : ''}" data-act="annual-ver" data-v="${k}">${n}</button>`).join('')}</div>
      <div class="sub mt8">${esc(d.title || '')} · ${esc((d.period && d.period.label) || '')}</div>
      ${(d.pages || []).map((pg, i) => `<div class="page-title">${i + 1}. ${esc(pg.title)}</div>${W.render(pg.widgets)}`).join('')}
      <div class="btns"><button class="btn ghost" data-act="annual-print">Print / PDF</button><button class="btn ghost" data-act="annual-email">Email</button></div>`,
  };

  VIEWS.coach = {
    load: () => App.api('/api/coach'),
    html: d => {
      const ix = d.index || {};
      return `<h1>Coach</h1><div class="sub">Your numbers, what they mean, what to do next</div>
        <div class="mt12">${W.render([{ type: 'index', title: 'Logsperity Index', value: ix.value, display: ix.display, label: ix.label, drivers: ix.drivers }])}</div>
        ${ix.trend && ix.trend.length ? W.render([{ type: 'bar', title: 'Index by month', items: ix.trend.map(t => ({ label: t.month, value: t.value, display: String(Math.round(t.value)) })) }]) : ''}
        <button class="btn primary" data-act="checkin">Start weekly check-in</button>
        ${d.focus ? `<h2>This week's focus</h2><div class="card flush">${(d.focus.items || []).map((f, i) => `<div class="li"><span class="av" style="background:var(--brand2)">${i + 1}</span><div class="t"><b>${esc(f.title)}</b><span>${esc(f.why || '')}</span></div></div>`).join('')}
          ${d.focus.drop ? `<div class="li"><span class="av" style="background:var(--red)">✕</span><div class="t"><b>Drop: ${esc(d.focus.drop.title || d.focus.drop)}</b><span>${esc(d.focus.drop.why || '')}</span></div></div>` : ''}</div>` : ''}
        <h2>Business plan pace</h2>${W.render([{ type: 'progress', title: 'Year to date vs plan', items: (d.plan && d.plan.items || []).map(it => ({ ...it, displayActual: it.display ? it.display.actual : undefined, displayProjected: it.display ? it.display.projected : undefined, displayGoal: it.display ? it.display.goal : undefined, pct: it.pacePct })) }])}
        <h2>HERB noticed <small>${(d.insights || []).length}</small></h2>
        ${(d.insights || []).map(it => `<div class="insight ${esc(it.level)}"><div class="k">${esc(it.title || it.level)}</div>${esc(it.text)}
          ${it.sample != null ? `<div class="note mt8">Based on ${esc(it.sample)} data points${it.numbers ? ' · ' + esc(typeof it.numbers === 'string' ? it.numbers : Object.entries(it.numbers).map(([k, x]) => `${k}: ${x}`).join(', ')) : ''}</div>` : ''}</div>`).join('') || '<div class="empty">No insights yet.</div>'}
        ${d.lastCheckin ? `<div class="note center mt12">Last check-in: ${esc(d.lastCheckin.date || d.lastCheckin)}</div>` : ''}`;
    },
  };

  VIEWS.more = {
    html: () => `<h1>More</h1>
      <div class="card flush mt12">${[['account', 'Account & subscription'], ['plan', 'Business Plan Set Up'], ['review', `Review queue (${App.reviewCount})`], ['cheat', 'Input Cheat Sheet'],
        ['autopilot', 'HERB Autopilot'], ['help', 'Help'], ['privacy', 'Data & privacy']].map(([k, n]) => `<div class="li" data-act="push" data-v="${k}"><div class="t"><b>${esc(n)}</b></div><span class="chev">›</span></div>`).join('')}</div>
      <h2>Simulator</h2><div class="card flush">
        <div class="li" data-act="reset"><div class="t"><b>Reset synthetic data</b><span>Rebuilds the SQLite database from seed 42</span></div></div>
        <div class="li" data-act="welcome"><div class="t"><b>Show welcome screen</b><span>Join / log in flow</span></div></div></div>
      <div class="note center mt16">Logsperity simulator · design v0.2 · all names and numbers are synthetic</div>`,
  };

  VIEWS.account = { title: 'Account', load: () => App.api('/api/account').then(a => (App.account = a)), html: a => F.accountHtml(a) };
  VIEWS.plan = { title: 'Business Plan', load: () => App.api('/api/plan').then(p => (App.plan = p)), html: p => F.planHtml(p) };

  VIEWS.cheat = {
    title: 'Cheat Sheet',
    html: () => {
      const T = App.T;
      return `<div class="sub">Every prospect, closing, income entry and activity hour is tagged so you can see where business really comes from.</div>
        <div class="card mt12"><div class="field"><span>🏛 Pillar</span><b>One of the four places business comes from</b></div>
        <div class="field"><span>▦ Category</span><b>Who or what the lead is</b></div><div class="field"><span>⑂ Source</span><b>The specific person, company or venue</b></div>
        <div class="field"><span>🏃 Activity</span><b>What you did to produce it</b></div></div>
        ${T.pillars.map(p => `<h2>${esc(p.name)}</h2><div class="card">
          ${T.subPillars.filter(s => s.pillar === p.id).map(s => `<div class="small" style="font-weight:700;margin:4px 0">${s.id !== p.id ? esc(s.name) : ''}</div>
            <div class="small"><b>Categories:</b> ${esc(T.categories.filter(c => c.subPillar === s.id).map(c => c.name).join(', '))}</div>
            <div class="small mt8"><b>Activities:</b> ${esc(T.activities.filter(c => c.subPillar === s.id).map(c => c.name).join(', '))}</div>`).join('<hr style="border:0;border-top:1px solid var(--line);margin:8px 0">')}</div>`).join('')}
        <h2>Logging rules</h2><div class="card">${[
          'Log every inquiry as a prospect, however weak — weak leads show which streams to cut.',
          'A referral from a past client goes under Clients, even if the chain started elsewhere. Use “Originally from” to remember the first source.',
          'Several transactions for one client at once: one Closing, the rest on the Income log.',
          'Repeat clients: the first transaction is a Closing; later ones go on the Income log.',
          'One closing per prospect — it keeps conversion rates honest.',
          'Mileage: the beginning odometer defaults to your last ending reading.'].map((t, i) => `<div class="field"><span>R${i + 1}</span><b style="font-weight:500">${esc(t)}</b></div>`).join('')}</div>`;
    },
  };

  const QUESTION_STYLES = [['quick', 'Quick', 'Only what a record needs: names, amounts, categories, and where each prospect came from.'],
    ['balanced', 'Balanced', 'Also offers address and phone, and asks for the follow-up date.'],
    ['thorough', 'Thorough', 'Also asks for email, lead strength, loan details and meal purpose.']];
  const SKIP_NAMES = { address: 'Address', phone: 'Phone number', email: 'Email', vendor: 'Store name', withWhom: 'Who a meal was with',
    payer: 'Who paid', destination: 'Trip destination', purpose: 'Business purpose', strength: 'Lead strength', loan: 'Loan details' };
  VIEWS.autopilot = {
    title: 'HERB Autopilot',
    load: async () => { const [items, acct] = await Promise.all([App.api('/api/autopilot'), App.api('/api/account')]); return { items, acct }; },
    html: ({ items, acct }) => {
      const qs = acct.herbQuestions || 'balanced', never = acct.herbNeverAsk || [];
      return `<h2>Follow-up questions</h2><div class="card"><div class="small muted">When you leave something out, HERB asks for it — one short question at a time. HERB always asks where a new prospect came from; “I don't know” is fine, and the prospect waits in Review until you fill it in.</div>
        <div class="seg mt8">${QUESTION_STYLES.map(([k, l]) => `<button class="${qs === k ? 'on' : ''}" data-act="hq" data-v="${k}">${l}</button>`).join('')}</div>
        <div class="small mt8">${esc(QUESTION_STYLES.find(s => s[0] === qs)[2])}</div>
        ${never.length ? `<div class="small mt8"><b>HERB stopped asking for:</b> ${never.map(k => esc(SKIP_NAMES[k] || k)).join(', ')} (you skipped ${never.length > 1 ? 'them' : 'it'} 3 times in a row). <a href="#" data-act="hq-reset">Ask again</a></div>` : ''}</div>
      <h2>Automation</h2><div class="sub">How much HERB does on its own. 0 Manual · 1 Suggest · 2 Draft · 3 Auto + review · 4 Autopilot</div>
      ${items.map(it => `<div class="card"><b>${esc(it.label)}</b><div class="small muted">${esc(it.description || '')}</div>
        <div class="seg mt8">${[0, 1, 2, 3, 4].map(l => `<button ${l < it.min || l > it.max ? 'disabled style="opacity:.3"' : ''} class="${it.level === l ? 'on' : ''}" data-act="ap" data-k="${esc(it.key)}" data-v="${l}">${l}</button>`).join('')}</div></div>`).join('')}
      <div class="note mt12">HERB never sends messages, pays or files anything for you — those stay at level 2 (draft) at most.</div>`;
    },
  };

  VIEWS.help = {
    title: 'Help',
    html: () => `<div class="card flush">${[['Customer service', 'Email support@prosperitysimplified.example (simulated)'], ['FAQs', 'Answers to common questions'], ['Member forum', 'Talk to other Logsperity users'],
      ['Input Cheat Sheet', 'Pillars, categories, sources, activities'], ['Refer a friend', 'Share Logsperity'], ['Other products', 'From Prosperity Simplified']].map(([a, b]) =>
        `<div class="li" data-act="${a === 'Input Cheat Sheet' ? 'push' : 'noop'}" data-v="cheat"><div class="t"><b>${esc(a)}</b><span>${esc(b)}</span></div><span class="chev">›</span></div>`).join('')}</div>
      <button class="ask" data-act="herb-ask" data-q="What can you do?"><span class="mic">${ICONS.mic}</span><span><b style="display:block">Ask HERB how to…</b><span class="small">“How do I log a closing?”</span></span></button>`,
  };

  VIEWS.privacy = {
    title: 'Data & privacy',
    html: () => `<div class="ok"><b>The developer stores none of your data.</b> On the iPhone your records live on the phone and in your own iCloud, with client fields end-to-end encrypted.</div>
      <h2>In this simulator</h2><div class="card">
        <div class="field"><span>Database</span><b>SQLite file on this PC (herb-sim/data)</b></div>
        <div class="field"><span>Data</span><b>Synthetic — fictional people</b></div>
        <div class="field"><span>Voice recognition</span><b>Edge/Chrome speech service</b></div>
        <div class="field"><span>HERB's answers</span><b>Computed locally</b></div>
        <div class="field"><span>Card numbers</span><b>Never collected (Apple billing)</b></div></div>
      <h2>On the iPhone</h2><div class="card">
        <div class="field"><span>This iPhone</span><b>Encrypted, Face ID</b></div><div class="field"><span>Your iCloud</span><b>Private database · E2E fields</b></div>
        <div class="field"><span>Developer servers</span><b>None</b></div><div class="field"><span>Speech & AI</span><b>On-device by default</b></div></div>`,
  };

  // ---------- HERB sheet ----------
  const convo = () => $('#convo');
  function addBubble(cls, html) { const d = document.createElement('div'); d.className = 'bub ' + cls; d.innerHTML = html; convo().appendChild(d); convo().scrollTop = 1e6; return d; }
  function herbEmptyState() {
    if (convo().children.length) return;
    addBubble('hb', `Hi, I'm HERB. Ask me about your numbers, or tell me something to log.
      <div class="sugg">${['What should I focus on this week?', 'Who do I need to follow up with?', 'Am I on track for my plan?', 'Which sources never close?', 'Where am I wasting time?', "What's my Logsperity Index?"]
        .map(q => `<button data-act="herb-ask" data-q="${esc(q)}">${esc(q)}</button>`).join('')}</div>`);
  }
  App.openHerb = function () { $('#herb').classList.add('open'); herbEmptyState(); };
  App.closeHerb = function () { $('#herb').classList.remove('open'); V.cancelListen && V.mode === 'ptt' && V.cancelListen(); V.stopSpeaking(); };

  function renderHerbReply(r) {
    const inDialog = 'dialog' in r;                 // follow-up questions (dialog.py): the server owns the flow
    if (inDialog) App.herbDialog = r.dialog || null;
    // one live draft card: earlier cards and buttons in the conversation are spent
    convo().querySelectorAll('.bub.dlg .herbcard.draft, .bub.dlg .sugg').forEach(e => e.remove());
    let html = esc(r.display || r.say || '');
    if (r.cards && r.cards.length) html += `<div class="herbcard">${r.cards.map(c => `<div class="li"><span class="dot" style="background:${c.chip && /late|overdue|concern|new|red/.test(c.chip) ? '#c2412d' : c.chip && /today|watch|gold/.test(c.chip) ? '#c98a12' : '#2c5fd6'}"></span>
      <div class="t"><b>${esc(c.title)}</b>${c.subtitle ? `<span>${esc(c.subtitle)}</span>` : ''}</div>${c.value ? `<span class="amt">${esc(c.value)}</span>` : ''}</div>`).join('')}</div>`;
    App.herbDraft = r.draft || (inDialog ? null : App.herbDraft);
    if (r.draft) {
      const sum = r.draft.summary || Object.entries(r.draft.data || {}).map(([label, value]) => ({ label, value }));
      html += `<div class="herbcard draft">${sum.map(s => `<div class="field${s.ask ? ' ask' : ''}"><span>${esc(s.label)}</span><b>${esc(s.value)}</b></div>`).join('')}</div>`;
    }
    const acts = (r.actions || []).slice(0, 7);
    if (r.draft && !inDialog) {
      if (!acts.some(a => a.action === 'confirm_draft')) acts.unshift({ label: 'Save', action: 'confirm_draft' });
      if (!acts.some(a => /^edit$/i.test(a.label))) acts.push({ label: 'Edit', action: 'edit_draft' });
      if (!acts.some(a => /^cancel$/i.test(a.label))) acts.push({ label: 'Cancel', action: 'cancel_draft' });
    }
    const primary = a => a.action === 'confirm_draft' || (a.action === 'reply' && /^(save|yes)\b/i.test(a.label));
    if (acts.length) html += `<div class="sugg">${acts.map((a, i) => `<button class="${i === 0 && primary(a) ? 'pri' : ''}" data-act="herb-action" data-a="${esc(a.action)}" data-t="${esc(a.target || a.label)}">${esc(a.label)}</button>`).join('')}</div>`;
    addBubble('hb' + (inDialog ? ' dlg' : ''), html);
    if (r.openForm) editDraft();
  }

  App.askHerb = async function (text, { voice = false } = {}) {
    text = String(text || '').trim(); if (!text) return;
    App.openHerb();
    const interim = convo().querySelector('.bub.interim'); if (interim) interim.remove();
    addBubble('me', esc(text));
    if (App.herbDialog) {                          // mid-conversation: HERB's dialog engine reads every answer
      if (/^(edit|open the form|let me (fix|edit|type))/i.test(text) && App.herbDraft) return editDraft();
    } else {                                       // legacy one-shot drafts
      if (App.herbDraft && /^(yes|yeah|yep|save( it)?|confirm|do it|sounds good|correct)\b/i.test(text)) return confirmDraft(voice);
      if (App.herbDraft && /^(no|cancel|never ?mind|stop)\b/i.test(text)) { App.herbDraft = null; return herbSay('Okay, I won\'t save that.', voice); }
      if (App.herbDraft && /^(edit|change( it)?|let me fix)/i.test(text)) return editDraft();
      if (/^(stop|be quiet|that's all|thanks herb|thank you)\b/i.test(text)) { V.stopSpeaking(); return herbSay('Anytime.', false); }
    }
    const thinking = addBubble('hb', '…');
    try {
      const r = await App.api('/api/herb', { method: 'POST', body: { text, dialog: App.herbDialog } });
      thinking.remove(); renderHerbReply(r);
      if (r.saved) { App.refreshBadges(); delete App.view().data; }
      await V.speak(r.say);
      if (!$('#herb').classList.contains('open')) return;
      // a question is waiting: listen for the answer without needing "Hi Herb" again
      if (App.herbDialog || r.followUp) { if (V.wakeOn) V.awaitReply(9000); else if (voice) V.listenOnce(); }
    } catch (e) { thinking.remove(); addBubble('hb', 'Sorry — I couldn\'t reach the Logsperity server. ' + esc(e.message)); }
  };
  async function herbSay(text, voice) { addBubble('hb', esc(text)); await V.speak(text); }
  async function confirmDraft(voice) {
    const draft = App.herbDraft; if (!draft) return;
    App.herbDraft = null;
    try {
      const r = await App.api('/api/herb/confirm', { method: 'POST', body: { draft } });
      addBubble('hb', esc(r.say || 'Saved.')); App.refreshBadges(); await V.speak(r.say || 'Saved.');
      const v = App.view(); delete v.data; if (!$('#herb').classList.contains('open')) App.render({ keepScroll: true });
    } catch (e) { addBubble('hb', 'Couldn\'t save: ' + esc(e.message)); }
  }
  async function editDraft() {
    const d = App.herbDraft; if (!d) return;
    App.herbDraft = null; App.herbDialog = null; App.closeHerb();
    App.tab = 'log'; App.stacks.log = [{ name: 'log' }];
    if (d.id) {                                     // an update to an existing record: open it with HERB's changes
      const row = await App.api(`/api/${d.log}/${d.id}`);
      return F.open(d.log, { id: d.id, row: { ...row, ...d.data } });
    }
    F.open(d.log, { draft: d.data });
  }
  function routeTarget(t) {
    App.closeHerb();
    if (!t) return;
    const [kind, arg] = String(t).split(':');
    if (kind === 'report') App.go('reports', 'report', { key: arg });
    else if (kind === 'log') App.go('log', 'logList', { log: arg });
    else if (kind === 'review') App.go('today', 'review');
    else if (kind === 'coach') App.go('coach');
    else if (kind === 'plan') App.go('more', 'plan');
    else if (kind === 'annual') App.go('reports', 'annual', { version: arg || 'complete' });
    else App.go('today');
  }

  // weekly check-in runs inside the HERB sheet
  async function runCheckin() {
    App.openHerb();
    addBubble('me', 'Start my weekly check-in');
    try {
      const r = await App.api('/api/coach/checkin', { method: 'POST', body: {} });
      for (const s of r.steps || []) {
        addBubble('hb', `<b>${esc(s.title)}</b>\n${esc(s.text)}`);
        await V.speak(s.say || s.text);
        if (!$('#herb').classList.contains('open')) return;
      }
      if (r.commitments && r.commitments.length) {
        App._commit = r.commitments;
        addBubble('hb', `Commit to these this week?<div class="herbcard">${r.commitments.map(c => `<div class="li"><span class="dot" style="background:#12806a"></span><div class="t"><b>${esc(c.text)}</b></div></div>`).join('')}</div>
          <div class="sugg"><button class="pri" data-act="commit">Commit</button><button data-act="herb-ask" data-q="What should I focus on this week?">Why these?</button></div>`);
      }
    } catch (e) { addBubble('hb', 'Check-in failed: ' + esc(e.message)); }
  }

  // ---------- printing / email ----------
  function printHtml(title, bodyHtml) {
    const w = window.open('', '_blank', 'width=1100,height=800');
    if (!w) { App.toast('Allow pop-ups to print.'); return; }
    w.document.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><link rel="stylesheet" href="${location.origin}/app.css">
      <style>body{display:block;background:#fff;padding:24px;font-family:Inter,"Segoe UI",sans-serif}@page{size:landscape}.grid{columns:3 300px;column-gap:14px}.w{break-inside:avoid}</style></head>
      <body><h1 style="font-weight:300;color:#5d6675">${esc(title)}</h1>${bodyHtml}<script>setTimeout(()=>print(),400)<\/script></body></html>`);
    w.document.close();
  }
  function emailText(subject, text) {
    const body = text.length > 1800 ? text.slice(0, 1800) + '\n…(full report attached as PDF in the real app)' : text;
    location.href = `mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }

  // ---------- actions ----------
  const ACTS = {
    tab: el => { const t = el.dataset.tab; if (App.tab === t) { App.stacks[t] = [App.stacks[t][0]]; } App.tab = t; delete App.view().data; App.render(); $('#screen').scrollTop = 0; },
    back: () => App.pop(),
    push: el => App.push(el.dataset.v),
    noop: () => {},
    'herb-open': () => App.openHerb(),
    'herb-close': () => App.closeHerb(),
    'herb-clear': () => { convo().innerHTML = ''; App.herbDraft = null; App.herbDialog = null; herbEmptyState(); },
    'herb-ask': el => App.askHerb(el.dataset.q),
    'herb-action': el => {
      const a = el.dataset.a, t = el.dataset.t;
      if (a === 'reply') return App.askHerb(t);      // quick reply to HERB's question
      if (a === 'confirm_draft') return confirmDraft(false);
      if (a === 'edit_draft') return editDraft();
      if (a === 'cancel_draft') { App.herbDraft = null; return addBubble('hb', 'Cancelled.'); }
      if (a === 'open') {
        if (/^form:/.test(t)) return editDraft();
        if (t === 'expense:scan') { const had = !!App.herbDraft; if (had) editDraft(); else { App.closeHerb(); F.open('expenses'); }
          setTimeout(() => { const b = document.querySelector('[data-act="scan-receipt"]'); if (b) b.click(); }, 400); return; }
        if (/^email:/.test(t)) return App.api('/api/reports/' + t.slice(6) + '?period=ytd').then(d => emailText(`Logsperity: ${d.title}`, W.toText(d.widgets)));
        return routeTarget(t);
      }
      if (a === 'say') {                       // HERB says the target text (e.g. Cancel, simulated calendar/texts)
        if (/^cancel$/i.test(el.textContent.trim())) App.herbDraft = null;
        return herbSay(t, false);
      }
      return App.askHerb(t);
    },
    mic: () => { if (V.mode === 'ptt') V.cancelListen(); else { App.openHerb(); V.listenOnce(); } },
    commit: async () => { await App.api('/api/coach/checkin', { method: 'POST', body: { commitments: App._commit } }); addBubble('hb', 'Committed. I\'ll check how it went next week.'); V.speak('Committed. I\'ll check how it went next week.'); },
    checkin: () => runCheckin(),
    kpi: el => { const k = el.dataset.k || ''; if (/index/.test(k)) App.go('coach'); else if (/pace|plan/.test(k)) App.go('more', 'plan'); else App.go('reports', 'report', { key: /conv/.test(k) ? 'conversion' : /expense/.test(k) ? 'expenses' : /closing/.test(k) ? 'closings' : /prospect/.test(k) ? 'prospects' : 'income' }); },
    review: () => App.push('review'),
    new: (el, ev) => { ev.stopPropagation(); F.open(el.dataset.log); },
    'open-log': el => App.push('logList', { log: el.dataset.log }),
    'open-prospect': async el => { if (!el.dataset.id) return; try { const d = await App.api(`/api/prospects?period=custom:2024-01-01:${App.today}&limit=3000`); const row = (d.rows || []).find(r => String(r.id) === el.dataset.id); if (row) F.open('prospects', { id: row.id, row }); } catch (e) { App.toast(e.message); } },
    'edit-row': el => { const v = App.view(); const row = (v.data.rows || []).find(r => String(r.id) === el.dataset.id); if (row) F.open(el.dataset.log, { id: row.id, row }); },
    'list-period': el => { const v = App.view(); v.period = el.dataset.v; delete v.data; App.render(); },
    'review-ok': async el => { await App.api('/api/review/' + el.dataset.id, { method: 'POST', body: { action: 'confirm' } }); App.toast('Confirmed.'); delete App.view().data; await App.refreshBadges(); App.render({ keepScroll: true }); },
    'review-no': async el => {
      const isTrip = el.dataset.id.startsWith('trips:');
      await App.api('/api/review/' + el.dataset.id, { method: 'POST', body: isTrip ? { action: 'confirm', patch: { is_business: 0 } } : { action: 'dismiss' } });
      App.toast(isTrip ? 'Marked personal.' : 'Dismissed.'); delete App.view().data; await App.refreshBadges(); App.render({ keepScroll: true });
    },
    'review-edit': async el => { const [log, id] = el.dataset.id.split(':'); const d = await App.api(`/api/${log}?period=last30&limit=500`); const row = (d.rows || []).find(r => String(r.id) === id);
      if (row) F.open(log, { id: row.id, row }); },
    'review-all': async () => { const items = App.view().data || []; for (const it of items) await App.api('/api/review/' + it.id, { method: 'POST', body: { action: 'confirm' } });
      App.toast(`Confirmed ${items.length}.`); delete App.view().data; await App.refreshBadges(); App.render(); },
    'rep-group': el => { App.view().group = el.dataset.v; App.render({ keepScroll: true }); },
    'open-report': el => App.push('report', { key: el.dataset.key }),
    'rep-period': el => { const v = App.view(); v.period = el.dataset.v; delete v.data; App.render({ keepScroll: true }); },
    'report-print': () => { const d = App.view().data; printHtml(`${d.title} — ${d.period ? d.period.label : ''}`, `<div class="grid">${W.render(d.widgets)}</div>`); },
    'report-email': () => { const d = App.view().data; emailText(`Logsperity: ${d.title} (${d.period ? d.period.label : ''})`, W.toText(d.widgets)); },
    'report-explain': () => { const d = App.view().data; App.askHerb(`Explain my ${d.title.toLowerCase()} report`); },
    'report-more': () => App.toast('Share as PDF, print or email — same as the buttons below.'),
    'print-sel': async () => { const v = App.view(); if (!v.sel || !v.sel.size) return App.toast('Check one or more reports first.');
      const parts = await Promise.all([...v.sel].map(k => App.api(`/api/reports/${k}?period=ytd`)));
      printHtml('Logsperity reports', parts.map(d => `<h2 class="page-title">${esc(d.title)}</h2><div class="grid">${W.render(d.widgets)}</div>`).join('<div style="break-after:page"></div>')); },
    'email-sel': async () => { const v = App.view(); if (!v.sel || !v.sel.size) return App.toast('Check one or more reports first.');
      const parts = await Promise.all([...v.sel].map(k => App.api(`/api/reports/${k}?period=ytd`)));
      emailText('Logsperity reports', parts.map(d => `== ${d.title} ==\n${W.toText(d.widgets)}`).join('\n\n')); },
    annual: el => App.push('annual', { version: el.dataset.v }),
    'annual-ver': el => { const v = App.view(); v.params.version = el.dataset.v; delete v.data; App.render(); },
    'annual-print': () => { const d = App.view().data; printHtml(d.title, (d.pages || []).map((p, i) => `<h2 class="page-title">${i + 1}. ${esc(p.title)}</h2><div class="grid">${W.render(p.widgets)}</div>`).join('<div style="break-after:page"></div>')); },
    'annual-email': () => { const d = App.view().data; emailText(d.title, (d.pages || []).map(p => `== ${p.title} ==\n${W.toText(p.widgets)}`).join('\n\n')); },
    ap: async el => { await App.api('/api/autopilot', { method: 'PUT', body: { key: el.dataset.k, level: +el.dataset.v } }); delete App.view().data; App.render({ keepScroll: true }); },
    hq: async el => { await App.api('/api/account', { method: 'PUT', body: { herbQuestions: el.dataset.v } }); delete App.view().data; App.render({ keepScroll: true }); },
    'hq-reset': async () => { await App.api('/api/account', { method: 'PUT', body: { herbNeverAsk: [], herbSkips: {} } }); delete App.view().data; App.render({ keepScroll: true }); App.toast('HERB will ask for those again.'); },
    reset: async () => { if (!confirm('Rebuild all synthetic data? Anything you entered will be lost.')) return; App.toast('Rebuilding…'); await App.api('/api/admin/reset', { method: 'POST', body: {} }); await boot(true); App.toast('Synthetic data rebuilt.'); },
    welcome: () => showWelcome(),
  };

  document.addEventListener('click', ev => {
    const el = ev.target.closest('[data-act]'); if (!el) return;
    const a = el.dataset.act, fn = ACTS[a] || F.acts[a];
    if (!fn) return;
    if (el.tagName === 'BUTTON' || el.tagName === 'A') ev.preventDefault();
    Promise.resolve(fn(el, ev)).catch(e => App.toast(e.message));
  });
  document.addEventListener('input', ev => {
    const el = ev.target;
    if (el.dataset.search) { const v = App.view(); v.q = el.value; clearTimeout(App._q); App._q = setTimeout(() => { delete v.data; App.render({ keepScroll: true, focus: null }).then(() => { const s = document.querySelector('[data-search]'); if (s) { s.focus(); s.setSelectionRange(s.value.length, s.value.length); } }); }, 300); return; }
    if (el.dataset.k && el.tagName !== 'SELECT' && el.type !== 'date') F.onInput(el);
  });
  document.addEventListener('change', ev => {
    const el = ev.target;
    if (el.dataset.photo !== undefined) return F.onPhoto(el);
    if (el.dataset.sel) { const v = App.view(); v.sel = v.sel || new Set(); el.checked ? v.sel.add(el.dataset.sel) : v.sel.delete(el.dataset.sel); App.render({ keepScroll: true }); return; }
    if (el.dataset.k && (el.tagName === 'SELECT' || el.type === 'date')) F.onInput(el);
  });
  $('#herbForm').addEventListener('submit', ev => { ev.preventDefault(); const i = $('#herbInput'); const t = i.value; i.value = ''; App.askHerb(t); });

  // ---------- welcome / onboarding ----------
  function showWelcome() {
    const w = $('#welcome');
    w.innerHTML = `<div class="logo"><svg viewBox="0 0 52 52"><circle cx="26" cy="26" r="23" fill="none" stroke="#9fd8ff" stroke-width="5"/><circle cx="26" cy="26" r="13" fill="none" stroke="#9fd8ff" stroke-width="4"/><circle cx="26" cy="26" r="6" fill="#f9c46b"/></svg>LOGSPERITY</div>
      <div class="tag">Know your numbers. Maximize your time. Multiply your prosperity.<br><span style="opacity:.7;font-size:15px">Your AI-powered business coach, HERB.</span></div>
      <div class="price"><div><b>$50</b>per month</div><div><b>$500</b>per year · save 20%</div></div>
      <div class="note" style="color:#cfe9e2;margin-top:8px">Subscriptions are billed by Apple. Logsperity never asks for a card number.</div>
      <div class="spacer"></div>
      <button class="btn out" data-act="wl-video">What is Logsperity?</button>
      <button class="btn apple" data-act="wl-join"> Sign in with Apple (simulated)</button>
      <button class="btn out" data-act="wl-join">Log in</button>`;
    w.hidden = false;
  }
  ACTS['wl-join'] = () => { $('#welcome').hidden = true; try { localStorage.setItem('herb.welcomed', '1'); } catch (e) {} App.toast('Signed in as Marcus Reed (synthetic account).'); };
  ACTS['wl-video'] = () => App.toast('This button plays the animated explainer video in the real app.');

  // ---------- simulator side panel ----------
  function syncVoiceUi() {
    const pill = $('#micState'), m = V.mode;
    const label = V.speaking ? 'HERB speaking' : m === 'wake' ? 'Listening for “Hi Herb”' : m === 'command' ? 'Go ahead…' : m === 'ptt' ? 'Listening…' : 'Mic off';
    pill.className = 'pill ' + (V.speaking || m !== 'idle' ? 'on' : 'off'); pill.lastElementChild.textContent = label;
    $('#wakeBtn').textContent = V.wakeOn ? 'Stop listening' : 'Listen for “Hi Herb”';
    const big = $('#bigmic'); big.innerHTML = (m === 'ptt' || m === 'command') ? ICONS.stop : ICONS.mic; big.classList.toggle('listening', m === 'ptt' || m === 'command');
    const wave = $('#wave'); wave.classList.toggle('on', m === 'ptt' || m === 'command' || V.speaking); wave.classList.toggle('speaking', V.speaking);
    $('#island').classList.toggle('live', m !== 'idle' || V.speaking);
    $('#herbHint').textContent = V.speaking ? 'HERB is talking — tap the mic to interrupt' : m === 'command' ? 'Go ahead — I\'m listening' : m === 'ptt' ? 'Listening… tap to stop' : V.wakeOn ? 'Say “Hi Herb…” any time' : 'Tap the mic or type below';
  }
  function setupPanel() {
    V.onState = syncVoiceUi;
    V.onHeard = t => { $('#heard').textContent = 'Heard: ' + t; };
    V.onWake = () => { App.openHerb(); };
    V.onInterim = t => {
      let b = convo().querySelector('.bub.interim');
      if (!t) { if (b) b.remove(); return; }
      if (!b) { App.openHerb(); b = addBubble('me interim', ''); }
      b.textContent = t; convo().scrollTop = 1e6;
    };
    V.onCommand = (t, o) => App.askHerb(t, o);
    V.init();
    const note = $('#voiceNote');
    if (!V.supported) note.innerHTML = '⚠ This browser has no speech recognition. Open <b>http://localhost:8765</b> in <b>Microsoft Edge</b> or <b>Google Chrome</b> to talk to HERB. Typing works everywhere.';
    else if (V.likelyEmbedded) note.innerHTML = 'You\'re in an embedded browser — the mic may not work here. For voice, open <b>http://localhost:8765</b> in Edge or Chrome.';
    else note.textContent = 'The first time, the browser asks to use the microphone — choose Allow. Recognition uses the browser\'s speech service.';
    $('#wakeBtn').onclick = () => V.setWake(!V.wakeOn);
    $('#pttBtn').onclick = () => { App.openHerb(); V.listenOnce(); };
    const fillVoices = () => { const vs = V.voices(); $('#voiceSel').innerHTML = vs.map(v => `<option ${V.voice && v.name === V.voice.name ? 'selected' : ''}>${esc(v.name)}</option>`).join('') || '<option>No voices found</option>'; };
    fillVoices(); if (V.ttsSupported) speechSynthesis.addEventListener('voiceschanged', fillVoices);
    $('#voiceSel').onchange = e => { V.setVoice(e.target.value); V.speak('Hi, I\'m HERB.'); };
    $('#rate').value = V.rate; $('#rate').oninput = e => V.setRate(parseFloat(e.target.value));
    $('#speakOn').onchange = e => { V.speakOn = e.target.checked; if (!V.speakOn) V.stopSpeaking(); };
    $('#resetBtn').onclick = () => ACTS.reset();
    $('#welcomeBtn').onclick = () => showWelcome();
    const tries = ['Hi Herb, new prospect Tom Rodgers, 847-477-0619, follow up next week',
      'Hi Herb, new prospect Tom Rodgers, follow up next week',
      'Hi Herb, new prospect Tom Rodgers, 216 Shadow Creek Lane, Hickory Creek Texas, 847-477-0619, follow up next week',
      'Hi Herb, I spent 45 dollars', 'Hi Herb, two hours of door knocking, got two leads',
      'Hi Herb, I called Priya Shah, she\'s not ready yet', 'Hi Herb, the Morales loan closed',
      'Hi Herb, I have some leads to record', 'Hi Herb, got paid 3,000', 'Hi Herb, drove 12 miles',
      'Hi Herb, what should I focus on this week?', 'Hi Herb, who do I need to follow up with?',
      'Hi Herb, which sources never close?', 'Hi Herb, am I on track for my plan?'];
    $('#tryList').innerHTML = tries.map(t => `<button class="say" data-try="${esc(t)}">“${esc(t)}”</button>`).join('');
    $('#tryList').onclick = e => { const b = e.target.closest('[data-try]'); if (b) App.askHerb(b.dataset.try.replace(/^(hi|hey) herb,?\s*/i, '')); };
    syncVoiceUi();
  }

  function tick() {
    const t = new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }).replace(/\s?[AP]M/, '');
    $('#clock').textContent = t; $('#clock2').textContent = t;
  }

  async function boot(reset = false) {
    App.T = await App.api('/api/taxonomy');
    const today = await App.api('/api/today');
    App.today = today.date || App.today;
    App.plan = await App.api('/api/plan').catch(() => null);
    try { const ex = await App.api('/api/expenses?period=ytd&limit=500'); App.cache.vendors = (ex.rows || []).map(r => r.vendor); } catch (e) {}
    for (const t of Object.keys(App.stacks)) { App.stacks[t] = [App.stacks[t][0]]; delete App.stacks[t][0].data; }
    App.stacks.today[0].data = today;
    if (reset) { convo().innerHTML = ''; App.herbDraft = null; App.herbDialog = null; }
    await App.refreshBadges();
    App.render();
  }

  setupPanel(); tick(); setInterval(tick, 15000);
  boot().catch(e => { $('#screen').innerHTML = `<div class="warn" style="margin-top:20px">Can't reach the Logsperity server: ${esc(e.message)}.<br>Start it with <b>run.bat</b> (or <code>python server.py</code>) and reload.</div>`; });
  let welcomed = null; try { welcomed = localStorage.getItem('herb.welcomed'); } catch (e) {}
  if (!welcomed) showWelcome();
})();
