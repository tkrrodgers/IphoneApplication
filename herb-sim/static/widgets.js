/* Widget renderer — turns report/coach widget JSON (CONTRACT.md "Widget JSON") into HTML.
   Visual style follows the 2018 Annual Report sample: blue header bars, serif big numbers with the
   formula underneath, taupe bars, periwinkle/orange donuts. */
(function () {
  const PALETTE = ['#5b6bbf', '#f7a35c', '#8ee8e0', '#b5aca5', '#12806a', '#c98a12', '#6b4bd8', '#c2412d', '#2c5fd6', '#7b8798'];

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }

  function fmt(v, format) {
    if (v === null || v === undefined || v === '') return '—';
    if (typeof v === 'string') return v;
    switch (format) {
      case 'money': return '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      case 'money0': return (v < 0 ? '−$' : '$') + Math.abs(Math.round(v)).toLocaleString('en-US');
      case 'pct': return (v * 100).toFixed(1).replace(/\.0$/, '') + '%';
      case 'num1': return v.toLocaleString('en-US', { maximumFractionDigits: 1 });
      case 'hours': return v.toLocaleString('en-US', { maximumFractionDigits: 1 }) + ' h';
      case 'miles': return Math.round(v).toLocaleString('en-US') + ' mi';
      case 'num': return Math.round(v * 100) / 100 === Math.round(v) ? Math.round(v).toLocaleString('en-US') : v.toLocaleString('en-US', { maximumFractionDigits: 2 });
      default: return typeof v === 'number' ? v.toLocaleString('en-US', { maximumFractionDigits: 2 }) : String(v);
    }
  }

  const shell = (w, body) => `<div class="w">${w.title ? `<div class="w-h">${esc(w.title)}</div>` : ''}<div class="w-b">${body}</div></div>`;
  const disp = (it, key = 'display', vkey = 'value', format) => esc(it[key] ?? fmt(it[vkey], format));

  function stat(w) {
    return shell(w, `<div class="big">${disp(w, 'display', 'value', w.format)}</div>
      ${w.caption ? `<div class="cap">${esc(w.caption)}</div>` : ''}
      ${w.formula ? `<div class="formula">(${esc(w.formula)})</div>` : ''}`);
  }

  function stats(w) {
    return shell(w, `<div class="stats">${(w.items || []).map(it => `<div>
      <div class="big">${disp(it, 'display', 'value', it.format)}</div>
      <div class="cap">${esc(it.label || '')}${it.caption ? ' · ' + esc(it.caption) : ''}</div>
      ${it.formula ? `<div class="formula">(${esc(it.formula)})</div>` : ''}</div>`).join('')}</div>`);
  }

  function table(w) {
    const cols = w.columns || [];
    const cell = (row, c) => {
      const v = row[c.key];
      const shown = row[c.key + 'Display'] ?? (typeof v === 'number' ? fmt(v, c.format) : v);
      return `<td class="${c.align === 'right' || (typeof v === 'number') ? 'r' : ''}">${esc(shown ?? '')}</td>`;
    };
    const rows = (w.rows || []);
    if (!rows.length) return shell(w, `<div class="empty">No entries for this period.</div>`);
    return shell(w, `<div class="tblwrap"><table class="tbl">
      <thead><tr>${cols.map(c => `<th class="${c.align === 'right' ? 'r' : ''}">${esc(c.label)}</th>`).join('')}</tr></thead>
      <tbody>${rows.map(r => `<tr>${cols.map(c => cell(r, c)).join('')}</tr>`).join('')}</tbody>
      ${w.total ? `<tfoot><tr>${cols.map(c => cell(w.total, c)).join('')}</tr></tfoot>` : ''}
    </table></div>${w.note ? `<div class="note mt8">${esc(w.note)}</div>` : ''}`);
  }

  function bar(w) {
    const items = w.items || [];
    if (!items.length) return shell(w, `<div class="empty">Nothing to chart yet.</div>`);
    const max = Math.max(...items.map(i => Math.abs(i.value) || 0), 1e-9);
    return shell(w, items.map(it => `<div class="hbar"><span class="l" title="${esc(it.label)}">${esc(it.label)}</span>
      <span class="b"><i style="width:${Math.max(1, Math.abs(it.value) / max * 100)}%;${it.value < 0 ? 'background:#c2412d' : ''}"></i></span>
      <span class="v">${disp(it, 'display', 'value', w.format)}</span></div>`).join(''));
  }

  function columns(w) {
    const items = w.items || [], series = w.series || [];
    if (!items.length) return shell(w, `<div class="empty">Nothing to chart yet.</div>`);
    // each series normalised to its own max so hours, counts and dollars share one chart
    const maxes = series.map((_, s) => Math.max(...items.map(i => Math.abs((i.values || [])[s]) || 0), 1e-9));
    const H = 110, bw = 6, gap = 2, groupW = series.length * (bw + gap) + 6;
    const width = Math.max(300, items.length * groupW + 10);
    let svg = `<svg width="100%" viewBox="0 0 ${width} ${H + 18}" preserveAspectRatio="none" style="height:${H + 18}px">`;
    items.forEach((it, i) => {
      series.forEach((_, s) => {
        const v = Math.abs((it.values || [])[s]) || 0, h = v / maxes[s] * H;
        const x = 6 + i * groupW + s * (bw + gap);
        svg += `<rect x="${x}" y="${H - h}" width="${bw}" height="${h}" fill="${PALETTE[s % PALETTE.length]}"><title>${esc(it.label)} · ${esc(series[s].name)}: ${esc((it.displays || [])[s] ?? v)}</title></rect>`;
      });
      svg += `<text x="${6 + i * groupW + (groupW - 6) / 2}" y="${H + 13}" font-size="9" text-anchor="middle" fill="#7b8798">${esc(it.label)}</text>`;
    });
    svg += `<line x1="0" x2="${width}" y1="${H}" y2="${H}" stroke="#2457a8" stroke-width="1"/></svg>`;
    const legend = `<div class="legend">${series.map((s, i) => `<span><i style="background:${PALETTE[i % PALETTE.length]}"></i>${esc(s.name)}</span>`).join('')}</div>`;
    return shell(w, svg + legend + `<div class="note">Each series is scaled to its own maximum; hover a bar for its value.</div>`);
  }

  function pie(w, donut) {
    const items = (w.items || []).filter(i => (i.value || 0) > 0);
    if (!items.length) return shell(w, `<div class="empty">Nothing to chart yet.</div>`);
    const total = items.reduce((a, b) => a + b.value, 0);
    const R = 52, r = donut ? 32 : 0, cx = 60, cy = 60;
    let a0 = -Math.PI / 2, paths = '';
    items.forEach((it, i) => {
      const frac = it.value / total, a1 = a0 + frac * Math.PI * 2, large = frac > 0.5 ? 1 : 0;
      const p = (rad, ang) => [cx + rad * Math.cos(ang), cy + rad * Math.sin(ang)];
      const color = PALETTE[i % PALETTE.length];
      if (frac >= 0.9999) {
        paths += `<circle cx="${cx}" cy="${cy}" r="${R}" fill="${color}"/>`;
      } else {
        const [x1, y1] = p(R, a0), [x2, y2] = p(R, a1);
        if (donut) {
          const [x3, y3] = p(r, a1), [x4, y4] = p(r, a0);
          paths += `<path d="M${x1},${y1} A${R},${R} 0 ${large} 1 ${x2},${y2} L${x3},${y3} A${r},${r} 0 ${large} 0 ${x4},${y4} Z" fill="${color}"/>`;
        } else {
          paths += `<path d="M${cx},${cy} L${x1},${y1} A${R},${R} 0 ${large} 1 ${x2},${y2} Z" fill="${color}"/>`;
        }
      }
      a0 = a1;
    });
    if (donut) paths += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="#fff"/>` +
      (w.center ? `<text x="${cx}" y="${cy + 6}" text-anchor="middle" font-family="Georgia,serif" font-size="17" fill="#1d2533">${esc(w.center)}</text>` : '');
    const legend = items.map((it, i) => `<span><i style="background:${PALETTE[i % PALETTE.length]}"></i>${esc(it.label)} · ${disp(it, 'display', 'value', w.format)}</span>`).join('');
    return shell(w, `<div class="row" style="align-items:center"><svg width="120" height="120" viewBox="0 0 120 120" style="flex:none">${paths}</svg>
      <div class="legend" style="flex-direction:column;gap:5px">${legend}</div></div>`);
  }

  function stack(w) {
    const items = w.items || [];
    const total = items.reduce((a, b) => a + Math.max(0, b.value || 0), 0) || 1;
    const color = it => it.role === 'profit' ? 'var(--rep-teal)' : it.role === 'expense' ? 'var(--rep-orange)' : 'var(--rep-taupe)';
    return shell(w, `<div style="display:flex;height:34px;border-radius:6px;overflow:hidden">${items.map(it =>
      `<div title="${esc(it.label)}" style="width:${Math.max(0, it.value) / total * 100}%;background:${color(it)};display:grid;place-items:center;font-size:11px;font-weight:700;color:#1d2533">${Math.round(Math.max(0, it.value) / total * 100)}%</div>`).join('')}</div>
      <div class="legend">${items.map(it => `<span><i style="background:${color(it)}"></i>${esc(it.label)} · ${disp(it, 'display', 'value', 'money0')}</span>`).join('')}</div>`);
  }

  function progress(w) {
    return shell(w, (w.items || []).map(it => {
      const goal = it.goal || 0, actual = it.actual || 0, proj = it.projected || 0;
      const pctGoal = goal ? Math.min(100, actual / goal * 100) : 0;
      const mark = goal ? Math.min(100, proj / goal * 100) : 0;
      const behind = proj && actual < proj * 0.95;
      const pace = it.pct ?? (proj ? actual / proj : null);
      return `<div class="prog"><div class="top"><b>${esc(it.label)}</b><span>${esc(it.displayActual ?? fmt(actual))} <span class="muted">of ${esc(it.displayGoal ?? fmt(goal))}</span></span></div>
        <div class="track"><div class="fill ${behind ? 'behind' : ''}" style="width:${pctGoal}%"></div><div class="mark" style="left:${mark}%" title="Projected to date"></div></div>
        <div class="bot"><span>Projected to date: ${esc(it.displayProjected ?? fmt(proj))}</span><span>${pace != null ? fmt(pace, 'pct') + ' of pace' : ''}</span></div></div>`;
    }).join('') + `<div class="note">The black tick marks where you should be today.</div>`);
  }

  function gaugeSvg(value, size = 210) {
    // 0–200 scale; 100 = healthy baseline
    const v = Math.max(0, Math.min(200, Number(value) || 0));
    const cx = size / 2, cy = size * 0.58, R = size * 0.42;
    const ang = a => Math.PI + (a / 200) * Math.PI;
    const pt = (a, rad = R) => [cx + rad * Math.cos(ang(a)), cy + rad * Math.sin(ang(a))];
    const arc = (a0, a1, color) => { const [x0, y0] = pt(a0), [x1, y1] = pt(a1); return `<path d="M${x0},${y0} A${R},${R} 0 0 1 ${x1},${y1}" stroke="${color}" stroke-width="16" fill="none"/>`; };
    const [nx, ny] = pt(v, R - 22);
    return `<svg class="gauge" width="${size}" height="${size * 0.84}" viewBox="0 0 ${size} ${size * 0.84}">
      ${arc(0, 80, '#f3c6bd')}${arc(80, 100, '#f6dfb0')}${arc(100, 150, '#bfe6d9')}${arc(150, 200, '#8fd3bd')}
      <line x1="${cx}" y1="${cy}" x2="${nx}" y2="${ny}" stroke="#1d2533" stroke-width="3" stroke-linecap="round"/>
      <circle cx="${cx}" cy="${cy}" r="6" fill="#1d2533"/>
      <text x="${cx}" y="${cy + 40}" text-anchor="middle" font-family="Georgia,serif" font-size="32" fill="#1d2533">${esc(Math.round(Number(value) || 0))}</text>
      <text x="${pt(0)[0] + 4}" y="${cy + 16}" font-size="10" fill="#7b8798">0</text>
      <text x="${cx}" y="${cy - R - 6}" font-size="10" fill="#7b8798" text-anchor="middle">100 = healthy</text>
      <text x="${pt(200)[0] - 16}" y="${cy + 16}" font-size="10" fill="#7b8798">200</text></svg>`;
  }

  function index(w) {
    const drivers = (w.drivers || []).map(d => `<span>${esc(d.label)}</span><b>${esc(d.display)} <span class="muted small">vs ${esc(d.benchmarkDisplay)}</span></b>
      <div class="bar"><i style="width:${Math.min(100, (d.ratio || 0) * 50)}%"></i></div>`).join('');
    return shell(w, gaugeSvg(w.value) + `<div class="center sub">${esc(w.label || '')}</div><div class="drv">${drivers}</div>
      <div class="note">Bars: each driver against its healthy benchmark (half-way = benchmark).</div>`);
  }

  const text = w => shell(w, (w.paragraphs || []).map(p => `<p style="font-size:13px;line-height:1.5;margin:4px 0">${esc(p)}</p>`).join(''));
  const list = w => shell(w, (w.items || []).map(it => `<div class="insight ${esc(it.level || '')}" style="box-shadow:none;margin-bottom:6px">
      ${it.title ? `<div class="k">${esc(it.title)}</div>` : ''}${esc(it.text || '')}</div>`).join('') || '<div class="empty">Nothing to report.</div>');

  const RENDER = { stat, stats, table, bar, pie: w => pie(w, false), donut: w => pie(w, true), stack, progress, index, text, list, columns };

  function render(widgets) {
    return (widgets || []).map(w => {
      const fn = RENDER[w.type];
      try { return fn ? fn(w) : shell(w, `<pre class="small">${esc(JSON.stringify(w, null, 1))}</pre>`); }
      catch (e) { console.error('widget failed', w, e); return shell(w, `<div class="empty">Couldn't draw this widget.</div>`); }
    }).join('');
  }

  // Plain-text version of widgets, used for "email this report"
  function toText(widgets) {
    const out = [];
    for (const w of widgets || []) {
      if (w.title) out.push('', w.title.toUpperCase());
      if (w.type === 'stat') out.push(`${w.display ?? fmt(w.value)}${w.caption ? ' — ' + w.caption : ''}`);
      else if (w.type === 'stats' || w.type === 'bar' || w.type === 'pie' || w.type === 'donut' || w.type === 'stack')
        (w.items || []).forEach(i => out.push(`${i.label}: ${i.display ?? fmt(i.value)}`));
      else if (w.type === 'progress') (w.items || []).forEach(i => out.push(`${i.label}: ${i.displayActual} of ${i.displayGoal} (projected ${i.displayProjected})`));
      else if (w.type === 'index') out.push(`Index ${w.display ?? w.value}`);
      else if (w.type === 'text') out.push(...(w.paragraphs || []));
      else if (w.type === 'list') (w.items || []).forEach(i => out.push(`- ${i.title ? i.title + ': ' : ''}${i.text}`));
      else if (w.type === 'table') (w.rows || []).slice(0, 15).forEach(r => out.push((w.columns || []).map(c => r[c.key + 'Display'] ?? fmt(r[c.key], c.format)).join(' | ')));
    }
    return out.join('\n').trim();
  }

  window.W = { render, toText, esc, fmt, gaugeSvg, PALETTE };
})();
