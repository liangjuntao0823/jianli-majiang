/* 监利红中麻将 —— 牌局引擎（移植自 iOS JianliCore/Engine.swift）
 * 房主权威的纯逻辑引擎：输入动作，输出事件；全程只有发牌用随机数。
 */
import {
  RED_RAW, ALL_KINDS, Wall, sortHand, nextSeat, othersOf, seatDistance, SEAT_LABEL,
} from './tiles.js';
import { isWinning } from './win.js';

export const DEFAULT_RULE = {
  name: '监利红中',
  tileCount: 112,
  selfDrawBase: 10,      // 自摸：三家各付
  pointGangBase: 10,     // 点杠：点杠者独付
  concealedGangBase: 15, // 暗杠：三家各付
  addedGangBase: 5,      // 蓄杠（回头笑）：三家各付
  redGangBase: 15,       // 四张红中打完，按暗杠计
  allowChi: false,
  allowPointHu: false,
  allowSevenPairs: true,
  redAsPizi: true,
  playSeconds: 30,
  claimSeconds: 30,
  rounds: 8,
};

export class EngineError extends Error {}

export const PHASE = { IDLE: 'idle', DISCARD: 'awaitingDiscard', CLAIM: 'awaitingClaim', FINISHED: 'finished' };

function newPlayer(seat, name, isBot) {
  return { seat, name, hand: [], melds: [], river: [], redsPlayed: 0, score: 0, isBot: !!isBot, connected: true };
}

export class Engine {
  constructor({ seed = Date.now(), names = [], dealer = 0, roundIndex = 1, botSeats = [], rule = DEFAULT_RULE, state = null } = {}) {
    this.rule = rule;
    this.events = [];
    if (state) {
      this.state = state;
      return;
    }
    const players = [];
    for (let i = 0; i < 4; i++) {
      const name = names[i] && names[i].length ? names[i] : SEAT_LABEL[i] + '家';
      players.push(newPlayer(i, name, botSeats.includes(i)));
    }
    this.state = {
      players,
      dealer,
      current: dealer,
      phase: PHASE.IDLE,
      wall: new Wall(seed >>> 0),
      seed: seed >>> 0,
      roundIndex,
      pending: null,
      lastDrawn: null,
      lastDrawnFromTail: false,
      winner: null,
      drawnGame: false,
      result: null,
    };
  }

  get players() { return this.state.players; }
  get phase() { return this.state.phase; }

  /* ---------------- 开局 ---------------- */

  startHand() {
    const { state, rule } = this;
    const wallSeed = (state.seed ^ Math.imul(state.roundIndex, 0x9e3779b9)) >>> 0;
    state.wall = new Wall(wallSeed);
    for (let i = 0; i < 4; i++) {
      Object.assign(state.players[i], { hand: [], melds: [], river: [], redsPlayed: 0 });
    }
    state.pending = null;
    state.lastDrawn = null;
    state.winner = null;
    state.drawnGame = false;
    state.result = null;
    state.current = state.dealer;
    state.phase = PHASE.IDLE;

    // 发 13 轮，庄家起手各 1 张
    for (let r = 0; r < 13; r++) {
      for (let k = 0; k < 4; k++) {
        const seat = (state.dealer + k) % 4;
        const t = state.wall.drawFront();
        if (t !== null) state.players[seat].hand.push(t);
      }
    }

    const out = [];
    // 起手带的红中同样必打：摆台面，从牌墙尾换真牌
    for (let i = 0; i < 4; i++) {
      let guard = 0;
      while (state.players[i].hand.includes(RED_RAW) && guard < 8) {
        guard++;
        state.players[i].hand.splice(state.players[i].hand.indexOf(RED_RAW), 1);
        state.players[i].redsPlayed++;
        out.push({ type: 'redDiscarded', seat: i, count: state.players[i].redsPlayed });
        const re = state.wall.drawBack();
        if (re !== null) state.players[i].hand.push(re);
      }
      state.players[i].hand = sortHand(state.players[i].hand);
    }

    out.unshift({ type: 'handStarted', dealer: state.dealer, seed: state.seed, roundIndex: state.roundIndex });
    out.push(...this.drawTurn(state.dealer));
    this.events = out;
    return out;
  }

  /** 下一局：谁胡谁坐庄，流局庄家不变 */
  startNextHand(seed) {
    if (this.state.winner !== null && this.state.winner !== undefined) this.state.dealer = this.state.winner;
    this.state.seed = seed >>> 0;
    this.state.roundIndex++;
    return this.startHand();
  }

  /* ---------------- 动作入口 ---------------- */

  apply(action, seat) {
    if (this.state.phase === PHASE.FINISHED) throw new EngineError('本局已结束');
    let out;
    switch (action.type) {
      case 'discard': out = this.#discard(action.tile, seat); break;
      case 'peng': out = this.#respond('peng', seat); break;
      case 'gangExposed': out = this.#respond('gang', seat); break;
      case 'pass': out = this.#respond('pass', seat); break;
      case 'gangConcealed': out = this.#concealedGang(action.tile, seat); break;
      case 'gangAdded': out = this.#addedGang(action.tile, seat); break;
      case 'hu': out = this.#hu(seat); break;
      default: throw new EngineError('未知动作 ' + action.type);
    }
    this.events.push(...out);
    return out;
  }

  /* ---------------- 出牌 ---------------- */

  #discard(raw, seat) {
    const s = this.state;
    if (s.phase !== PHASE.DISCARD || s.current !== seat) throw new EngineError('没轮到你');
    const p = s.players[seat];
    const idx = p.hand.indexOf(raw);
    if (idx < 0) throw new EngineError('手里没有这张牌');
    p.hand.splice(idx, 1);
    s.lastDrawn = null;
    if (raw !== RED_RAW) p.river.push(raw);

    let out = [{ type: 'discarded', seat, tile: raw }, { type: 'wallRemaining', n: s.wall.remaining }];

    // 皮子：红中必打，摆台面、尾补一张、结算翻倍
    if (raw === RED_RAW) {
      p.redsPlayed++;
      out.push({ type: 'redDiscarded', seat, count: p.redsPlayed });
      if (p.redsPlayed >= 4) out.push(...this.#pay(this.rule.redGangBase, seat, othersOf(seat), 'redGang'));
      const re = s.wall.drawBack();
      if (re !== null) {
        p.hand.push(re);
        p.hand = sortHand(p.hand);
        s.lastDrawn = re;
        s.current = seat;
        s.phase = PHASE.DISCARD;
        out.push({ type: 'turn', seat, drawn: re }, { type: 'wallRemaining', n: s.wall.remaining });
      } else {
        out.push(this.#finishDrawn());
      }
      return out;
    }

    // 声明窗口：只能碰、杠，不能吃、不能点炮胡
    const options = {};
    for (let o = 0; o < 4; o++) {
      if (o === seat) continue;
      const same = s.players[o].hand.filter((t) => t === raw).length;
      if (same >= 3) options[o] = ['pass', 'gang'];
      else if (same === 2) options[o] = ['pass', 'peng'];
    }
    if (Object.keys(options).length === 0) {
      out.push(...this.drawTurn(nextSeat(seat)));
    } else {
      s.phase = PHASE.CLAIM;
      s.pending = { discarder: seat, tile: raw, options, outstanding: Object.keys(options).map(Number).sort(), answers: {} };
      out.push({ type: 'claimWindow', discarder: seat, tile: raw });
    }
    return out;
  }

  /* ---------------- 声明（碰/杠/过） ---------------- */

  #respond(option, seat) {
    const s = this.state;
    if (s.phase !== PHASE.CLAIM || !s.pending) throw new EngineError('当前阶段不允许这个操作');
    const opts = s.pending.options[seat];
    if (!opts || !opts.includes(option)) throw new EngineError('当前不能这样声明');
    s.pending.answers[seat] = option;
    s.pending.outstanding = s.pending.outstanding.filter((x) => x !== seat);
    if (s.pending.outstanding.length > 0) return [];
    return this.#resolve(s.pending);
  }

  #resolve(pending) {
    const s = this.state;
    const nearest = (seats) => seats.length === 0 ? null
      : seats.slice().sort((a, b) => seatDistance(s.players[a].seat, pending.discarder) - seatDistance(s.players[b].seat, pending.discarder))[0];
    const gangs = Object.keys(pending.answers).map(Number).filter((k) => pending.answers[k] === 'gang').sort((a, b) => a - b);
    const pengs = Object.keys(pending.answers).map(Number).filter((k) => pending.answers[k] === 'peng').sort((a, b) => a - b);
    s.pending = null;

    const g = nearest(gangs);
    if (g !== null) return this.#claimGang(g, pending);
    const pg = nearest(pengs);
    if (pg !== null) return this.#claimPeng(pg, pending);
    return this.drawTurn(nextSeat(pending.discarder));
  }

  #claimPeng(seat, pending) {
    const s = this.state;
    const p = s.players[seat];
    this.#removeTiles(pending.tile, 2, seat);
    p.melds.push({ kind: 'peng', tile: pending.tile });
    this.#removeFromRiver(pending.tile, pending.discarder);
    s.current = seat;
    s.phase = PHASE.DISCARD;
    s.lastDrawn = null;
    return [{ type: 'peng', seat, tile: pending.tile }];
  }

  #claimGang(seat, pending) {
    const s = this.state;
    const p = s.players[seat];
    this.#removeTiles(pending.tile, 3, seat);
    p.melds.push({ kind: 'gangExposed', tile: pending.tile });
    this.#removeFromRiver(pending.tile, pending.discarder);
    const out = [{ type: 'gang', seat, kind: 'gangExposed', tile: pending.tile }];
    out.push(...this.#pay(this.rule.pointGangBase, seat, [pending.discarder], 'pointGang'));
    out.push(...this.drawTurn(seat, true));
    return out;
  }

  /* ---------------- 自己回合的杠 ---------------- */

  #concealedGang(raw, seat) {
    const s = this.state;
    if (s.phase !== PHASE.DISCARD || s.current !== seat) throw new EngineError('没轮到你');
    const p = s.players[seat];
    if (raw >= 27 || p.hand.filter((t) => t === raw).length !== 4) throw new EngineError('没有四张一样的牌');
    this.#removeTiles(raw, 4, seat);
    p.melds.push({ kind: 'gangConcealed', tile: raw });
    const out = [{ type: 'gang', seat, kind: 'gangConcealed', tile: raw }];
    out.push(...this.#pay(this.rule.concealedGangBase, seat, othersOf(seat), 'concealedGang'));
    out.push(...this.drawTurn(seat, true));
    return out;
  }

  #addedGang(raw, seat) {
    const s = this.state;
    if (s.phase !== PHASE.DISCARD || s.current !== seat) throw new EngineError('没轮到你');
    const p = s.players[seat];
    const mi = p.melds.findIndex((m) => m.tile === raw && m.kind === 'peng');
    if (mi < 0) throw new EngineError('没有这张牌的碰');
    if (!p.hand.includes(raw)) throw new EngineError('手里没有第四张');
    this.#removeTiles(raw, 1, seat);
    p.melds[mi].kind = 'gangAdded';
    const out = [{ type: 'gang', seat, kind: 'gangAdded', tile: raw }];
    out.push(...this.#pay(this.rule.addedGangBase, seat, othersOf(seat), 'addedGang'));
    out.push(...this.drawTurn(seat, true));
    return out;
  }

  /* ---------------- 胡（只能自摸） ---------------- */

  #hu(seat) {
    const s = this.state;
    if (s.phase !== PHASE.DISCARD || s.current !== seat) throw new EngineError('没轮到你');
    const p = s.players[seat];
    if (p.hand.includes(RED_RAW)) throw new EngineError('手上带红中，不能胡');
    if (!isWinning(p.hand, p.melds.length, this.rule.allowSevenPairs)) throw new EngineError('牌型不成和');

    const payments = {};
    for (const o of othersOf(seat)) payments[o] = this.amount(this.rule.selfDrawBase, seat, o);
    for (const o of othersOf(seat)) {
      const v = payments[o] || 0;
      s.players[o].score -= v;
      p.score += v;
    }
    const result = {
      winner: seat,
      hand: p.hand.slice(),
      melds: p.melds.map((m) => ({ ...m })),
      payments,
      winnerReds: p.redsPlayed,
      base: this.rule.selfDrawBase,
      scores: s.players.map((x) => x.score),
      roundIndex: s.roundIndex,
      seed: s.seed,
    };
    s.phase = PHASE.FINISHED;
    s.winner = seat;
    s.drawnGame = false;
    s.result = result;
    return [{ type: 'hu', seat, payments }];
  }

  /* ---------------- 摸牌 / 流局 ---------------- */

  drawTurn(seat, fromBack = false) {
    const s = this.state;
    const p = s.players[seat];
    let out = [];
    let back = !!fromBack;

    // 红中必打：摸到红中直接摆台面，从尾牌换，直到摸到真牌
    for (;;) {
      const drawn = back ? s.wall.drawBack() : s.wall.drawFront();
      if (drawn === null) {
        out.push(this.#finishDrawn());
        return out;
      }
      s.lastDrawn = drawn;
      s.lastDrawnFromTail = back;

      if (drawn === RED_RAW) {
        p.redsPlayed++;
        out.push({ type: 'redDiscarded', seat, count: p.redsPlayed });
        if (p.redsPlayed >= 4) out.push(...this.#pay(this.rule.redGangBase, seat, othersOf(seat), 'redGang'));
        out.push({ type: 'wallRemaining', n: s.wall.remaining });
        back = true;
        continue;
      }

      p.hand.push(drawn);
      p.hand = sortHand(p.hand);
      s.current = seat;
      s.phase = PHASE.DISCARD;
      s.pending = null;
      out.push({ type: 'turn', seat, drawn }, { type: 'wallRemaining', n: s.wall.remaining });
      return out;
    }
  }

  #finishDrawn() {
    const s = this.state;
    s.phase = PHASE.FINISHED;
    s.drawnGame = true;
    s.winner = null;
    s.result = null;
    return { type: 'drawnGame' };
  }

  /* ---------------- 分账 ---------------- */

  /** 皮子倍乘：赢家每打出 1 张红中翻倍，付钱方每打出 1 张红中再翻倍 */
  amount(base, winner, payer) {
    const wm = 1 << Math.min(this.state.players[winner].redsPlayed, 8);
    const pm = 1 << Math.min(this.state.players[payer].redsPlayed, 8);
    return base * wm * pm;
  }

  #pay(base, winner, payers, reason) {
    const out = [];
    for (const payer of payers) {
      if (payer === winner) continue;
      const v = this.amount(base, winner, payer);
      this.state.players[payer].score -= v;
      this.state.players[winner].score += v;
      out.push({ type: 'score', from: payer, to: winner, amount: v, reason });
    }
    return out;
  }

  /* ---------------- 工具 ---------------- */

  #removeTiles(raw, count, seat) {
    const hand = this.state.players[seat].hand;
    for (let i = 0; i < count; i++) {
      const idx = hand.indexOf(raw);
      if (idx < 0) throw new EngineError('手牌不足');
      hand.splice(idx, 1);
    }
  }

  #removeFromRiver(raw, seat) {
    const river = this.state.players[seat].river;
    const idx = river.lastIndexOf(raw);
    if (idx >= 0) river.splice(idx, 1);
  }

  /** 轮到某人时他能做的非出牌动作（给 UI 与 AI 用） */
  options(seat) {
    const s = this.state;
    if (s.phase !== PHASE.DISCARD || s.current !== seat) return [];
    const p = s.players[seat];
    const out = [];
    if (this.canHu(seat)) out.push({ type: 'hu' });
    for (const kind of ALL_KINDS) {
      if (kind === RED_RAW) continue;
      if (p.hand.filter((t) => t === kind).length === 4) out.push({ type: 'gangConcealed', tile: kind });
      if (p.melds.some((m) => m.kind === 'peng' && m.tile === kind) && p.hand.includes(kind)) {
        out.push({ type: 'gangAdded', tile: kind });
      }
    }
    return out;
  }

  canHu(seat) {
    const p = this.state.players[seat];
    if (p.hand.includes(RED_RAW)) return false;
    return isWinning(p.hand, p.melds.length, this.rule.allowSevenPairs);
  }

  /** 玩家视角快照（联机传输 / UI 渲染用），隐藏别人的手牌 */
  snapshotFor(seat) {
    const s = this.state;
    return {
      dealer: s.dealer,
      current: s.current,
      phase: s.phase,
      roundIndex: s.roundIndex,
      wallRemaining: s.wall.remaining,
      lastDrawn: s.current === seat ? s.lastDrawn : null,
      myActions: this.options(seat),
      pending: s.pending ? {
        discarder: s.pending.discarder,
        tile: s.pending.tile,
        myOptions: s.pending.options[seat] || null,
      } : null,
      winner: s.winner,
      drawnGame: s.drawnGame,
      result: s.result ? { ...s.result } : null,
      players: s.players.map((p) => ({
        seat: p.seat,
        name: p.name,
        handCount: p.hand.length,
        hand: p.seat === seat ? p.hand.slice() : null,
        melds: p.melds.map((m) => ({ ...m })),
        river: p.river.slice(),
        redsPlayed: p.redsPlayed,
        score: p.score,
        isBot: p.isBot,
      })),
    };
  }
}
