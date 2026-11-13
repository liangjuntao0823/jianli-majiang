/* 监利红中 · 局域网联机服务器
 * 零依赖：只用 Node 内置模块。房主电脑跑起来，四个人用浏览器打开地址就能打。
 *   启动：node server.js
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Engine, DEFAULT_RULE } from './js/engine.js';
import { nextAction, discardCandidate } from './js/bot.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8878);
const ROUNDS = 8;

const room = {
  players: [],      // { name, token, isBot, online, lastSeen }
  engine: null,
  started: false,
  over: false,
  version: 0,
  lastBotAt: 0,
  lastKey: '',
  deadline: null,   // { at, kind: 'discard' | 'pass', seat }
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.png': 'image/png',
  '.json': 'application/json; charset=utf-8',
  '.ico': 'image/x-icon',
};

/* ---------------- 静态文件 ---------------- */

function serveStatic(req, res) {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  if (p === '/') p = '/index.html';
  const full = path.normalize(path.join(ROOT, p));
  if (!full.startsWith(ROOT)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404); res.end('not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(full)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(data);
  });
}

/* ---------------- 工具 ---------------- */

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => { body += c; if (body.length > 1e5) reject(new Error('too large')); });
    req.on('end', () => { try { resolve(body ? JSON.parse(body) : {}); } catch { resolve({}); } });
    req.on('error', reject);
  });
}

const seatByToken = (token) => room.players.findIndex((p) => p.token && p.token === token);
const cleanName = (s) => String(s || '').replace(/[<>{}"'`\\]/g, '').trim().slice(0, 8) || '玩家';

function applyAction(action, seat) {
  if (!room.engine) return false;
  try {
    room.engine.apply(action, seat);
    room.version++;
    return true;
  } catch (e) {
    return false;
  }
}

/* ---------------- 房间逻辑 ---------------- */

function fillWithBots() {
  let n = 1;
  while (room.players.length < 4) {
    room.players.push({ name: '机器人' + n++, token: null, isBot: true, online: true, lastSeen: 0 });
  }
}

function startGame() {
  fillWithBots();
  const names = room.players.map((p, i) => p.name || '玩家' + (i + 1));
  const botSeats = [];
  for (let i = 0; i < 4; i++) if (room.players[i].isBot) botSeats.push(i);
  room.engine = new Engine({ seed: (Date.now() & 0xffffffff) >>> 0, names, botSeats, dealer: 0, roundIndex: 1 });
  room.engine.startHand();
  room.started = true;
  room.over = false;
  room.lastKey = '';
  room.deadline = null;
  room.version++;
}

function snapshotFor(seat) {
  const snap = room.engine.snapshotFor(seat);
  snap.turnDeadline = room.deadline ? room.deadline.at : null;
  snap.over = room.over;
  snap.seats = room.players.map((p) => ({ name: p.name, isBot: p.isBot, online: p.online }));
  snap.canStart = seat === 0 && !room.started;
  snap.canNext = room.engine && room.engine.state.phase === 'finished';
  snap.rounds = ROUNDS;
  return snap;
}

/* ---------------- 驱动（机器人 + 超时） ---------------- */

setInterval(() => {
  if (!room.started || !room.engine) return;
  const s = room.engine.state;
  const now = Date.now();

  if (s.phase === 'finished') { room.deadline = null; return; }

  // 回合变化 → 重设超时
  const key = `${s.phase}|${s.current}|${s.pending ? s.pending.outstanding.join(',') : ''}|${s.wall.remaining}`;
  if (key !== room.lastKey) {
    room.lastKey = key;
    room.deadline = null;
    if (s.phase === 'awaitingDiscard' && room.players[s.current] && !room.players[s.current].isBot) {
      room.deadline = { at: now + DEFAULT_RULE.playSeconds * 1000, kind: 'discard', seat: s.current };
    } else if (s.phase === 'awaitingClaim' && s.pending) {
      const humans = s.pending.outstanding.filter((x) => room.players[x] && !room.players[x].isBot);
      if (humans.length) room.deadline = { at: now + DEFAULT_RULE.claimSeconds * 1000, kind: 'pass', seat: humans[0] };
    }
  }

  // 人类超时托管
  if (room.deadline && now >= room.deadline.at) {
    const d = room.deadline;
    room.deadline = null;
    if (d.kind === 'discard') {
      const t = discardCandidate(s.players[d.seat].hand);
      if (t !== null) applyAction({ type: 'discard', tile: t }, d.seat);
    } else {
      applyAction({ type: 'pass' }, d.seat);
    }
    return;
  }

  // 机器人节奏
  if (now - room.lastBotAt < 1100) return;
  let botSeat = -1;
  if (s.phase === 'awaitingClaim' && s.pending) {
    botSeat = s.pending.outstanding.find((x) => room.players[x] && room.players[x].isBot);
    if (botSeat === undefined) botSeat = -1;
  } else if (s.phase === 'awaitingDiscard' && room.players[s.current] && room.players[s.current].isBot) {
    botSeat = s.current;
  }
  if (botSeat >= 0) {
    const a = nextAction(room.engine, botSeat) || { type: 'pass' };
    applyAction(a, botSeat);
    room.lastBotAt = now;
  }
}, 250);

/* ---------------- HTTP ---------------- */

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');

  if (!url.pathname.startsWith('/api/')) return serveStatic(req, res);

  try {
    if (url.pathname === '/api/room' && req.method === 'GET') {
      return json(res, 200, {
        started: room.started,
        over: room.over,
        seats: room.players.map((p) => ({ name: p.name, isBot: p.isBot, online: p.online })),
        rounds: ROUNDS,
      });
    }

    if (url.pathname === '/api/join' && req.method === 'POST') {
      const body = await readBody(req);
      if (room.started && !room.over) return json(res, 409, { error: '本局已经开始，等这局打完再加入' });
      if (room.players.length >= 4) return json(res, 409, { error: '房间已满（4 人）' });
      const token = randomBytes(10).toString('hex');
      const seat = room.players.length;
      room.players.push({ name: cleanName(body.name), token, isBot: false, online: true, lastSeen: Date.now() });
      room.version++;
      return json(res, 200, { seat, token, name: room.players[seat].name });
    }

    if (url.pathname === '/api/state' && req.method === 'GET') {
      const token = url.searchParams.get('token') || '';
      const seat = seatByToken(token);
      if (seat < 0) return json(res, 401, { error: '未入座' });
      room.players[seat].lastSeen = Date.now();
      room.players[seat].online = true;
      if (!room.engine) {
        return json(res, 200, {
          seat, started: false, version: room.version,
          seats: room.players.map((p) => ({ name: p.name, isBot: p.isBot, online: p.online })),
          snapshot: null, rounds: ROUNDS,
        });
      }
      return json(res, 200, {
        seat,
        started: room.started,
        version: room.version,
        snapshot: snapshotFor(seat),
        rounds: ROUNDS,
      });
    }

    if (url.pathname === '/api/action' && req.method === 'POST') {
      const body = await readBody(req);
      const seat = seatByToken(body.token || '');
      if (seat < 0) return json(res, 401, { error: '未入座' });
      if (!room.engine || room.engine.state.phase === 'finished') return json(res, 400, { error: '当前不能操作' });
      const ok = applyAction(body.action || {}, seat);
      return json(res, ok ? 200 : 400, { ok });
    }

    if (url.pathname === '/api/start' && req.method === 'POST') {
      const body = await readBody(req);
      const seat = seatByToken(body.token || '');
      if (seat !== 0) return json(res, 403, { error: '只有房主能开局' });
      if (room.started && !room.over) return json(res, 400, { error: '已经开局了' });
      startGame();
      return json(res, 200, { ok: true });
    }

    if (url.pathname === '/api/next' && req.method === 'POST') {
      const body = await readBody(req);
      const seat = seatByToken(body.token || '');
      if (seat < 0) return json(res, 401, { error: '未入座' });
      if (!room.engine) return json(res, 400, { error: '还没开局' });
      const s = room.engine.state;
      if (s.phase !== 'finished') return json(res, 400, { error: '本局还没结束' });
      if (s.drawnGame === false && s.winner === 0) { /* 谁胡谁坐庄由引擎处理 */ }
      if (s.roundIndex >= ROUNDS) {
        room.over = true;
        room.version++;
        return json(res, 200, { ok: true, over: true });
      }
      room.engine.startNextHand((Date.now() & 0xffffffff) >>> 0);
      room.lastKey = '';
      room.deadline = null;
      room.version++;
      return json(res, 200, { ok: true, over: false });
    }

    if (url.pathname === '/api/restart' && req.method === 'POST') {
      const body = await readBody(req);
      const seat = seatByToken(body.token || '');
      if (seat !== 0) return json(res, 403, { error: '只有房主能重开' });
      room.over = false;
      room.engine = null;
      room.started = false;
      startGame();
      return json(res, 200, { ok: true });
    }

    return json(res, 404, { error: 'unknown api' });
  } catch (err) {
    return json(res, 500, { error: String(err && err.message || err) });
  }
});

function localIPs() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const i of list || []) {
      if (i.family === 'IPv4' && !i.internal) out.push(i.address);
    }
  }
  return out;
}

server.listen(PORT, () => {
  const ips = localIPs();
  console.log('');
  console.log('  监利红中 · 局域网麻将            ');
  console.log('  ─────────────────────────────');
  console.log(`  本机访问：   http://localhost:${PORT}`);
  for (const ip of ips) console.log(`  手机/电脑：  http://${ip}:${PORT}`);
  console.log('');
  console.log('  四个人用浏览器打开上面的地址，第一个人是房主（东家）。');
  console.log('  人不够时房主点「开始对局」，空位自动补机器人。');
  console.log('');
});
