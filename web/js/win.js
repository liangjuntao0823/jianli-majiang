/* 胡牌判定 —— 与 iOS 版 WinChecker 一致
 * 红中是皮子：手里带红中一律不算胡。
 * 标准型：4 组面子（顺子/刻子）+ 1 对将；七对只在无副露时成立。
 */
import { RED_RAW, ALL_KINDS } from './tiles.js';

/**
 * @param {number[]} hand 手牌 raw 数组（不含副露的牌）
 * @param {number} meldCount 已副露组数（碰/杠都算 1 组面子）
 * @param {boolean} allowSevenPairs
 */
export function isWinning(hand, meldCount = 0, allowSevenPairs = true) {
  if (hand.some((t) => t === RED_RAW)) return false;

  const counts = new Array(27).fill(0);
  for (const t of hand) {
    if (t >= 27) return false;
    counts[t]++;
  }

  const setsNeeded = 4 - meldCount;
  if (setsNeeded < 0) return false;
  if (hand.length !== setsNeeded * 3 + 2) return false;

  if (allowSevenPairs && meldCount === 0 && hand.length === 14) {
    let pairs = 0;
    let allEven = true;
    for (let i = 0; i < 27; i++) {
      pairs += Math.floor(counts[i] / 2);
      if (counts[i] % 2 !== 0) allEven = false;
    }
    if (allEven && pairs === 7) return true;
  }

  for (let pair = 0; pair < 27; pair++) {
    if (counts[pair] < 2) continue;
    const rest = counts.slice();
    rest[pair] -= 2;
    if (canFormSets(rest, setsNeeded)) return true;
  }
  return false;
}

function canFormSets(counts, sets) {
  if (sets === 0) return counts.every((c) => c === 0);
  let first = -1;
  for (let i = 0; i < 27; i++) {
    if (counts[i] > 0) {
      first = i;
      break;
    }
  }
  if (first < 0) return false;

  // 刻子
  if (counts[first] >= 3) {
    const c = counts.slice();
    c[first] -= 3;
    if (canFormSets(c, sets - 1)) return true;
  }

  // 顺子（同花色内连续）
  const rank = first % 9;
  if (rank <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0) {
    const c = counts.slice();
    c[first] -= 1;
    c[first + 1] -= 1;
    c[first + 2] -= 1;
    if (canFormSets(c, sets - 1)) return true;
  }
  return false;
}

/** 听牌提示：返回所有能和的牌 raw（只用于 UI，不参与裁决） */
export function waitingTiles(hand, meldCount = 0, allowSevenPairs = true) {
  if (hand.some((t) => t === RED_RAW)) return [];
  const out = [];
  for (const kind of ALL_KINDS) {
    if (kind === RED_RAW) continue;
    if (isWinning([...hand, kind], meldCount, allowSevenPairs)) out.push(kind);
  }
  return out;
}
