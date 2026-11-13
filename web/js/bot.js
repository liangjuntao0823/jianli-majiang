/* 机器人 AI —— 移植自 iOS Bot.swift
 * 不追求强，要求「像人」：先打皮子、再拆孤张、不无脑碰杠。
 */
import { RED_RAW, rankOf } from './tiles.js';

export function nextAction(engine, seat) {
  const s = engine.state;

  // 声明窗口：能杠就杠；碰要看牌型；否则过
  if (s.phase === 'awaitingClaim' && s.pending && s.pending.outstanding.includes(seat)) {
    const opts = s.pending.options[seat] || ['pass'];
    if (opts.includes('gang')) return { type: 'gangExposed' };
    if (opts.includes('peng') && shouldPeng(s.players[seat].hand, s.pending.tile)) return { type: 'peng' };
    return { type: 'pass' };
  }

  if (s.phase !== 'awaitingDiscard' || s.current !== seat) return null;
  if (engine.canHu(seat)) return { type: 'hu' };

  for (const opt of engine.options(seat)) {
    if (opt.type === 'gangAdded') return { type: 'gangAdded', tile: opt.tile };
    if (opt.type === 'gangConcealed' && s.players[seat].melds.length >= 1) {
      return { type: 'gangConcealed', tile: opt.tile };
    }
  }

  const tile = discardCandidate(s.players[seat].hand);
  return tile === null ? null : { type: 'discard', tile };
}

export function shouldPeng(hand, tile) {
  if (hand.filter((t) => t === tile).length < 2) return false;
  const pairs = new Map();
  for (const t of hand) {
    if (t === RED_RAW) continue;
    pairs.set(t, (pairs.get(t) || 0) + 1);
  }
  let pairCount = 0;
  for (const v of pairs.values()) if (v >= 2) pairCount++;
  const rank = rankOf(tile);
  if (rank === 1 || rank === 9) return true;
  return pairCount >= 2;
}

export function discardCandidate(hand) {
  if (hand.length === 0) return null;
  if (hand.includes(RED_RAW)) return RED_RAW; // 皮子留不得

  let best = null;
  let bestScore = Infinity;
  for (const tile of hand) {
    let score = 0;
    const same = hand.filter((t) => t === tile).length;
    score += same * 4;

    if (tile !== RED_RAW) {
      const suit = Math.floor(tile / 9);
      for (const delta of [-2, -1, 1, 2]) {
        const target = tile + delta;
        if (target < 0 || target >= 27 || Math.floor(target / 9) !== suit) continue;
        if (hand.includes(target)) score += Math.abs(delta) === 1 ? 3 : 1;
      }
      const rank = rankOf(tile);
      if (rank === 1 || rank === 9) score -= 2;
      if (rank >= 3 && rank <= 7) score += 1;
    }

    if (score < bestScore) {
      bestScore = score;
      best = tile;
    }
  }
  return best;
}
