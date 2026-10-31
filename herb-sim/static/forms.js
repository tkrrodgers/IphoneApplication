/* Input screens (design §10): Prospect, Closing, Income, Expense, Mileage, Activity — plus Account (§8.1)
   and Business Plan Set Up (§9). State lives in F.state; inputs carry data-k (field) and data-i (row). */
(function () {
  const { esc } = W;
  const LOGS = {
    prospects: { title: 'Prospect', multi: false },
    closings: { title: 'Closing', multi: false },
    income: { title: 'Income', multi: false },
    expenses: { title: 'Expense', multi: true },
    trips: { title: 'Mileage', multi: true },
    activities: { title: 'Activity', multi: true },
  };
  // Small offline zip table for the simulator (the app would use a full zip database)
  const ZIPS = { '76201': ['Denton', 'TX'], '76205': ['Denton', 'TX'], '76209': ['Denton', 'TX'], '76210': ['Denton', 'TX'], '76226': ['Argyle', 'TX'],
    '75034': ['Frisco', 'TX'], '75033': ['Frisco', 'TX'], '76092': ['Southlake', 'TX'], '75201': ['Dallas', 'TX'], '75028': ['Flower Mound', 'TX'],
    '76262': ['Roanoke', 'TX'], '75022': ['Flower Mound', 'TX'], '76177': ['Fort Worth', 'TX'], '75070': ['McKinney', 'TX'] };
  const SAMPLE_RECEIPTS = [
    { vendor: 'Cedar Grill', amount: 86.40, group_id: 'relationships', cat: 'meal', purpose: 'Q4 referral pipeline review', with_whom: 'Dana Ruiz' },
    { vendor: 'Office Depot', amount: 42.17, group_id: 'general', cat: 'office_supplies', purpose: 'Folders and printer paper' },
    { vendor: 'Vistaprint', amount: 128.00, group_id: 'ad_traditional', cat: 'flyer', purpose: 'Open house flyers' },
    { vendor: 'Starbucks', amount: 14.85, group_id: 'relationships', cat: 'meal', purpose: 'Coffee with realtor', with_whom: 'Ruth Alvarez' },
  ];

  const today = () => App.today;
  const addDays = (iso, n) => { const d = new Date(iso + 'T12:00:00'); d.setDate(d.getDate() + n); return d.toISOString().slice(0, 10); };
  const opt = x => (typeof x === 'string' ? { id: x, name: x } : x);
  const snake = k => k.replace(/[A-Z]/g, m => '_' + m.toLowerCase());
  const toSnake = o => Object.fromEntries(Object.entries(o || {}).map(([k, v]) => [snake(k), v]));

  const F = { state: null, sources: [], prospects: [], closings: [] };

  function blank(log) {
    const d = { date: today(), capture: 'manual' };
    switch (log) {
      case 'prospects': return { ...d, pillar: '', category_id: '', activity_id: '', source: '', strength: 'medium', plan_of_action: '', follow_up_days: '7', follow_up: addDays(today(), 7), phone1_type: 'Mobile', phone2_type: 'Mobile' };
      case 'closings': return { ...d, prospect_id: '', add_to_income: true, referral_request: 'ask_14', additional: [] };
      case 'income': return { ...d, mode: 'transaction', expect_1099: true };
      case 'expenses': return { ...d, group_id: '', category_id: '', amount: '' };
      case 'trips': return { ...d, reason: '', destination: '', is_business: true };
      case 'activities': return { ...d, pillar: '', activity_id: '', minutes: '60' };
    }
    return d;
  }

  // ---------- open ----------
  F.open = async function (log, { id = null, row = null, draft = null } = {}) {
    const meta = LOGS[log];
    let rows;
    if (row) rows = [{ ...blank(log), ...toSnake(row), source: row.sourceName || row.source_name || row.source || '' }];
    else if (draft) rows = (Array.isArray(draft) ? draft : [draft]).map(d => ({ ...blank(log), ...toSnake(d), source: d.sourceName || d.source || d.source_name || '' }));
    else rows = [blank(log)];
    rows.forEach(r => { r.capture = r.capture || 'manual'; if (draft) r._auto = Object.keys(toSnake(Array.isArray(draft) ? draft[0] : draft)); });
    F.state = { log, id, rows, meta, errors: {} };
    App.push('form', { log, id });
    loadLookups(log);
  };

  async function loadLookups(log) {
    try {
      F.sources = await App.api('/api/sources');
      if (log === 'closings' || log === 'income') {
        const [p, c] = await Promise.all([App.api('/api/prospects?period=custom:2024-01-01:' + today() + '&limit=2000'),
          App.api('/api/closings?period=custom:2024-01-01:' + today() + '&limit=2000')]);
        F.closings = c.rows || [];
        const closed = new Set(F.closings.map(x => x.prospect_id));
        F.prospects = (p.rows || []).filter(x => !closed.has(x.id) || (F.state && x.id === Number(F.state.rows[0].prospect_id)));
      }
      if (log === 'trips') {
        const t = await App.api('/api/trips?period=last30&limit=200');
        F.destinations = [...new Set((t.rows || []).map(r => r.destination).filter(Boolean))];
      }
    } catch (e) { console.warn(e); }
    if (App.view().name === 'form') App.render();
  }

  // ---------- controls ----------
  const val = (r, k) => (r[k] ?? '');
  const autoMark = (r, k) => (r._auto && r._auto.includes(k) ? '<span class="auto">auto</span>' : '');
  function input(r, i, k, type = 'text', extra = '') {
    return `<input data-k="${k}" data-i="${i}" type="${type}" value="${esc(val(r, k))}" ${extra}>`;
  }
  function select(r, i, k, options, placeholder = 'Choose', extra = '') {
    const v = String(val(r, k));
    return `<select data-k="${k}" data-i="${i}" ${extra}><option value="">${esc(placeholder)}</option>${options.map(o => { o = opt(o);
      return `<option value="${esc(o.id)}" ${String(o.id) === v ? 'selected' : ''}>${esc(o.name)}</option>`; }).join('')}</select>`;
  }
  function f(label, control, { req = false, k = null, r = null, col = false } = {}) {
    const bad = F.state.errors[k];
    return `<div class="f ${col ? 'col' : ''} ${bad ? 'invalid' : ''}"><label>${esc(label)}${req ? ' <span class="req">*</span>' : ''}${r && k ? autoMark(r, k) : ''}</label>${control}</div>`;
  }
  const T = () => App.T;
  const cats = p => T().categories.filter(c => !p || c.pillar === p);
  const acts = p => T().activities.filter(a => !p || a.pillar === p);
  const groupLabel = items => items.map(c => ({ id: c.id, name: `${c.name}${c.subPillar && c.subPillar !== c.pillar ? ' · ' + subName(c.subPillar) : ''}` }));
  const subName = s => (T().subPillars.find(x => x.id === s) || {}).name || s;
  const sourceList = () => `<datalist id="srcList">${F.sources.map(s => `<option value="${esc(s.name)}">`).join('')}</datalist>`;

  function attribution(r, i, { required = true, label = 'Where it came from' } = {}) {
    return `<div class="form-h"><span>${label}</span><a class="link small" data-act="cheat">Cheat sheet</a></div><div class="form">
      ${f('Pillar', select(r, i, 'pillar', T().pillars, 'Choose pillar'), { req: required, k: 'pillar', r })}
      ${f('Category', select(r, i, 'category_id', groupLabel(cats(r.pillar)), r.pillar ? 'Choose category' : 'Pick a pillar first'), { req: required, k: 'category_id', r })}
      ${f('Source', input(r, i, 'source', 'text', 'list="srcList" placeholder="Person or company"'), { req: required, k: 'source', r })}
      ${f('Activity used', select(r, i, 'activity_id', groupLabel(acts(r.pillar)), r.pillar ? 'Choose activity' : 'Pick a pillar first'), { req: required, k: 'activity_id', r })}
    </div>`;
  }

  function contact(r, i) {
    const phoneTypes = T().picklists.phoneTypes || ['Mobile', 'Work', 'Home', 'Other'];
    return `<div class="form-h"><span>Contact</span><a class="link small" data-act="scan-card">Scan card (simulated)</a></div><div class="form">
      ${f('Last name', input(r, i, 'last_name'), { req: true, k: 'last_name', r })}
      ${f('First name(s)', input(r, i, 'first_names'), { k: 'first_names', r })}
      ${f('Phone 1', input(r, i, 'phone1', 'tel') + select(r, i, 'phone1_type', phoneTypes, 'Type', 'style="flex:none;width:80px"'), { k: 'phone1', r })}
      ${f('Phone 2', input(r, i, 'phone2', 'tel') + select(r, i, 'phone2_type', phoneTypes, 'Type', 'style="flex:none;width:80px"'), { k: 'phone2', r })}
      ${f('Email 1', input(r, i, 'email1', 'email'), { k: 'email1', r })}
      ${f('Email 2', input(r, i, 'email2', 'email'), { k: 'email2', r })}
      ${f('Address', input(r, i, 'address'), { k: 'address', r })}
      ${f('Zip', input(r, i, 'zip', 'text', 'inputmode="numeric" maxlength="5"'), { k: 'zip', r })}
      ${f('City & state', `<input data-k="city" data-i="${i}" value="${esc(val(r, 'city'))}" placeholder="From zip"><input data-k="state" data-i="${i}" value="${esc(val(r, 'state'))}" style="flex:none;width:36px" maxlength="2">`)}
    </div>`;
  }

  // ---------- screens ----------
  function prospect(r) {
    const strength = (T().picklists.strength || []).map(opt);
    const days = T().picklists.followUpDays || [5, 7, 10, 15, 21, 30, 45, 60, 75, 90, 120, 180, 250, 365];
    return contact(r, 0) + attribution(r, 0) + `
      <div class="form-h"><span>Follow-up</span></div><div class="form">
      ${f('Strength', `<div class="colors">${strength.map(s => `<button type="button" data-act="strength" data-v="${esc(s.id)}" class="${r.strength === s.id ? 'on' : ''}" style="background:${esc(s.color || '#eee')}22;color:${esc(s.color || '#333')}">${esc(s.name)}</button>`).join('')}</div>`, { k: 'strength', r })}
      ${f('Plan of action', select(r, 0, 'plan_of_action', T().picklists.planOfAction || []), { k: 'plan_of_action', r })}
      ${f('Follow up in', select(r, 0, 'follow_up_days', days.map(d => ({ id: String(d), name: d + ' days' })), 'Pick a date →'), { k: 'follow_up_days', r })}
      ${f('Follow-up date', input(r, 0, 'follow_up', 'date'), { k: 'follow_up', r })}
      ${f('Originally from', input(r, 0, 'originally_from', 'text', 'list="srcList" placeholder="Optional (rule R2)"'), { k: 'originally_from', r })}
      ${f('Notes', `<textarea data-k="notes" data-i="0">${esc(val(r, 'notes'))}</textarea>`, { col: true, k: 'notes', r })}
      </div>`;
  }

  function closing(r) {
    const plist = F.prospects.map(p => ({ id: String(p.id), name: `${[p.first_names, p.last_name].filter(Boolean).join(' ')} · ${p.date}` }));
    const isNew = r.prospect_id === 'new';
    const yieldPct = App.plan && App.plan.outputs ? App.plan.outputs.yieldPct : null;
    const suggest = yieldPct && r.transaction_size ? Math.round(Number(r.transaction_size) * yieldPct) : null;
    const rr = (T().picklists.referralRequest || []).map(opt);
    return `<div class="form-h"><span>Client</span></div><div class="form">
      ${f('Choose prospect', select(r, 0, 'prospect_id', [{ id: 'new', name: '+ New client (not in prospects)' }, ...plist], plist.length ? 'Choose from prospects' : 'Loading…'), { req: true, k: 'prospect_id', r })}
      ${isNew ? f('Last name', input(r, 0, 'last_name'), { req: true, k: 'last_name', r }) + f('First name(s)', input(r, 0, 'first_names')) + f('Phone', input(r, 0, 'phone1', 'tel')) + f('Email', input(r, 0, 'email1', 'email')) : ''}
      </div>
      ${r.prospect_id && !isNew ? `<div class="note mt8" style="padding:0 4px">Contact details, pillar, category, source and activity carry over from the prospect.</div>` : ''}
      ${attribution(r, 0)}
      <div class="form-h"><span>The deal</span></div><div class="form">
      ${f('Transaction size', input(r, 0, 'transaction_size', 'number', 'step="1000" placeholder="Volume $"'), { req: true, k: 'transaction_size', r })}
      ${f('Income earned', input(r, 0, 'income', 'number', `step="50" placeholder="${suggest ? 'Suggest $' + suggest.toLocaleString() : 'Your income $'}"`), { req: true, k: 'income', r })}
      ${f('Add to Income Log?', `<span class="spacer"></span><button type="button" class="toggle ${r.add_to_income ? '' : 'off'}" data-act="toggle" data-k="add_to_income"></button>`)}
      ${f('Referral / review', select(r, 0, 'referral_request', rr, 'Choose'), { k: 'referral_request', r })}
      ${f('Post-closing follow-up', input(r, 0, 'post_closing_follow_up', 'date'))}
      ${f('Notes', `<textarea data-k="notes" data-i="0">${esc(val(r, 'notes'))}</textarea>`, { col: true })}
      </div>
      <div class="form-h"><span>Additional transactions (go to Income log · rule R3)</span></div>
      ${(r.additional || []).map((a, j) => `<div class="form">
        ${f('Transaction size', `<input data-k="transaction_size" data-add="${j}" type="number" value="${esc(a.transaction_size || '')}">`)}
        ${f('Income', `<input data-k="income" data-add="${j}" type="number" value="${esc(a.income || '')}">`)}
        <div class="f"><button type="button" class="rm" data-act="rm-add" data-j="${j}">Remove</button></div></div>`).join('')}
      <button type="button" class="add-row" data-act="add-additional">+ Additional transaction for this client</button>`;
  }

  function income(r) {
    const types = (T().picklists.incomeTypes || []).map(opt);
    const clist = F.closings.map(c => ({ id: String(c.id), name: `${c.name || [c.first_names, c.last_name].filter(Boolean).join(' ') || 'Closing #' + c.id} · ${c.date} · $${Math.round(c.income || 0).toLocaleString()}` }));
    const avg = r.mode === 'batch' && r.transaction_count && r.amount ? '$' + Math.round(r.amount / r.transaction_count).toLocaleString() : '—';
    let body = '';
    if (r.mode === 'transaction') body = `<div class="form">
        ${f('Choose closing', select(r, 0, 'closing_id', clist, clist.length ? 'Choose from closings' : 'Loading…'), { k: 'closing_id', r })}
        ${f('Last name', input(r, 0, 'last_name'), { k: 'last_name', r })}
        ${f('Transaction size', input(r, 0, 'transaction_size', 'number'), { k: 'transaction_size', r })}
        ${f('Income', input(r, 0, 'amount', 'number'), { req: true, k: 'amount', r })}</div>${attribution(r, 0, { required: false })}`;
    else if (r.mode === 'batch') body = `<div class="form">
        ${f('Type', select(r, 0, 'type', types), { req: true, k: 'type', r })}
        ${f('# of transactions', input(r, 0, 'transaction_count', 'number', 'min="1"'), { req: true, k: 'transaction_count', r })}
        ${f('Income amount', input(r, 0, 'amount', 'number'), { req: true, k: 'amount', r })}
        ${f('Avg per transaction', `<span class="calc">${avg}</span>`)}</div>`;
    else body = `<div class="form">
        ${f('Type', select(r, 0, 'type', types), { req: true, k: 'type', r })}
        ${f('Amount', input(r, 0, 'amount', 'number'), { req: true, k: 'amount', r })}
        ${f('Pillar (optional)', select(r, 0, 'pillar', T().pillars, 'None'))}</div>`;
    return `<div class="seg" style="margin-bottom:6px">${[['transaction', 'By transaction'], ['batch', 'Batch'], ['type', 'By type']].map(([m, n]) =>
      `<button type="button" data-act="mode" data-v="${m}" class="${r.mode === m ? 'on' : ''}">${n}</button>`).join('')}</div>
      ${body}
      <div class="form-h"><span>Details</span></div><div class="form">
      ${f('Payer', input(r, 0, 'payer', 'text', 'placeholder="Lender or company"'), { k: 'payer', r })}
      ${f('1099 expected', `<span class="spacer"></span><button type="button" class="toggle ${r.expect_1099 ? '' : 'off'}" data-act="toggle" data-k="expect_1099"></button>`)}
      ${f('Notes', `<textarea data-k="notes" data-i="0">${esc(val(r, 'notes'))}</textarea>`, { col: true })}</div>`;
  }

  function expenseRow(r, i, n) {
    const groups = T().expenseGroups;
    const ecats = T().expenseCategories.filter(c => c.group === r.group_id);
    const cat = T().expenseCategories.find(c => c.id === r.category_id);
    return `<div class="multi-h"><span>Expense ${n > 1 ? i + 1 : ''}</span>${n > 1 ? `<button type="button" class="rm" data-act="rm-row" data-i="${i}">Remove</button>` : ''}</div>
      <div class="form">
      ${f('Date', input(r, i, 'date', 'date'), { req: true, k: 'date', r })}
      ${f('Vendor', input(r, i, 'vendor', 'text', 'list="vendorList"'), { req: true, k: 'vendor', r })}
      ${f('Amount', input(r, i, 'amount', 'number', 'step="0.01"'), { req: true, k: 'amount', r })}
      ${f('Pillar / group', select(r, i, 'group_id', groups.map(g => ({ id: g.id, name: g.pillar ? g.name : 'No pillar · ' + g.name })), 'Choose'), { req: true, k: 'group_id', r })}
      ${f('Category', select(r, i, 'category_id', ecats, r.group_id ? 'Choose' : 'Pick a group first'), { req: true, k: 'category_id', r })}
      ${cat ? f('IRS category', `<span class="spacer"></span><span class="irs">${esc(cat.irs)}</span>`) : ''}
      ${r.group_id === 'relationships' ? f('Relationship', select(r, i, 'relationship_sub_pillar', [{ id: 'personal', name: 'Personal' }, { id: 'professional', name: 'Professional' }], 'Choose'), { req: true, k: 'relationship_sub_pillar', r }) : ''}
      ${f('For source', input(r, i, 'source', 'text', 'list="srcList" placeholder="Optional"'), { k: 'source', r })}
      ${f('Business purpose', input(r, i, 'purpose'), { k: 'purpose', r })}
      ${f('With whom', input(r, i, 'with_whom'), { k: 'with_whom', r })}
      ${f('Check #', input(r, i, 'check_number'), { k: 'check_number', r })}
      ${f('Card (last 4)', input(r, i, 'card_last4', 'text', 'maxlength="4" inputmode="numeric"'), { k: 'card_last4', r })}
      ${f('Receipt', `<span class="spacer"></span>${r._photo ? `<img class="receipt-thumb" src="${r._photo}">` : r.has_receipt ? '<span class="chip c-green">On file</span>' : ''}
          <label class="btn small ghost" style="margin:0">Photo<input type="file" accept="image/*" capture="environment" data-photo="${i}" hidden></label>
          <button type="button" class="btn small ghost" data-act="scan-receipt" data-i="${i}">Scan sample</button>`)}
      ${f('Notes', `<textarea data-k="notes" data-i="${i}">${esc(val(r, 'notes'))}</textarea>`, { col: true })}
      </div>`;
  }

  function tripRow(r, i, n) {
    const miles = r.gps_miles ? Number(r.gps_miles) : (r.odometer_end && r.odometer_start ? Math.max(0, r.odometer_end - r.odometer_start) : 0);
    return `<div class="multi-h"><span>Trip ${n > 1 ? i + 1 : ''}</span>${n > 1 ? `<button type="button" class="rm" data-act="rm-row" data-i="${i}">Remove</button>` : ''}</div>
      <div class="form">
      ${f('Date', input(r, i, 'date', 'date'), { req: true, k: 'date', r })}
      ${f('Reason', input(r, i, 'reason', 'text', 'list="reasonList"'), { req: true, k: 'reason', r })}
      ${f('Destination', input(r, i, 'destination', 'text', 'list="destList"'), { req: true, k: 'destination', r })}
      ${r.gps_miles ? f('GPS miles', input(r, i, 'gps_miles', 'number', 'step="0.1"'), { k: 'gps_miles', r }) : `
      ${f('Beginning odometer', input(r, i, 'odometer_start', 'number'), { k: 'odometer_start', r })}
      ${f('Ending odometer', input(r, i, 'odometer_end', 'number'), { k: 'odometer_end', r })}`}
      ${f('Total', `<span class="calc">${miles ? miles.toFixed(1) + ' mi' : '—'}</span><button type="button" class="btn small ghost" data-act="gps" data-i="${i}">${r.gps_miles ? 'Use odometer' : 'GPS trip'}</button>`)}
      ${f('Business trip', `<span class="spacer"></span><button type="button" class="toggle ${r.is_business ? '' : 'off'}" data-act="toggle" data-k="is_business" data-i="${i}"></button>`)}
      </div>`;
  }

  function activityRow(r, i, n) {
    const mins = []; for (let m = 15; m <= 600; m += 15) mins.push({ id: String(m), name: m < 60 ? m + ' min' : (m / 60) + ' h' });
    return `<div class="multi-h"><span>Activity ${n > 1 ? i + 1 : ''}</span>${n > 1 ? `<button type="button" class="rm" data-act="rm-row" data-i="${i}">Remove</button>` : ''}</div>
      <div class="form">
      ${f('Date', input(r, i, 'date', 'date'), { req: true, k: 'date', r })}
      ${f('Pillar', select(r, i, 'pillar', T().pillars, 'Choose pillar'), { req: true, k: 'pillar', r })}
      ${f('Activity', select(r, i, 'activity_id', groupLabel(acts(r.pillar)), r.pillar ? 'Choose' : 'Pick a pillar first'), { req: true, k: 'activity_id', r })}
      ${f('Time', select(r, i, 'minutes', mins, 'Choose'), { req: true, k: 'minutes', r })}
      ${f('With / source', input(r, i, 'source', 'text', 'list="srcList" placeholder="Optional"'), { k: 'source', r })}
      ${f('Notes', input(r, i, 'notes'), { k: 'notes', r })}
      </div>`;
  }

  F.html = function () {
    const s = F.state; if (!s) return '<div class="empty">No form</div>';
    const r0 = s.rows[0];
    let body;
    if (s.log === 'prospects') body = prospect(r0);
    else if (s.log === 'closings') body = closing(r0);
    else if (s.log === 'income') body = income(r0);
    else {
      const fn = { expenses: expenseRow, trips: tripRow, activities: activityRow }[s.log];
      body = s.rows.map((r, i) => fn(r, i, s.rows.length)).join('') + (s.id ? '' : `<button type="button" class="add-row" data-act="add-row">+ Add another ${s.meta.title.toLowerCase()}</button>`);
      if (s.log === 'trips') {
        const tot = s.rows.reduce((a, r) => a + (r.gps_miles ? Number(r.gps_miles) : Math.max(0, (r.odometer_end || 0) - (r.odometer_start || 0))), 0);
        body += `<div class="card mt12 row"><b>Grand total for the day</b><span class="spacer"></span><b>${tot.toFixed(1)} mi</b></div>`;
      }
    }
    const reasons = (T().picklists.mileageReasons || []);
    const vendors = [...new Set((App.cache.vendors || []))];
    const fromHerb = r0._auto ? `<div class="ok" style="margin-bottom:8px"><b>HERB filled this in.</b> Fields marked <span class="auto">auto</span> came from what you said — check them and tap Save.</div>` : '';
    return `${fromHerb}<form id="logForm" autocomplete="off">${body}</form>
      ${sourceList()}<datalist id="reasonList">${reasons.map(x => `<option value="${esc(x)}">`).join('')}</datalist>
      <datalist id="destList">${(F.destinations || []).map(x => `<option value="${esc(x)}">`).join('')}</datalist>
      <datalist id="vendorList">${vendors.map(x => `<option value="${esc(x)}">`).join('')}</datalist>
      ${Object.keys(s.errors).length ? `<div class="warn mt12">Please fill in the fields marked in red.</div>` : ''}
      <div class="btns"><button class="btn primary" data-act="save">${s.id ? 'Save changes' : 'Save'}</button>${s.id ? '' : `<button class="btn ghost" data-act="save-next">Save &amp; next</button>`}</div>
      ${s.id ? `<button class="btn danger mt8" data-act="delete">Delete</button>` : ''}
      <div class="note center mt12">Date fills in automatically and can be changed. Source remembers what you typed before.</div>`;
  };

  // ---------- events ----------
  F.onInput = function (el) {
    const s = F.state; if (!s) return;
    const k = el.dataset.k; if (!k) return;
    if (el.dataset.add !== undefined) { s.rows[0].additional[+el.dataset.add][k] = el.value; return; }
    const i = +(el.dataset.i || 0), r = s.rows[i];
    r[k] = el.type === 'number' ? (el.value === '' ? '' : Number(el.value)) : el.value;
    if (r._auto) r._auto = r._auto.filter(x => x !== k);
    delete s.errors[k];
    let rerender = false;
    if (k === 'pillar') { r.category_id = ''; r.activity_id = ''; rerender = true; }
    if (k === 'group_id') { r.category_id = ''; rerender = true; }
    if (k === 'category_id' && s.log === 'expenses') rerender = true;
    if (k === 'follow_up_days' && el.value) { r.follow_up = addDays(r.date || today(), +el.value); rerender = true; }
    if (k === 'zip' && ZIPS[el.value]) { [r.city, r.state] = ZIPS[el.value]; rerender = true; }
    if (k === 'prospect_id') { carryProspect(r); rerender = true; }
    if (k === 'closing_id') { carryClosing(r); rerender = true; }
    if (['odometer_start', 'odometer_end', 'gps_miles', 'transaction_count', 'amount', 'transaction_size'].includes(k) && el.type !== 'text' && el.tagName === 'INPUT' && el.dataset.k !== 'amount') rerender = s.log === 'trips' || s.log === 'closings';
    if (s.log === 'income' && (k === 'transaction_count' || k === 'amount')) rerender = true;
    if (rerender) App.render({ keepScroll: true, focus: el.tagName === 'INPUT' && el.type !== 'date' ? { k, i } : null });
  };

  function carryProspect(r) {
    const p = F.prospects.find(x => String(x.id) === String(r.prospect_id)); if (!p) return;
    Object.assign(r, { pillar: p.pillar, category_id: p.category_id, activity_id: p.activity_id, source: p.sourceName || p.source_name || '',
      last_name: p.last_name, first_names: p.first_names });
  }
  function carryClosing(r) {
    const c = F.closings.find(x => String(x.id) === String(r.closing_id)); if (!c) return;
    Object.assign(r, { pillar: c.pillar, category_id: c.category_id, activity_id: c.activity_id, source: c.sourceName || c.source_name || '',
      last_name: c.last_name || (c.name || '').split(' ').slice(-1)[0], transaction_size: c.transaction_size, amount: c.income });
  }

  F.onPhoto = function (el) {
    const i = +el.dataset.photo, file = el.files && el.files[0]; if (!file) return;
    const rd = new FileReader();
    rd.onload = () => { F.state.rows[i]._photo = rd.result; F.state.rows[i].has_receipt = 1; F.state.rows[i].capture = 'receipt';
      App.toast('Receipt photo attached. (On the iPhone, HERB reads the receipt on-device.)'); App.render({ keepScroll: true }); };
    rd.readAsDataURL(file);
  };

  F.acts = {
    strength: el => { F.state.rows[0].strength = el.dataset.v; App.render({ keepScroll: true }); },
    toggle: el => { const r = F.state.rows[+(el.dataset.i || 0)]; r[el.dataset.k] = !r[el.dataset.k]; App.render({ keepScroll: true }); },
    mode: el => { const r = F.state.rows[0]; r.mode = el.dataset.v; App.render({ keepScroll: true }); },
    'add-row': () => { const last = F.state.rows[F.state.rows.length - 1]; const nr = blank(F.state.log); nr.date = last.date;
      if (F.state.log === 'trips' && last.odometer_end) nr.odometer_start = last.odometer_end; // rule R6
      F.state.rows.push(nr); App.render({ keepScroll: true }); },
    'rm-row': el => { F.state.rows.splice(+el.dataset.i, 1); App.render({ keepScroll: true }); },
    'add-additional': () => { F.state.rows[0].additional = [...(F.state.rows[0].additional || []), {}]; App.render({ keepScroll: true }); },
    'rm-add': el => { F.state.rows[0].additional.splice(+el.dataset.j, 1); App.render({ keepScroll: true }); },
    gps: el => { const r = F.state.rows[+el.dataset.i];
      if (r.gps_miles) { delete r.gps_miles; r.capture = 'manual'; }
      else { r.gps_miles = Math.round((4 + Math.random() * 22) * 10) / 10; r.capture = 'gps'; App.toast('Simulated GPS trip recorded.'); }
      App.render({ keepScroll: true }); },
    'scan-receipt': el => { const i = +el.dataset.i, s = SAMPLE_RECEIPTS[Math.floor(Math.random() * SAMPLE_RECEIPTS.length)];
      const cat = App.T.expenseCategories.find(c => c.group === s.group_id && c.id.endsWith('.' + s.cat)) || App.T.expenseCategories.find(c => c.group === s.group_id);
      Object.assign(F.state.rows[i], { vendor: s.vendor, amount: s.amount, group_id: s.group_id, category_id: cat ? cat.id : '', purpose: s.purpose || '',
        with_whom: s.with_whom || '', has_receipt: 1, capture: 'receipt', relationship_sub_pillar: s.group_id === 'relationships' ? 'professional' : '',
        _auto: ['vendor', 'amount', 'group_id', 'category_id', 'purpose', 'with_whom', 'relationship_sub_pillar'] });
      App.toast(`HERB read the receipt: ${s.vendor} $${s.amount.toFixed(2)} (simulated).`); App.render({ keepScroll: true }); },
    'scan-card': () => { Object.assign(F.state.rows[0], { last_name: 'Nguyen', first_names: 'Alicia', phone1: '(940) 555-0182', email1: 'alicia.nguyen@example.com',
        zip: '76205', city: 'Denton', state: 'TX', capture: 'manual', _auto: ['last_name', 'first_names', 'phone1', 'email1', 'zip'] });
      App.toast('Business card read (simulated).'); App.render({ keepScroll: true }); },
    cheat: () => App.push('cheat'),
    save: () => save(false),
    'save-next': () => save(true),
    delete: async () => {
      if (!confirm('Delete this entry?')) return;
      await App.api(`/api/${F.state.log}/${F.state.id}`, { method: 'DELETE' });
      App.toast('Deleted.'); App.pop(); App.refreshBadges();
    },
  };

  function validate() {
    const s = F.state, e = {};
    const need = (r, keys) => keys.forEach(k => { if (r[k] === '' || r[k] === undefined || r[k] === null) e[k] = true; });
    s.rows.forEach(r => {
      if (s.log === 'prospects') need(r, ['last_name', 'pillar', 'category_id', 'source', 'activity_id']);
      if (s.log === 'closings') { need(r, ['prospect_id', 'pillar', 'category_id', 'source', 'activity_id', 'transaction_size', 'income']); if (r.prospect_id === 'new') need(r, ['last_name']); }
      if (s.log === 'income') { need(r, ['amount']); if (r.mode !== 'transaction') need(r, ['type']); if (r.mode === 'batch') need(r, ['transaction_count']); }
      if (s.log === 'expenses') { need(r, ['date', 'vendor', 'amount', 'group_id', 'category_id']); if (r.group_id === 'relationships') need(r, ['relationship_sub_pillar']); }
      if (s.log === 'trips') { need(r, ['date', 'reason', 'destination']); if (!r.gps_miles && !(r.odometer_end > r.odometer_start)) e.odometer_end = true; }
      if (s.log === 'activities') need(r, ['date', 'pillar', 'activity_id', 'minutes']);
    });
    s.errors = e;
    return !Object.keys(e).length;
  }

  function payload(r) {
    const o = {};
    for (const [k, v] of Object.entries(r)) if (!k.startsWith('_') && k !== 'follow_up_days' && v !== '' && v !== undefined) o[k] = v;
    if (F.state.log === 'closings') {
      if (o.prospect_id === 'new') delete o.prospect_id; else o.prospect_id = Number(o.prospect_id);
      o.addToIncome = !!r.add_to_income; delete o.add_to_income;
      o.additionalTransactions = (r.additional || []).filter(a => a.income).map(a => ({ transactionSize: Number(a.transaction_size || 0), income: Number(a.income) }));
      delete o.additional;
    }
    if (F.state.log === 'income' && o.closing_id) o.closing_id = Number(o.closing_id);
    if (F.state.log === 'activities') o.minutes = Number(o.minutes);
    if ('is_business' in o) o.is_business = o.is_business ? 1 : 0;
    if ('expect_1099' in o) o.expect_1099 = o.expect_1099 ? 1 : 0;
    return o;
  }

  async function save(next) {
    if (!validate()) { App.render({ keepScroll: true }); return; }
    const s = F.state;
    try {
      if (s.id) await App.api(`/api/${s.log}/${s.id}`, { method: 'PUT', body: payload(s.rows[0]) });
      else {
        const body = s.meta.multi ? s.rows.map(payload) : payload(s.rows[0]);
        await App.api(`/api/${s.log}`, { method: 'POST', body: s.meta.multi && body.length === 1 ? body[0] : body });
      }
      App.toast(`${s.meta.title}${s.rows.length > 1 ? ` ×${s.rows.length}` : ''} saved.`);
      App.cache.vendors = null;
      App.refreshBadges();
      if (next) { F.state = { ...s, id: null, rows: [blank(s.log)], errors: {} }; App.render(); }
      else App.pop();
    } catch (e) { App.toast('Could not save: ' + e.message); }
  }

  // ---------- Account (no card fields — Apple In-App Purchase) ----------
  F.accountHtml = function (a) {
    const sub = a.subscription || {};
    const prof = (App.T.picklists.professions || []).map(opt);
    const times = []; for (let h = 6; h <= 22; h++) for (const m of ['00', '30']) times.push({ id: `${String(h).padStart(2, '0')}:${m}`, name: `${((h + 11) % 12) + 1}:${m} ${h < 12 ? 'AM' : 'PM'}` });
    const r = a; F.state = { log: 'account', rows: [r], errors: {} };
    return `<div class="form-h"><span>You</span></div><div class="form">
      ${f('Name', input(r, 0, 'name'), { req: true })}${f('Title', input(r, 0, 'title'))}${f('Email', input(r, 0, 'email', 'email'))}
      ${f('Company', input(r, 0, 'company'))}${f('Phone', input(r, 0, 'phone', 'tel'))}
      ${f('Profession', select(r, 0, 'profession', prof))}
      ${f('Address', input(r, 0, 'address'))}${f('Zip', input(r, 0, 'zip'))}
      ${f('City & state', `<input data-k="city" data-i="0" value="${esc(r.city || '')}"><input data-k="state" data-i="0" value="${esc(r.state || '')}" style="flex:none;width:36px">`)}
      ${f('Daily reminder', select(r, 0, 'reminderTime', times))}
      </div>
      <div class="form-h"><span>Subscription</span></div>
      <div class="card">
        <div class="row"><b>${a.plan === 'annual' ? 'Annual · $500/year' : 'Monthly · $50/month'}</b><span class="spacer"></span><span class="chip c-green">${esc(sub.status || 'active')}</span></div>
        <div class="note mt8">Billed through ${esc(sub.via || 'Apple In-App Purchase (simulated)')}${sub.renews ? ' · renews ' + esc(sub.renews) : ''}.
          Logsperity never sees or stores card numbers — Apple handles payment, renewal and refunds.</div>
        <div class="seg mt12"><button type="button" data-act="plan-pick" data-v="monthly" class="${a.plan !== 'annual' ? 'on' : ''}">Monthly $50</button>
          <button type="button" data-act="plan-pick" data-v="annual" class="${a.plan === 'annual' ? 'on' : ''}">Annual $500 · save 20%</button></div>
        <button class="btn ghost mt8" data-act="manage-sub">Manage subscription in Settings</button>
      </div>
      <button class="btn primary mt12" data-act="account-save">Save</button>`;
  };
  F.acts['plan-pick'] = el => { F.state.rows[0].plan = el.dataset.v; App.toast(`Simulated Apple purchase sheet: switch to ${el.dataset.v} plan. Confirmed.`); App.render({ keepScroll: true }); };
  F.acts['manage-sub'] = () => App.toast('On the iPhone this opens Settings › Apple ID › Subscriptions.');
  F.acts['account-save'] = async () => { const r = { ...F.state.rows[0] }; delete r.subscription;
    await App.api('/api/account', { method: 'PUT', body: r }); App.toast('Account saved.'); App.account = null; App.pop(); };

  // ---------- Business Plan Set Up ----------
  F.planHtml = function (p) {
    const r = { ...p.inputs }; F.state = { log: 'plan', rows: [r], errors: {}, year: p.year };
    const o = p.outputs || {}, x = p.extended || {};
    const m = v => W.fmt(v, 'money0'), n = (v, d = 1) => (v == null ? '—' : Number(v).toFixed(d));
    const out = (label, v) => `<div class="field"><span>${esc(label)}</span><b>${v}</b></div>`;
    return `<div class="sub" style="margin-bottom:6px">Plan year ${esc(p.year)}</div>
      <div class="form-h"><span>Your goals</span></div><div class="form">
      ${f('Annual gross income', input(r, 0, 'grossIncomeGoal', 'number', 'step="1000"'), { req: true })}
      ${f('Annual net profit', input(r, 0, 'netProfitGoal', 'number', 'step="1000"'), { req: true })}
      ${f('Avg commission / deal', input(r, 0, 'avgCommission', 'number', 'step="100"'), { req: true })}
      ${f('Avg transaction size', input(r, 0, 'avgTransactionSize', 'number', 'step="5000"'), { req: true })}
      ${f('Hours per week', input(r, 0, 'hoursPerWeek', 'number'), { req: true })}
      ${f('Weeks of vacation', input(r, 0, 'vacationWeeks', 'number'), { req: true })}
      </div>
      <button class="btn primary mt12" data-act="plan-save">Recalculate &amp; save</button>
      <div class="form-h"><span>This is your business</span></div><div class="card">
      ${out('Monthly gross income', m(o.monthlyGross))}${out('Monthly net profit', m(o.monthlyNet))}
      ${out('Annual projected expenses', m(o.annualExpenses))}${out('Monthly projected expenses', m(o.monthlyExpenses))}
      ${out('Your % yield per transaction', o.yieldPct != null ? (o.yieldPct * 100).toFixed(2) + '%' : '—')}
      ${out('Transactions needed / year', n(o.annualTransactions))}${out('Transactions needed / month', n(o.monthlyTransactions, 2))}
      ${out('Volume needed / year', m(o.annualVolume))}${out('Volume needed / month', m(o.monthlyVolume))}
      ${out('Projected work hours / year', n(o.annualWorkHours, 0))}
      ${out('Anticipated hourly rate (gross)', W.fmt(o.hourlyGross, 'money'))}${out('Anticipated hourly rate (net)', W.fmt(o.hourlyNet, 'money'))}
      </div>
      <div class="form-h"><span>HERB works it back further (your actual rates)</span></div><div class="card">
      ${out('Your conversion rate', x.conversion != null ? W.fmt(x.conversion, 'pct') : '—')}
      ${out('Prospects needed / year', n(x.prospectsNeeded))}${out('Prospects needed / week', n(x.prospectsPerWeek))}
      ${out('Hours per prospect', n(x.hoursPerProspect, 2))}
      ${out('Business-building hours / year', n(x.bbHoursNeeded, 0))}${out('Business-building hours / week', n(x.bbHoursPerWeek))}
      </div>`;
  };
  F.acts['plan-save'] = async () => {
    const r = F.state.rows[0];
    const body = Object.fromEntries(Object.entries(r).map(([k, v]) => [k, Number(v)]));
    App.plan = await App.api('/api/plan?year=' + F.state.year, { method: 'PUT', body });
    App.toast('Business plan saved.'); App.render({ keepScroll: true });
  };

  F.LOGS = LOGS;
  window.F = F;
})();
