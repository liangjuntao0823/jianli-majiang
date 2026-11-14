/* 牌桌渲染 + 输入 */
import { tileImage, tileSrc, label, RED_RAW, SEAT_LABEL } from './tiles.js';
import { waitingTiles } from './win.js';

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
  seatNames: null,
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
  d.setAttribute('aria-label', label(raw));
  const img = el('img');
  img.src = tileSrc(raw);
  img.alt = label(raw);
  img.draggable = false;
  img.onerror = () => { d.classList.add('no-art'); d.textContent = label(raw); };
  d.appendChild(img);
  if (onClick) {
    d.classList.add('clickable');
    d.onclick = onClick;
  }
  return d;
}

/* ---------- 全屏 ---------- */
function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
}
function applyFullscreenIcon() {
  const btn = document.getElementById('btn-full');
  if (!btn) return;
  const on = !!document.fullscreenElement || !!document.webkitFullscreenElement || isStandalone();
  btn.textContent = on ? '⛶' : '⛶';
  btn.title = on ? '退出全屏' : '全屏';
}
export function toggleFullscreen() {
  const el = document.documentElement;
  const req = el.requestFullscreen || el.webkitRequestFullscreen;
  if (isStandalone() || document.fullscreenElement) {
    if (document.exitFullscreen) document.exitFullscreen().catch(() => {});
    else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
    return;
  }
  if (req) {
    req.call(el).then(applyFullscreenIcon).catch(() => iosFullscreenTip());
  } else {
    iosFullscreenTip();
  }
}
let fullTipTimer = null;
function iosFullscreenTip() {
  showToast('iPhone 全屏：用 Safari 打开后点「分享」→「添加到主屏幕」，从桌面图标进入即可全屏', '', 6000);
}
function bindFullscreen() {
  const btn = document.getElementById('btn-full');
  if (btn) btn.addEventListener('click', toggleFullscreen);
  document.addEventListener('fullscreenchange', applyFullscreenIcon);
  document.addEventListener('webkitfullscreenchange', applyFullscreenIcon);
  applyFullscreenIcon();
}

/* 视口单位（竖屏时整屏旋转 90° 照样横屏玩） */
export function applyLayoutUnits() {
  const w = window.innerWidth, h = window.innerHeight;
  const portrait = h >= w;
  const root = document.documentElement;
  root.style.setProperty('--uv', (h / 100) + 'px');
  root.style.setProperty('--uh', (w / 100) + 'px');
  document.body.classList.toggle('rotated', portrait);
  const logicalH = portrait ? w : h;
  document.body.classList.toggle('short', logicalH < 560);
  document.body.classList.toggle('tiny', logicalH < 500);
}
export function bindLayout() {
  applyLayoutUnits();
  window.addEventListener('resize', applyLayoutUnits);
  window.addEventListener('orientationchange', () => setTimeout(applyLayoutUnits, 150));
}
bindLayout();

export function resetEventState() {
  meldSnap = {};
  lastPhase = null;
  wasTing = false;
  const box = document.getElementById('event');
  if (box) box.innerHTML = '';
}

export function initTable(opts) {
  Object.assign(G, opts);
  G.selected = null;
  G.timerFill = null;
  document.getElementById('home').classList.add('hidden');
  const tip = document.getElementById('home-tip');
  if (tip) tip.style.display = 'none';
  document.getElementById('table').classList.add('show');
  document.getElementById('result').classList.remove('show');
  document.getElementById('toast').innerHTML = '';
  const exit = document.getElementById('btn-exit');
  exit.onclick = () => { if (G.onExit) G.onExit(); };
  bindFullscreen();
  bindLayout();
}

export function backToHome() {
  const tip = document.getElementById('home-tip');
  if (tip) tip.style.display = '';
  document.getElementById('home').classList.remove('hidden');
  document.getElementById('table').classList.remove('show');
  document.getElementById('result').classList.remove('show');
}

/* ---------------- 中央大字事件 ---------------- */
const MELD_SAY = {
  peng: ['碰', '碰！'],
  gangExposed: ['杠', '明杠！'],
  gangConcealed: ['杠', '暗杠！'],
  gangAdded: ['回头笑', '回头笑！'],
};

function flashEvent(main, sub) {
  const box = document.getElementById('event');
  if (!box) return;
  box.innerHTML = '';
  const wrap = el('div', 'ev-box');
  wrap.append(el('div', 'ev-main', main));
  if (sub) wrap.append(el('div', 'ev-sub', sub));
  box.append(wrap);
  setTimeout(() => { if (box.firstChild === wrap) box.innerHTML = ''; }, 1100);
}

let meldSnap = {};
let lastPhase = null;
let wasTing = false;
function detectEvents(s) {
  if (!s) return;
  // 副露新增 → 大字
  for (let seat = 0; seat < 4; seat++) {
    const p = s.players[seat];
    const n = p.melds.length;
    const prev = meldSnap[seat] === undefined ? n : meldSnap[seat];
    if (n > prev) {
      const m = p.melds[n - 1];
      const say = MELD_SAY[m.kind];
      if (say) flashEvent(say[1], seat === G.humanSeat ? '' : (G.seatNames ? G.seatNames[seat] : ''));
    }
    meldSnap[seat] = n;
  }
  // 本局结束 → 胡 / 流局
  if (s.phase === 'finished' && lastPhase !== 'finished') {
    if (s.winner !== null && s.winner !== undefined) {
      const who = s.winner === G.humanSeat ? '你' : (G.seatNames ? G.seatNames[s.winner] : '');
      flashEvent('胡！', who ? who + ' 自摸' : '');
    } else {
      flashEvent('流局', '');
    }
  }
  lastPhase = s.phase;
  // 刚听牌 → 中央大字
  const myWaits = calcWaits(s.players[G.humanSeat]);
  const isTing = !!(myWaits && myWaits.mode === 'ting');
  if (isTing && !wasTing) flashEvent('听牌！', myWaits.waits.map(label).join(' '));
  wasTing = isTing;
}

/* ---------------- 主渲染 ---------------- */

export function renderAll() {
  const s = st();
  detectEvents(s);
  G.timerFill = null;
  for (let seat = 0; seat < 4; seat++) {
    renderSeat(seat);
    renderRiver(seat);
  }
  renderCore();
  renderActions();
  renderWaits();
}

function renderSeat(seat) {
  const s = st();
  const p = s.players[seat];
  const pos = posOf(seat);
  const box = document.getElementById('seat-' + pos);
  box.innerHTML = '';
  const slot = document.getElementById('info-' + pos);
  if (slot) slot.innerHTML = '';

  const info = el('div', 'info' + (s.current === seat && s.phase !== 'finished' ? ' active' : ''));
  const row1 = el('div', 'row1');
  row1.append(el('span', 'wind', SEAT_LABEL[seat]), el('span', 'name', p.name));
  if (s.current === seat && s.phase !== 'finished') row1.append(el('span', 'tag live', '出牌中'));
  if (p.isBot) row1.append(el('span', 'tag bot', '机器人'));
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

  if (slot) slot.append(info);

  if (pos === 'bottom') {
    renderMyMeld(box, seat);
    renderMyHand(box, seat);
  } else {
    renderOppHand(box, seat);
  }
}

/* 一组副露：碰 3 张明；杠 4 张，第 4 张压在右上角
 * 暗杠：下面 3 张暗的，上面 1 张明的
 * 回头笑（点杠）：下面 3 张明的，上面 1 张暗的
 * 蓄杠：4 张全明
 */
function meldGroupEl(m) {
  const g = el('div', 'meld-group' + (m.kind && m.kind.startsWith('gang') ? ' gang' : ''));
  const face = () => tileEl(m.tile, { cls: 'meld' });
  const back = () => el('div', 'tile hand-back meld');
  if (m.kind === 'gangConcealed') {
    g.append(back(), back(), back());
    const st4 = el('div', 'stack');
    st4.append(face());
    g.append(st4);
  } else if (m.kind === 'gangExposed') {
    g.append(face(), face(), face());
    const st4 = el('div', 'stack');
    st4.append(back());
    g.append(st4);
  } else if (m.kind === 'gangAdded') {
    g.append(face(), face(), face());
    const st4 = el('div', 'stack');
    st4.append(face());
    g.append(st4);
  } else {
    g.append(face(), face(), face());
  }
  return g;
}

/* 台面上的皮子（红中）——四家都看得到 */
function redZoneEl(p, small) {
  const rz = el('div', small ? 'red-zone small' : 'red-zone');
  if (p.redsPlayed > 0) {
    for (let i = 0; i < p.redsPlayed; i++) rz.append(tileEl(RED_RAW, { cls: small ? 'red-mark tiny' : 'red-mark' }));
  } else {
    rz.append(el('span', 'empty', '—'));
  }
  return rz;
}

function renderMyMeld(box, seat) {
  const p = st().players[seat];
  const zone = el('div', 'meld-zone');
  for (const m of p.melds) zone.append(meldGroupEl(m));
  const rz = redZoneEl(p, false);
  rz.insertBefore(el('span', 'lbl', '皮子'), rz.firstChild);
  zone.append(rz);
  box.append(zone);
}

function renderMyHand(box, seat) {
  const s = st();
  const p = s.players[seat];
  const zone = el('div', 'hand-zone');
  const myW = calcWaits(p);
  if (seat === G.humanSeat && myW && myW.mode === 'ting') zone.classList.add('ting-glow');

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

  if (p.melds.length > 0 || p.redsPlayed > 0) {
    const row = el('div', 'meld-row');
    for (const m of p.melds) row.append(meldGroupEl(m));
    if (p.redsPlayed > 0) row.append(redZoneEl(p, true));
    box.append(row);
  }
}

function renderRiver(seat) {
  const s = st();
  const p = s.players[seat];
  const box = document.getElementById('river-' + posOf(seat));
  box.innerHTML = '';
  const pendingSeat = s.phase === 'awaitingClaim' && s.pending ? s.pending.discarder : -1;
  if (!G.prevRiver) G.prevRiver = {};
  const prev = G.prevRiver[seat] || 0;
  p.river.forEach((raw, i) => {
    const t = tileEl(raw, { cls: 'mini' });
    if (seat === pendingSeat && i === p.river.length - 1) t.classList.add('raised');
    if (i === p.river.length - 1 && p.river.length > prev) t.classList.add('drop-in');
    box.append(t);
  });
  G.prevRiver[seat] = p.river.length;
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
  if (G.hintText) {
    const line = el('div', 'hint-line');
    line.innerHTML = G.hintText;
    core.append(line);
  }
}

/* ---------------- 操作区 ---------------- */

function btn(text, onClick, cls = '') {
  const b = el('button', ('act-btn ' + cls).trim(), text);
  b.onclick = onClick;
  return b;
}

function setHint(text) {
  G.hintText = text || null;
  const core = document.getElementById('core');
  if (!core) return;
  let line = core.querySelector('.hint-line');
  if (!text) { if (line) line.remove(); return; }
  if (!line) { line = el('div', 'hint-line'); core.append(line); }
  line.innerHTML = text;
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
    if (pendingOpts.includes('peng')) acts.append(btn('碰', () => G.onAct({ type: 'peng' }), 'peng'));
    if (pendingOpts.includes('gang')) acts.append(btn('杠', () => G.onAct({ type: 'gangExposed' }), 'gang'));
    acts.append(btn('过', () => G.onAct({ type: 'pass' }), 'pass'));
    return;
  }

  // 自己回合：胡 / 杠
  if (s.phase === 'awaitingDiscard' && s.current === human) {
    const opts = G.getMyActions ? G.getMyActions() : [];
    if (opts.some((o) => o.type === 'hu')) acts.append(btn('胡', () => G.onAct({ type: 'hu' }), 'hu'));
    for (const o of opts) {
      if (o.type === 'gangConcealed') acts.append(btn('暗杠 ' + label(o.tile), () => G.onAct(o), 'gang'));
      if (o.type === 'gangAdded') acts.append(btn('蓄杠 ' + label(o.tile), () => G.onAct(o), 'gang'));
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

/* ---------------- 听牌 ---------------- */
function calcWaits(p) {
  if (!p) return null;
  const hand = p.hand.slice();
  if (hand.some((t) => t === RED_RAW)) return null;
  const meldCount = p.melds.length;
  const rem = hand.length % 3;   // 1 = 等牌(3n+1)，2 = 已摸牌(3n+2)
  if (rem === 1) {
    const waits = waitingTiles(hand, meldCount);
    return waits.length ? { mode: 'ting', waits } : null;
  }
  if (rem === 2) {
    let best = null;
    for (const t of [...new Set(hand)]) {
      const rest = hand.slice();
      rest.splice(rest.indexOf(t), 1);
      const w = waitingTiles(rest, meldCount);
      if (w.length && (!best || w.length > best.waits.length)) best = { mode: 'discard', discard: t, waits: w };
    }
    return best;
  }
  return null;
}

function renderWaits() {
  const box = document.getElementById('waits');
  if (!box) return;
  const s = st();
  box.innerHTML = '';
  const p = s ? s.players[G.humanSeat] : null;
  const r = s && s.phase !== 'finished' ? calcWaits(p) : null;
  if (!r) { box.classList.remove('show'); return; }
  const core = document.getElementById('core');
  const badge = r.mode === 'ting' ? '已听牌' : '打 ' + label(r.discard) + ' 听';
  box.append(el('span', 'w-lbl ting', badge));
  for (const w of r.waits) box.append(el('span', 'w-tile', label(w)));
  box.classList.add('show');
  if (core) {
    const line = el('div', 'ting-line');
    line.append(el('span', 't-badge', badge));
    for (const w of r.waits) line.append(el('span', 't-tile', label(w)));
    core.append(line);
  }
}

/* ---------------- 计时 / 提示 ---------------- */

export function updateTimer(ratio) {
  if (!G.timerFill) return;
  G.timerFill.style.width = Math.max(0, Math.min(1, ratio)) * 100 + '%';
  G.timerFill.classList.toggle('run', ratio < 0.35);
}

export function showToast(text, cls = '', ms = 2000) {
  const box = document.getElementById('toast');
  const item = el('div', ('toast-item ' + cls).trim(), text);
  box.append(item);
  setTimeout(() => { item.style.opacity = '0'; item.style.transition = 'opacity .25s'; }, Math.max(600, ms - 400));
  setTimeout(() => item.remove(), ms);
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
