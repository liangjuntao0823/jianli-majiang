/* 局域网联机客户端：轮询服务器快照 + 提交动作 */
import { G, initTable, renderAll, updateTimer, showToast, showResult, hideResult, backToHome } from './ui.js';
import { label, SEAT_LABEL } from './tiles.js';

const NET = {
  seat: 0,
  token: null,
  name: '',
  version: -1,
  snap: null,
  started: false,
  over: false,
  inGame: false,
  pollTimer: null,
  localTimer: null,
  resultKey: '',
};

const el = (id) => document.getElementById(id);

function api(path, opts) {
  return fetch(path, opts).then((r) => r.json());
}

/* ---------------- 入口 ---------------- */

export function openLAN() {
  if (location.protocol === 'file:') {
    alert('局域网联机要先启动服务器：\n\n1. 双击 start-server.bat（或运行 node server.js）\n2. 用浏览器打开控制台显示的地址\n\n单机模式可以直接玩。');
    return;
  }
  el('lobby').classList.add('show');
  el('lobby-name').value = NET.name || localStorage.getItem('jianli_name') || '';
  if (NET.token) {
    pollOnce().then(() => startPolling());
  }
}

el('lobby-join').addEventListener('click', async () => {
  const name = el('lobby-name').value.trim();
  if (!name) { el('lobby-name').focus(); return; }
  NET.name = name;
  localStorage.setItem('jianli_name', name);
  const r = await api('/api/join', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name }) });
  if (r.error) { el('lobby-status').textContent = r.error; return; }
  NET.token = r.token;
  NET.seat = r.seat;
  localStorage.setItem('jianli_token', r.token);
  el('lobby-name-row').style.display = 'none';
  startPolling();
});

/* ---------------- 轮询 ---------------- */

function startPolling() {
  if (NET.pollTimer) clearInterval(NET.pollTimer);
  NET.pollTimer = setInterval(pollOnce, 400);
  pollOnce();
  if (!NET.localTimer) {
    NET.localTimer = setInterval(() => {
      if (!NET.snap || !NET.snap.turnDeadline) return;
      const total = NET.snap.phase === 'awaitingClaim' ? 8000 : 30000;
      updateTimer((NET.snap.turnDeadline - Date.now()) / total);
    }, 100);
  }
}

function stopPolling() {
  clearInterval(NET.pollTimer);
  NET.pollTimer = null;
  clearInterval(NET.localTimer);
  NET.localTimer = null;
}

async function pollOnce() {
  if (!NET.token) return;
  let r;
  try {
    r = await api('/api/state?token=' + encodeURIComponent(NET.token));
  } catch {
    el('lobby-status').textContent = '服务器连不上了';
    return;
  }
  if (r.error) {
    NET.token = null;
    localStorage.removeItem('jianli_token');
    el('lobby-status').textContent = r.error;
    stopPolling();
    return;
  }
  NET.seat = r.seat;
  NET.started = r.started;
  const snap = r.snapshot;
  const changed = r.version !== NET.version || (snap && snap.phase !== NET.lastPhase);
  NET.version = r.version;

  if (snap) {
    NET.snap = wrapSnapshot(snap);
    NET.over = snap.over;
    if (snap.phase !== NET.lastPhase) NET.lastPhase = snap.phase;
  }

  if (r.started && snap) {
    if (!NET.inGame) enterGame();
    if (changed) renderAll();
    maybeShowResult();
  } else {
    renderLobby(r);
  }
}

/** 把服务器快照包装成 ui.js 认的 state 形状 */
function wrapSnapshot(snap) {
  return {
    ...snap,
    wall: { remaining: snap.wallRemaining },
  };
}

/* ---------------- 房间等待 ---------------- */

function renderLobby(r) {
  el('lobby-seats').style.display = 'block';
  const box = el('lobby-seats');
  box.innerHTML = '';
  const seats = r.seats || [];
  const names = ['东（房主）', '南', '西', '北'];
  for (let i = 0; i < 4; i++) {
    const p = seats[i];
    const row = document.createElement('div');
    row.className = 'seat-row' + (p ? ' filled' : '') + (i === NET.seat ? ' me' : '');
    row.textContent = `${names[i]}   ${p ? p.name + (p.isBot ? '（机器人）' : '') : '空位'}`;
    box.append(row);
  }

  const actions = el('lobby-actions');
  actions.innerHTML = '';
  if (r.seats && r.seats.length >= 4 && NET.seat === 0) {
    const b = document.createElement('button');
    b.className = 'big-btn';
    b.textContent = '开始对局';
    b.onclick = async () => { await api('/api/start', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: NET.token }) }); pollOnce(); };
    actions.append(b);
  } else if (NET.seat === 0) {
    const b = document.createElement('button');
    b.className = 'big-btn';
    b.textContent = '开始对局（空位补机器人）';
    b.onclick = async () => { await api('/api/start', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: NET.token }) }); pollOnce(); };
    actions.append(b);
  } else {
    const t = document.createElement('div');
    t.style.cssText = 'color: rgba(243,236,216,.6); font-size: 14px;';
    t.textContent = '等待房主开始对局…';
    actions.append(t);
  }
}

/* ---------------- 进入牌桌 ---------------- */

function enterGame() {
  NET.inGame = true;
  el('lobby').classList.remove('show');
  initTable({
    humanSeat: NET.seat,
    mode: 'lan',
    totalRounds: 8,
    getState: () => NET.snap,
    getMyActions: () => (NET.snap && NET.snap.myActions) || [],
    getPendingOptions: () => (NET.snap && NET.snap.pending ? NET.snap.pending.myOptions : null),
    onDiscard: (tile) => send({ type: 'discard', tile }),
    onAct: (a) => send(a),
    onNext: () => nextHand(),
    onExit: () => exitLAN(),
  });
  renderAll();
}

function send(action) {
  api('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: NET.token, action }), })
    .then((r) => { if (r.error) showToast(r.error); pollOnce(); });
}

function nextHand() {
  hideResult();
  NET.resultKey = '';
  api('/api/next', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: NET.token }) })
    .then((r) => { if (r.error) showToast(r.error); pollOnce(); });
}

function exitLAN() {
  stopPolling();
  NET.inGame = false;
  NET.snap = null;
  NET.version = -1;
  NET.lastPhase = '';
  hideResult();
  backToHome();
  el('lobby').classList.remove('show');
}

/* ---------------- 结算 ---------------- */

function namesOf() {
  return (NET.snap && NET.snap.seats ? NET.snap.seats.map((s) => s.name) : ['东', '南', '西', '北']);
}

function maybeShowResult() {
  const snap = NET.snap;
  if (!snap || snap.phase !== 'finished') return;
  const key = `${snap.roundIndex}|${snap.winner}|${snap.drawnGame}|${NET.version}`;
  if (NET.resultKey === key) return;
  NET.resultKey = key;

  if (snap.over) { showFinal(); return; }

  if (snap.drawnGame) {
    showResult({
      title: '流局',
      subtitle: '牌墙摸完 · 庄家不变，下一局继续',
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
    subtitle: `自摸 ${r.base} 分${mult} · 第 ${snap.roundIndex}/8 局`,
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
  const snap = NET.snap;
  const card = el('result-card');
  card.innerHTML = '';
  const t = document.createElement('div');
  t.className = 'result-title';
  t.textContent = '本场结束';
  card.append(t);
  const sub = document.createElement('div');
  sub.className = 'result-sub';
  sub.textContent = '共 8 局 · 感谢陪打';
  card.append(sub);

  const table = document.createElement('table');
  table.className = 'result-table';
  table.innerHTML = '<thead><tr><th>排名</th><th>名字</th><th>总分</th></tr></thead>';
  const tbody = document.createElement('tbody');
  const ranked = snap.players.map((p) => ({ name: p.name, score: p.score })).sort((a, b) => b.score - a.score);
  ranked.forEach((r, i) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td>${i + 1}</td><td>${r.name}</td><td class="${r.score >= 0 ? 'pos' : 'neg'}">${r.score > 0 ? '+' : ''}${r.score}</td>`;
    tbody.append(tr);
  });
  table.append(tbody);
  card.append(table);

  const actions = document.createElement('div');
  actions.className = 'result-actions';
  if (NET.seat === 0) {
    const again = document.createElement('button');
    again.className = 'big-btn';
    again.textContent = '再来一场';
    again.onclick = async () => { hideResult(); await api('/api/restart', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token: NET.token }) }); NET.resultKey = ''; pollOnce(); };
    actions.append(again);
  }
  const home = document.createElement('button');
  home.className = 'big-btn ghost';
  home.textContent = '回首页';
  home.onclick = () => { hideResult(); exitLAN(); };
  actions.append(home);
  card.append(actions);
  el('result').classList.add('show');
}

window.LAN = { open: openLAN };
