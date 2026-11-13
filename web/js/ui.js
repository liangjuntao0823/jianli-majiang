/* 牌桌渲染 + 输入 */
import { tileImage, tileSrc, label, RED_RAW, SEAT_LABEL } from './tiles.js';

export const G = {
  getState: null,
  humanSeat: 0,
  selected: null,      // { raw, drawn }
  onDiscard: null,
  onAct: null,
  onNext: null,
  onExit: null,
  getMyActions: null,
  getPendingOptions: null,
  mode: 'single',
  totalRounds: 8,
  timerFill: null,
};

const st = () => G.getState();

const POS = ['bottom', 'right', 'top', 'left'];
const posOf = (seat) => POS[(seat - G.humanSeat + 4) % 4];

function el(tag, cls, text) {
  const d = document.createElement(tag);
  if (cls) d.className = cls;
  if (text !== undefined) d.textContent = text;
  return d;
}

function tileEl(raw, { cls = '', onClick = null } = {}) {
  const d = el('div', ('tile ' + cls).trim());
  const img = el('img');
  img.src = tileSrc(raw);
  img.alt = label(raw);
  img.draggable = false;
  d.appendChild(img);
  if (onClick) {
    d.classList.add('clickable');
    d.onclick = onClick;
  }
  return d;
}

export function initTable(opts) {
  Object.assign(G, opts);
  G.selected = null;
  G.timerFill = null;
  document.getElementById('home').classList.add('hidden');
  document.getElementById('table').classList.add('show');
  document.getElementById('result').classList.remove('show');
  document.getElementById('toast').innerHTML = '';
  const exit = document.getElementById('btn-exit');
  exit.onclick = () => { if (G.onExit) G.onExit(); };
}

export function backToHome() {
  document.getElementById('home').classList.remove('hidden');
  document.getElementById('table').classList.remove('show');
  document.getElementById('result').classList.remove('show');
}

/* ---------------- 主渲染 ---------------- */

export function renderAll() {
  const s = st();
  G.timerFill = null;
  for (let seat = 0; seat < 4; seat++) {
    renderSeat(seat);
    renderRiver(seat);
  }
  renderCore();
  renderActions();
}

function renderSeat(seat) {
  const s = st();
  const p = s.players[seat];
  const pos = posOf(seat);
  const box = document.getElementById('seat-' + pos);
  box.innerHTML = '';

  const info = el('div', 'info' + (s.current === seat && s.phase !== 'finished' ? ' active' : ''));
  const row1 = el('div', 'row1');
  row1.append(el('span', 'wind', SEAT_LABEL[seat]), el('span', 'name', p.name));
  if (p.isBot) row1.append(el('span', 'tag', '机器人'));
  if (seat === s.dealer) row1.append(el('span', 'tag dealer', '庄'));
  if (p.redsPlayed > 0) row1.append(el('span', 'tag red', '皮 ' + p.redsPlayed));
  const row2 = el('div', 'row2');
  const score = el('span', 'score ' + (p.score > 0 ? 'pos' : p.score < 0 ? 'neg' : ''), (p.score > 0 ? '+' : '') + p.score);
  row2.append(score);
  info.append(row1, row2);

  const track = el('div', 'timer-track');
  const fill = el('div', 'timer-fill');
  fill.style.width = '0%';
  track.append(fill);
  info.append(track);
  if (s.current === seat && s.phase !== 'finished') G.timerFill = fill;

  box.append(info);

  if (pos === 'bottom') {
    renderMyMeld(box, seat);
    renderMyHand(box, seat);
  } else {
    renderOppHand(box, seat);
  }
}

function renderMyMeld(box, seat) {
  const p = st().players[seat];
  const zone = el('div', 'meld-zone');
  for (const m of p.melds) {
    const g = el('div', 'meld-group');
    const n = m.kind === 'peng' ? 3 : 4;
    for (let i = 0; i < n; i++) g.append(tileEl(m.tile, { cls: 'meld' }));
    zone.append(g);
  }
  const rz = el('div', 'red-zone');
  rz.append(el('span', 'lbl', '皮子'));
  if (p.redsPlayed > 0) {
    for (let i = 0; i < p.redsPlayed; i++) rz.append(tileEl(RED_RAW, { cls: 'red-mark' }));
  } else {
    rz.append(el('span', 'empty', '—'));
  }
  zone.append(rz);
  box.append(zone);
}

function renderMyHand(box, seat) {
  const s = st();
  const p = s.players[seat];
  const zone = el('div', 'hand-zone');

  const canPlay = seat === G.humanSeat && s.phase === 'awaitingDiscard' && s.current === seat && G.onDiscard !== null;
  const showDrawn = s.current === seat && s.phase === 'awaitingDiscard' && s.lastDrawn !== null;

  let hand = p.hand.slice().sort((a, b) => a - b);
  let drawn = null;
  if (showDrawn) {
    const idx = hand.indexOf(s.lastDrawn);
    if (idx >= 0) { hand.splice(idx, 1); drawn = s.lastDrawn; }
  }

  for (const raw of hand) {
    const t = tileEl(raw, canPlay ? { onClick: () => onTileClick(raw, false) } : {});
    if (canPlay && G.selected && G.selected.raw === raw && !G.selected.drawn) t.classList.add('selected');
    zone.append(t);
  }
  if (drawn !== null) {
    const t = tileEl(drawn, { cls: 'drawn', onClick: canPlay ? () => onTileClick(drawn, true) : null });
    if (canPlay && G.selected && G.selected.raw === drawn && G.selected.drawn) t.classList.add('selected');
    zone.append(t);
  }
  box.append(zone);
}

function onTileClick(raw, drawn) {
  const s = st();
  if (!(s.phase === 'awaitingDiscard' && s.current === G.humanSeat)) return;
  if (G.selected && G.selected.raw === raw && !!G.selected.drawn === !!drawn) {
    G.selected = null;
    G.onDiscard(raw);
  } else {
    G.selected = { raw, drawn: !!drawn };
    renderAll();
  }
}

function renderOppHand(box, seat) {
  const p = st().players[seat];
  const zone = el('div', 'opp-hand');
  const pos = posOf(seat);
  const n = p.handCount !== undefined ? p.handCount : p.hand.length;
  for (let i = 0; i < n; i++) zone.append(el('div', 'tile hand-back'));
  box.append(zone);

  if (p.melds.length > 0) {
    const row = el('div', 'meld-row');
    for (const m of p.melds) {
      const g = el('div', 'meld-group');
      const cnt = m.kind === 'peng' ? 3 : 4;
      for (let i = 0; i < cnt; i++) g.append(tileEl(m.tile, { cls: 'meld' }));
      row.append(g);
    }
    box.append(row);
  }
  // 对家/左右 的皮子数已在信息牌展示
}

function renderRiver(seat) {
  const s = st();
  const p = s.players[seat];
  const box = document.getElementById('river-' + posOf(seat));
  box.innerHTML = '';
  for (const raw of p.river) box.append(tileEl(raw, { cls: 'mini' }));
}

function renderCore() {
  const s = st();
  const core = document.getElementById('core');
  core.innerHTML = '';
  core.append(el('div', 'num', String(s.wall.remaining)));
  core.append(el('div', 'unit', '张'));
  const round = el('div', 'round');
  round.innerHTML = `${SEAT_LABEL[s.dealer]}庄 <b>${s.roundIndex}</b>/${G.totalRounds}`;
  core.append(round);
}

/* ---------------- 操作区 ---------------- */

function btn(text, onClick, cls = '') {
  const b = el('button', ('act-btn ' + cls).trim(), text);
  b.onclick = onClick;
  return b;
}

function setHint(text) {
  const h = document.getElementById('hint');
  if (!text) { h.classList.add('hidden'); return; }
  h.innerHTML = text;
  h.classList.remove('hidden');
}

function renderActions() {
  const s = st();
  const acts = document.getElementById('actions');
  acts.innerHTML = '';
  if (!s || s.phase === 'finished') { setHint(null); return; }

  const human = G.humanSeat;

  // 声明窗口（碰/杠/过）
  const pendingOpts = G.getPendingOptions ? G.getPendingOptions() : (s.pending && s.pending.options ? s.pending.options[human] : null);
  if (s.phase === 'awaitingClaim' && s.pending && pendingOpts) {
    const disc = s.players[s.pending.discarder];
    setHint(`<b>${disc.name}</b> 打出 ${label(s.pending.tile)}`);
    if (pendingOpts.includes('peng')) acts.append(btn('碰', () => G.onAct({ type: 'peng' })));
    if (pendingOpts.includes('gang')) acts.append(btn('杠', () => G.onAct({ type: 'gangExposed' })));
    acts.append(btn('过', () => G.onAct({ type: 'pass' })));
    return;
  }

  // 自己回合：胡 / 杠
  if (s.phase === 'awaitingDiscard' && s.current === human) {
    const opts = G.getMyActions ? G.getMyActions() : [];
    if (opts.some((o) => o.type === 'hu')) acts.append(btn('胡', () => G.onAct({ type: 'hu' }), 'hu'));
    for (const o of opts) {
      if (o.type === 'gangConcealed') acts.append(btn('暗杠 ' + label(o.tile), () => G.onAct(o)));
      if (o.type === 'gangAdded') acts.append(btn('蓄杠 ' + label(o.tile), () => G.onAct(o)));
    }
    setHint(G.selected ? '再点一次打出' : '点牌选中，再点打出');
    return;
  }

  // 等待
  if (s.phase === 'awaitingClaim') {
    setHint(`<b>${s.players[s.pending.discarder].name}</b> 打出 ${label(s.pending.tile)}，等待其他人`);
  } else if (s.phase === 'awaitingDiscard') {
    const cur = s.players[s.current];
    setHint(cur.isBot ? `<b>${cur.name}</b> 摸牌中` : `<b>${cur.name}</b> 出牌中`);
  } else {
    setHint(null);
  }
}

/* ---------------- 计时 / 提示 ---------------- */

export function updateTimer(ratio) {
  if (!G.timerFill) return;
  G.timerFill.style.width = Math.max(0, Math.min(1, ratio)) * 100 + '%';
  G.timerFill.classList.toggle('run', ratio < 0.35);
}

export function showToast(text, cls = '') {
  const box = document.getElementById('toast');
  const item = el('div', ('toast-item ' + cls).trim(), text);
  box.append(item);
  setTimeout(() => { item.style.opacity = '0'; item.style.transition = 'opacity .25s'; }, 1600);
  setTimeout(() => item.remove(), 2000);
}

export function clearToast() {
  document.getElementById('toast').innerHTML = '';
}

/* ---------------- 结算 ---------------- */

export function showResult({ title, subtitle, winnerSeat, hand, melds, payments, scores, names, reds, drawnGame }) {
  const card = document.getElementById('result-card');
  card.innerHTML = '';
  card.append(el('div', 'result-title', title));
  card.append(el('div', 'result-sub', subtitle));

  if ((hand && hand.length) || (melds && melds.length)) {
    const h = el('div', 'result-hand');
    if (melds) for (const m of melds) {
      const g = el('div', 'meld-group');
      const cnt = m.kind === 'peng' ? 3 : 4;
      for (let i = 0; i < cnt; i++) g.append(tileEl(m.tile, { cls: 'mini' }));
      h.append(g);
    }
    if (hand) for (const raw of hand) h.append(tileEl(raw, { cls: 'mini' }));
    card.append(h);
  }

  const table = el('table', 'result-table');
  const thead = el('thead');
  const hr = el('tr');
  for (const t of ['座位', '名字', '本局', reds ? '皮子' : '', '累计'].filter(Boolean)) hr.append(el('th', '', t));
  thead.append(hr);
  table.append(thead);
  const tbody = el('tbody');
  for (let seat = 0; seat < 4; seat++) {
    const tr = el('tr');
    tr.append(el('td', '', SEAT_LABEL[seat] + (seat === winnerSeat ? ' ★' : '')));
    tr.append(el('td', '', names[seat]));
    const pay = payments ? (payments[seat] !== undefined ? -payments[seat] : 0) : 0;
    tr.append(el('td', pay > 0 ? 'pos' : pay < 0 ? 'neg' : '', (pay > 0 ? '+' : '') + pay));
    if (reds) tr.append(el('td', '', reds[seat] > 0 ? reds[seat] + ' 张' : '—'));
    tr.append(el('td', scores[seat] > 0 ? 'pos' : scores[seat] < 0 ? 'neg' : '', (scores[seat] > 0 ? '+' : '') + scores[seat]));
    tbody.append(tr);
  }
  table.append(tbody);
  card.append(table);

  const actions = el('div', 'result-actions');
  const next = el('button', 'big-btn', '下一局');
  next.onclick = () => { document.getElementById('result').classList.remove('show'); if (G.onNext) G.onNext(); };
  actions.append(next);
  card.append(actions);

  document.getElementById('result').classList.add('show');
}

export function hideResult() {
  document.getElementById('result').classList.remove('show');
}
