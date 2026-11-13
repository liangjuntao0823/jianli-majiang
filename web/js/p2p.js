/* 手机联机（P2P）：房主的浏览器当主机，其他人输房号通过 WebRTC 直连。
 * 不需要电脑、不需要服务器，四个人在同一个 WiFi 下就能打。
 */
import { Engine, DEFAULT_RULE } from './engine.js';
import { nextAction, discardCandidate } from './bot.js';
import { initTable, renderAll, updateTimer, showResult, hideResult, backToHome } from './ui.js';

const ROUNDS = 8;
const HOST_PREFIX = 'jianli-mj-';
const ICE = {
  iceServers: [
    { urls: 'stun:stun.miwifi.com:3478' },
    { urls: 'stun:stun.chat.bilibili.com:3478' },
    { urls: 'stun:stun.l.google.com:19302' },
  ],
};
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

const P = {
  role: null,          // 'host' | 'guest'
  code: '',
  name: '',
  seat: 0,
  peer: null,
  conns: [],           // host: [{ conn, seat }]
  players: [],         // host: [{ name, isBot, online }]
  engine: null,
  started: false,
  over: false,
  version: 0,
  deadline: null,
  lastKey: '',
  lastBotAt: 0,
  lastSentVersion: -1,
  snap: null,
  inGame: false,
  resultKey: '',
  lastPhase: '',
  lastStateVersion: -1,
  hostConn: null,
  loop: null,
  uiTimer: null,
  joinTimer: null,
};

const el = (id) => document.getElementById(id);
const status = (t) => { const s = el('lobby-status'); if (s) s.textContent = t; };

function makeCode() {
  let s = '';
  for (let i = 0; i < 6; i++) s += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  return s;
}

/* ---------------- 大厅 UI ---------------- */

function buildEntryUI() {
  el('lobby').classList.add('show');
  el('lobby-name-row').style.display = 'none';
  document.querySelector('.lobby-title').textContent = '手机联机';
  document.querySelector('.lobby-sub').textContent = '同一个 WiFi：一个人开房，其他人输 6 位房号加入';

  let box = el('p2p-box');
  if (!box) {
    box = document.createElement('div');
    box.id = 'p2p-box';
    const card = document.querySelector('.lobby-card');
    card.insertBefore(box, el('lobby-seats'));
  }
  box.innerHTML = `
    <div id="p2p-entry">
      <input id="p2p-name" maxlength="8" placeholder="你的名字" autocomplete="off">
      <button class="big-btn" id="p2p-create">创建房间</button>
      <div class="p2p-or">或者加入别人的房间</div>
      <div class="p2p-join-row">
        <input id="p2p-code" maxlength="6" placeholder="房号" autocomplete="off" spellcheck="false">
        <button class="big-btn ghost" id="p2p-join">加入</button>
      </div>
    </div>
    <div id="p2p-code-show" class="hidden"></div>
  `;
  el('p2p-name').value = P.name || localStorage.getItem('jianli_name') || '';
  el('p2p-create').onclick = () => createRoom();
  el('p2p-join').onclick = () => joinRoom();
  el('p2p-code').addEventListener('input', (e) => { e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); });
  el('lobby-actions').innerHTML = '';
  el('lobby-seats').innerHTML = '';
  status('');
}

function setEntryVisible(v) {
  const e = el('p2p-entry');
  if (e) e.style.display = v ? 'block' : 'none';
}

function readName() {
  const v = (el('p2p-name') && el('p2p-name').value.trim()) || '';
  const name = v.slice(0, 8) || ('玩家' + Math.floor(Math.random() * 90 + 10));
  P.name = name;
  localStorage.setItem('jianli_name', name);
  return name;
}

/* ---------------- 房主 ---------------- */

function createRoom() {
  if (!window.Peer) { status('联机组件没加载，刷新一下页面'); return; }
  const name = readName();
  P.role = 'host';
  P.seat = 0;
  P.players = [{ name, isBot: false, online: true }];
  P.version++;

  const tryBind = (attempt) => {
    P.code = makeCode();
    const peer = new Peer(HOST_PREFIX + P.code, { config: ICE, debug: 0 });
    P.peer = peer;
    peer.on('open', () => {
      setEntryVisible(false);
      showRoomCode();
      renderSeats();
      renderHostActions();
      status('把房号发给其他三个人，他们打开同一个页面输入房号');
      startHostLoop();
    });
    peer.on('error', (e) => {
      if (e && e.type === 'unavailable-id' && attempt < 5) { try { peer.destroy(); } catch {} ; tryBind(attempt + 1); return; }
      status('建房失败：' + errText(e));
      P.role = null;
    });
    peer.on('connection', onGuest);
  };
  tryBind(0);
}

function showRoomCode() {
  const box = el('p2p-code-show');
  box.classList.remove('hidden');
  box.innerHTML = `<div class="p2p-code-label">房号</div><div class="p2p-code">${P.code}</div>`;
  document.querySelector('.lobby-sub').textContent = '让其他人打开本页面 → 输入这个房号 → 加入';
}

function renderSeats() {
  const box = el('lobby-seats');
  box.style.display = 'block';
  box.innerHTML = '';
  const names = ['东（房主）', '南', '西', '北'];
  for (let i = 0; i < 4; i++) {
    const p = P.players[i];
    const row = document.createElement('div');
    const mine = P.role === 'host' ? i === 0 : i === P.seat;
    row.className = 'seat-row' + (p ? ' filled' : '') + (mine ? ' me' : '');
    row.textContent = `${names[i]}   ${p ? p.name + (p.isBot ? '（机器人）' : '') : '空位'}`;
    box.append(row);
  }
}

function renderHostActions() {
  const actions = el('lobby-actions');
  actions.innerHTML = '';
  if (P.started && !P.over && P.engine && P.engine.state.phase !== 'finished') return;
  const b = document.createElement('button');
  b.className = 'big-btn';
  const n = P.players.filter((p) => p).length;
  b.textContent = n >= 4 ? '开始对局' : '开始对局（空位补机器人）';
  b.onclick = () => startHostGame();
  actions.append(b);
}

let hostPeerSeq = 0;
function onGuest(conn) {
  const name = cleanName(conn.metadata && conn.metadata.name);
  if (P.started && P.engine && P.engine.state.phase !== 'finished') {
    try { conn.send({ t: 'reject', reason: '这一局已经开始，等这局打完再进来' }); } catch {}
    setTimeout(() => { try { conn.close(); } catch {} }, 300);
    return;
  }
  const used = new Set(P.conns.map((c) => c.seat));
  let seat = -1;
  for (let i = 1; i < 4; i++) if (!used.has(i) && !P.players[i]) { seat = i; break; }
  if (seat < 0) {
    try { conn.send({ t: 'reject', reason: '房间满了（4 人）' }); } catch {}
    setTimeout(() => { try { conn.close(); } catch {} }, 300);
    return;
  }
  P.players[seat] = { name, isBot: false, online: true };
  P.conns.push({ conn, seat });
  P.version++;
  hostPeerSeq++;

  conn.on('data', (msg) => hostMsg(conn, seat, msg));
  conn.on('close', () => {
    const i = P.conns.findIndex((c) => c.conn === conn);
    if (i >= 0) P.conns.splice(i, 1);
    if (P.players[seat]) { P.players[seat].online = false; P.players[seat].isBot = true; }
    P.version++;
    if (!P.inGame) { renderSeats(); renderHostActions(); }
  });

  try {
    conn.send({ t: 'hello', seat, started: P.started, over: P.over, code: P.code });
    conn.send({ t: 'state', seat, started: P.started, over: P.over, version: P.version, snap: snapshotFor(seat) });
  } catch {}
  if (!P.inGame) { renderSeats(); renderHostActions(); status(`${name} 加入了（${P.conns.length + 1}/4）`); }
}

function hostMsg(conn, seat, msg) {
  if (!msg || typeof msg !== 'object') return;
  if (msg.type === 'act' || msg.t === 'act') {
    applyHostAction(msg.action, seat);
  } else if (msg.t === 'start' && seat === 0) {
    startHostGame();
  } else if (msg.t === 'next') {
    hostNextHand();
  } else if (msg.t === 'restart' && seat === 0) {
    P.over = false; P.started = false; P.engine = null; startHostGame();
  } else if (msg.t === 'bye') {
    try { conn.close(); } catch {}
  }
}

function applyHostAction(action, seat) {
  if (!P.engine || P.engine.state.phase === 'finished') return;
  try {
    P.engine.apply(action, seat);
    P.version++;
    hostPush();
  } catch {}
}

function startHostGame() {
  if (!P.engine) {
    while (P.players.length < 4) P.players.push({ name: '机器人' + (P.players.length), isBot: true, online: true });
    const names = P.players.map((p, i) => (p && p.name) || '玩家' + (i + 1));
    const botSeats = [];
    for (let i = 0; i < 4; i++) if (P.players[i] && P.players[i].isBot) botSeats.push(i);
    P.engine = new Engine({ seed: (Date.now() & 0xffffffff) >>> 0, names, botSeats, dealer: 0, roundIndex: 1 });
    P.engine.startHand();
  } else {
    P.engine.startNextHand((Date.now() & 0xffffffff) >>> 0);
  }
  P.started = true;
  P.over = false;
  P.lastKey = '';
  P.deadline = null;
  P.lastBotAt = 0;
  P.version++;
  P.lastSentVersion = -1;
  enterGame();
  hostPush();
}

function hostNextHand() {
  if (!P.engine || P.engine.state.phase !== 'finished') return;
  if (P.engine.state.roundIndex >= ROUNDS) {
    P.over = true;
    P.version++;
    hostPush();
    maybeShowResult(true);
    return;
  }
  hideResult();
  P.resultKey = '';
  P.engine.startNextHand((Date.now() & 0xffffffff) >>> 0);
  P.lastKey = '';
  P.deadline = null;
  P.version++;
  P.lastSentVersion = -1;
  hostPush();
}

/* ---------------- 房主驱动 ---------------- */

function startHostLoop() {
  if (P.loop) clearInterval(P.loop);
  P.loop = setInterval(hostTick, 250);
}

function hostTick() {
  if (!P.engine) return;
  const s = P.engine.state;
  const now = Date.now();
  if (s.phase === 'finished') { P.deadline = null; hostPush(); return; }

  const key = `${s.phase}|${s.current}|${s.pending ? s.pending.outstanding.join(',') : ''}|${s.wall.remaining}`;
  if (key !== P.lastKey) {
    P.lastKey = key;
    P.deadline = null;
    if (s.phase === 'awaitingDiscard' && P.players[s.current] && !P.players[s.current].isBot && P.players[s.current].online) {
      P.deadline = { at: now + DEFAULT_RULE.playSeconds * 1000, kind: 'discard', seat: s.current };
    } else if (s.phase === 'awaitingClaim' && s.pending) {
      const humans = s.pending.outstanding.filter((x) => P.players[x] && !P.players[x].isBot && P.players[x].online);
      if (humans.length) P.deadline = { at: now + DEFAULT_RULE.claimSeconds * 1000, kind: 'pass', seat: humans[0] };
    }
  }

  if (P.deadline && now >= P.deadline.at) {
    const d = P.deadline;
    P.deadline = null;
    if (d.kind === 'discard') {
      const t = discardCandidate(s.players[d.seat].hand);
      if (t !== null) applyHostAction({ type: 'discard', tile: t }, d.seat);
    } else {
      applyHostAction({ type: 'pass' }, d.seat);
    }
    return;
  }

  if (now - P.lastBotAt >= 1100) {
    let botSeat = -1;
    if (s.phase === 'awaitingClaim' && s.pending) {
      const x = s.pending.outstanding.find((i) => P.players[i] && (P.players[i].isBot || !P.players[i].online));
      if (x !== undefined) botSeat = x;
    } else if (s.phase === 'awaitingDiscard' && P.players[s.current] && (P.players[s.current].isBot || !P.players[s.current].online)) {
      botSeat = s.current;
    }
    if (botSeat >= 0) {
      const a = nextAction(P.engine, botSeat) || { type: 'pass' };
      try { P.engine.apply(a, botSeat); P.version++; } catch {}
      P.lastBotAt = now;
    }
  }
  hostPush();
}

function snapshotFor(seat) {
  const snap = P.engine.snapshotFor(seat);
  snap.turnDeadline = P.deadline ? P.deadline.at : null;
  snap.over = P.over;
  snap.seats = P.players.map((p) => ({ name: p && p.name, isBot: !!(p && p.isBot), online: !!(p && p.online) }));
  snap.canStart = seat === 0 && !P.started;
  snap.canNext = !!(P.engine && P.engine.state.phase === 'finished');
  snap.rounds = ROUNDS;
  return snap;
}

function hostPush(force = false) {
  if (force || P.version !== P.lastSentVersion) {
    P.lastSentVersion = P.version;
    for (const g of P.conns) {
      try { if (g.conn.open) g.conn.send({ t: 'state', seat: g.seat, started: P.started, over: P.over, version: P.version, snap: snapshotFor(g.seat) }); } catch {}
    }
    if (P.engine && P.role === 'host') {
      P.snap = wrapSnapshot(snapshotFor(0));
      if (P.inGame) { renderAll(); maybeShowResult(); }
      const s = P.engine.state;
      if (s.phase === 'finished' && P.deadline === null) {}
    }
  } else if (P.engine && P.role === 'host' && P.inGame) {
    P.snap = wrapSnapshot(snapshotFor(0));
  }
}

/* ---------------- 玩家 ---------------- */

function joinRoom() {
  if (!window.Peer) { status('联机组件没加载，刷新一下页面'); return; }
  const code = (el('p2p-code').value || '').trim().toUpperCase();
  if (code.length !== 6) { status('请输入 6 位房号'); el('p2p-code').focus(); return; }
  const name = readName();
  P.role = 'guest';
  P.code = code;
  status('正在连接房主…');

  const peer = new Peer({ config: ICE, debug: 0 });
  P.peer = peer;
  peer.on('open', () => {
    const conn = peer.connect(HOST_PREFIX + code, { reliable: true, metadata: { name } });
    P.hostConn = conn;
    conn.on('open', () => { status('已连上房主，等房主开局'); clearTimeout(P.joinTimer); });
    conn.on('data', guestMsg);
    conn.on('close', () => { status('房主断开了，可以回首页重开'); });
    conn.on('error', (e) => status('连接出错：' + errText(e)));
  });
  peer.on('error', (e) => {
    clearTimeout(P.joinTimer);
    status(errText(e));
  });
  P.joinTimer = setTimeout(() => {
    if (!P.hostConn || !P.hostConn.open) {
      status('连不上房主：确认房号没输错、两台手机在同一个 WiFi');
    }
  }, 9000);
}

function guestMsg(msg) {
  if (!msg || typeof msg !== 'object') return;
  if (msg.t === 'reject') {
    clearTimeout(P.joinTimer);
    status(msg.reason || '进不去');
    try { P.hostConn.close(); } catch {}
    reset();
    return;
  }
  if (msg.t === 'hello') {
    P.seat = msg.seat || 0;
    P.code = msg.code || P.code;
    if (!P.inGame) { setEntryVisible(false); renderGuestSeats(); }
    return;
  }
  if (msg.t === 'state') {
    if (typeof msg.seat === 'number') P.seat = msg.seat;
    const snap = msg.snap;
    if (!snap) return;
    const ver = typeof msg.version === 'number' ? msg.version : -1;
    const changed = ver !== P.lastStateVersion || snap.phase !== P.lastPhase;
    P.lastStateVersion = ver;
    P.snap = wrapSnapshot(snap);
    P.over = !!snap.over;
    P.lastPhase = snap.phase;
    if (!P.inGame) {
      setEntryVisible(false);
      renderGuestSeats();
      if (msg.started || snap.started) enterGame();
    }
    /* 只有版本真的变了才重绘，否则每 250ms 白跑一遍 DOM 会卡 */
    if (P.inGame && changed) { renderAll(); maybeShowResult(); }
  }
}

function wrapSnapshot(snap) {
  return { ...snap, wall: { remaining: snap.wallRemaining } };
}

function renderGuestSeats() {
  const seats = (P.snap && P.snap.seats) || [];
  P.players = seats.map((s) => s);
  const box = el('lobby-seats');
  box.style.display = 'block';
  box.innerHTML = '';
  const names = ['东（房主）', '南', '西', '北'];
  for (let i = 0; i < 4; i++) {
    const p = seats[i];
    const row = document.createElement('div');
    row.className = 'seat-row' + (p ? ' filled' : '') + (i === P.seat ? ' me' : '');
    row.textContent = `${names[i]}   ${p ? p.name + (p.isBot ? '（机器人）' : '') : '空位'}`;
    box.append(row);
  }
  document.querySelector('.lobby-sub').textContent = `房号 ${P.code} · 等房主开始`;
  el('lobby-actions').innerHTML = '';
  const tip = document.createElement('div');
  tip.style.cssText = 'color: rgba(243,236,216,.6); font-size: 14px; margin-top: 10px;';
  tip.textContent = '等待房主开始对局…';
  el('lobby-actions').append(tip);
}

/* ---------------- 共用：进牌桌 ---------------- */

function enterGame() {
  if (P.inGame) return;
  if (!P.snap && P.engine) P.snap = wrapSnapshot(snapshotFor(P.role === 'host' ? 0 : P.seat));
  P.inGame = true;
  el('lobby').classList.remove('show');
  initTable({
    humanSeat: P.seat,
    mode: 'p2p',
    totalRounds: ROUNDS,
    getState: () => P.snap,
    getMyActions: () => (P.snap && P.snap.myActions) || [],
    getPendingOptions: () => (P.snap && P.snap.pending ? P.snap.pending.myOptions : null),
    onDiscard: (tile) => send({ type: 'discard', tile }),
    onAct: (a) => send(a),
    onNext: () => nextHand(),
    onExit: () => exitP2P(),
  });
  renderAll();
  if (!P.uiTimer) {
    P.uiTimer = setInterval(() => {
      if (!P.snap || !P.snap.turnDeadline) return;
      const total = P.snap.phase === 'awaitingClaim' ? 8000 : 30000;
      updateTimer((P.snap.turnDeadline - Date.now()) / total);
    }, 100);
  }
}

function send(action) {
  if (P.role === 'host') {
    applyHostAction(action, 0);
    return;
  }
  try { if (P.hostConn && P.hostConn.open) P.hostConn.send({ t: 'act', action }); } catch {}
}

function nextHand() {
  hideResult();
  P.resultKey = '';
  if (P.role === 'host') hostNextHand();
  else { try { P.hostConn.send({ t: 'next' }); } catch {} }
}

function exitP2P() {
  if (P.role === 'host') {
    for (const g of P.conns) { try { g.conn.send({ t: 'bye' }); g.conn.close(); } catch {} }
  } else {
    try { if (P.hostConn) P.hostConn.close(); } catch {}
  }
  try { if (P.peer) P.peer.destroy(); } catch {}
  hideResult();
  backToHome();
  el('lobby').classList.remove('show');
  reset();
}

function reset() {
  clearInterval(P.loop);
  clearInterval(P.uiTimer);
  clearTimeout(P.joinTimer);
  Object.assign(P, {
    role: null, code: '', seat: 0, peer: null, conns: [], players: [],
    engine: null, started: false, over: false, version: 0, deadline: null,
    lastKey: '', lastBotAt: 0, lastSentVersion: -1, snap: null, inGame: false,
    resultKey: '', lastPhase: '', lastStateVersion: -1, hostConn: null, loop: null, uiTimer: null, joinTimer: null,
  });
}

/* ---------------- 结算 ---------------- */

function namesOf() {
  return (P.snap && P.snap.seats ? P.snap.seats.map((s) => s && s.name) : ['东', '南', '西', '北']);
}

function maybeShowResult(isFinal) {
  const snap = P.snap;
  if (!snap || snap.phase !== 'finished') return;
  const key = `${snap.roundIndex}|${snap.winner}|${snap.drawnGame}|${P.over}|${snap.players.map((p) => p.score).join(',')}`;
  if (P.resultKey === key && !isFinal) return;
  P.resultKey = key;

  if (snap.over) { showFinal(); return; }

  if (snap.drawnGame) {
    showResult({
      title: '流局',
      subtitle: `牌墙摸完 · 庄家不变，下一局继续（${snap.roundIndex}/${ROUNDS}）`,
      hand: null,
      payments: null,
      scores: snap.players.map((p) => p.score),
      names: namesOf(),
      reds: snap.players.map((p) => p.redsPlayed),
      drawnGame: true,
    });
    return;
  }
  const r = snap.result;
  if (!r) return;
  const winner = snap.players[r.winner];
  const mult = winner.redsPlayed > 0 ? ` · 皮子 ×${1 << winner.redsPlayed}` : '';
  showResult({
    title: `${winner.name} 自摸`,
    subtitle: `自摸 ${r.base} 分${mult} · 第 ${snap.roundIndex}/${ROUNDS} 局`,
    winnerSeat: r.winner,
    hand: r.hand,
    melds: r.melds,
    payments: r.payments,
    scores: r.scores,
    names: namesOf(),
    reds: snap.players.map((p) => p.redsPlayed),
  });
}

function showFinal() {
  const snap = P.snap;
  const card = el('result-card');
  card.innerHTML = '';
  const t = document.createElement('div');
  t.className = 'result-title';
  t.textContent = '本场结束';
  card.append(t);
  const sub = document.createElement('div');
  sub.className = 'result-sub';
  sub.textContent = `共 ${ROUNDS} 局`;
  card.append(sub);

  const table = document.createElement('table');
  table.className = 'result-table';
  table.innerHTML = '<thead><tr><th>排名</th><th>名字</th><th>总分</th></tr></thead>';
  const tbody = document.createElement('tbody');
  snap.players.map((p) => ({ name: p.name, score: p.score }))
    .sort((a, b) => b.score - a.score)
    .forEach((r, i) => {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${i + 1}</td><td>${r.name}</td><td class="${r.score >= 0 ? 'pos' : 'neg'}">${r.score > 0 ? '+' : ''}${r.score}</td>`;
      tbody.append(tr);
    });
  table.append(tbody);
  card.append(table);

  const actions = document.createElement('div');
  actions.className = 'result-actions';
  if (P.role === 'host' || P.seat === 0) {
    const again = document.createElement('button');
    again.className = 'big-btn';
    again.textContent = '再来一场';
    again.onclick = () => {
      hideResult(); P.resultKey = '';
      if (P.role === 'host') { P.over = false; P.started = false; P.engine = null; startHostGame(); }
      else { try { P.hostConn.send({ t: 'restart' }); } catch {} }
    };
    actions.append(again);
  }
  const home = document.createElement('button');
  home.className = 'big-btn ghost';
  home.textContent = '回首页';
  home.onclick = () => { hideResult(); exitP2P(); };
  actions.append(home);
  card.append(actions);
  el('result').classList.add('show');
}

/* ---------------- 工具 ---------------- */

function cleanName(s) {
  return String(s || '').replace(/[<>{}"'`\\]/g, '').trim().slice(0, 8) || '玩家';
}

function errText(e) {
  if (!e) return '未知错误';
  const t = e.type || '';
  if (t === 'peer-unavailable') return '房号不存在，确认一下是不是输错了';
  if (t === 'network') return '网络连不上（信令服务器不可达），换个网络试试';
  if (t === 'server-error') return '信令服务器忙，稍后再试';
  if (t === 'unavailable-id') return '房号被占用，重新建一次';
  if (t === 'browser-incompatible') return '这个浏览器不支持联机，换 Chrome / Safari 新版';
  if (t === 'webrtc') return '点对点连接失败，两个人先连同一个 WiFi';
  return t || (e.message || '未知错误');
}

export function openP2P() {
  if (P.role) { el('lobby').classList.add('show'); return; }
  buildEntryUI();
}

window.P2P = { open: openP2P };
