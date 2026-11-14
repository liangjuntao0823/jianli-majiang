/* 监利红中麻将 —— 牌定义 / 随机数 / 牌墙
 * 牌编码与 iOS 版 JianliCore 完全一致：
 * 0-8 万1-9，9-17 筒1-9，18-26 条1-9，27 红中。共 112 张。
 */

export const RED_RAW = 27;
export const ALL_KINDS = Array.from({ length: 28 }, (_, i) => i);
export const NUMERALS = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
export const SUIT_SYMBOL = ['萬', '筒', '條'];

export const isRed = (raw) => raw === RED_RAW;
export const suitOf = (raw) => (raw === RED_RAW ? 3 : Math.floor(raw / 9));
export const rankOf = (raw) => (raw === RED_RAW ? 0 : (raw % 9) + 1);

export function label(raw) {
  if (raw === RED_RAW) return '红中';
  return NUMERALS[rankOf(raw) - 1] + SUIT_SYMBOL[suitOf(raw)];
}

/** 单文件构建时由构建脚本填充为 base64 data URI */
import { TILE_SRC as ART_SRC } from './tileArt.js';

/** 牌面图：内联 base64（js/tileArt.js），保证任何环境都能显示 */
export const TILE_SRC = ART_SRC;

/** 牌面图片名，对应 assets/tiles/<name>.png */
export function tileSrc(raw) {
  const name = tileImage(raw);
  return TILE_SRC[name] || 'assets/tiles/' + name + '.png';
}

export function tileImage(raw) {
  if (raw === RED_RAW) return 'Chun';
  const suit = ['Man', 'Pin', 'Sou'][suitOf(raw)];
  return suit + rankOf(raw);
}

/** 112 张全牌堆 */
export function fullSet() {
  const out = [];
  for (const k of ALL_KINDS) for (let i = 0; i < 4; i++) out.push(k);
  return out;
}

/* —— 确定性随机：mulberry32。只用于发牌，局中不取随机 —— */
export function makeRng(seed) {
  let a = seed >>> 0;
  return function next() {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function shuffledTiles(seed) {
  const rng = makeRng(seed >>> 0);
  const arr = fullSet();
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/** 牌墙：head 为正常摸牌端，tail 为杠/皮子补牌端 */
export class Wall {
  constructor(seedOrTiles, head, tail) {
    if (Array.isArray(seedOrTiles)) {
      this.tiles = seedOrTiles.slice();
      this.head = head || 0;
      this.tail = tail === undefined ? this.tiles.length - 1 : tail;
    } else {
      this.tiles = shuffledTiles(seedOrTiles >>> 0);
      this.head = 0;
      this.tail = this.tiles.length - 1;
    }
  }
  get remaining() {
    return Math.max(0, this.tail - this.head + 1);
  }
  get isEmpty() {
    return this.remaining <= 0;
  }
  drawFront() {
    if (this.remaining <= 0) return null;
    return this.tiles[this.head++];
  }
  drawBack() {
    if (this.remaining <= 0) return null;
    return this.tiles[this.tail--];
  }
}

/** 座位：0东 1南 2西 3北（顺时针） */
export const SEAT_LABEL = ['东', '南', '西', '北'];
export const nextSeat = (s) => (s + 1) % 4;
export const othersOf = (s) => [0, 1, 2, 3].filter((x) => x !== s);
/** 从 self 出发到 other 的顺时针步数 1..3 */
export const seatDistance = (self, other) => (other - self + 4) % 4;

/** 手牌排序：万→筒→条→红中 */
export const sortHand = (hand) => hand.slice().sort((a, b) => a - b);

/** 统计 raw 出现次数 */
export function countByRaw(hand) {
  const c = new Map();
  for (const t of hand) c.set(t, (c.get(t) || 0) + 1);
  return c;
}
