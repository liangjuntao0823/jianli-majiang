# 监利红中 · iOS 局域网四人麻将

一台 iPhone 开房，同一 Wi-Fi 下另外三台扫码/搜索入座，无账号、无服务器、无公网依赖。全部界面横屏。

> 规则口径以「监利红中麻将 · 修正版」为准：112 张、红中为皮子、只能自摸、可碰杠不可吃、杠分 + 皮子倍乘。

---

## 一、现在能做什么

| 能力 | 状态 |
|---|---|
| 112 张牌墙、洗牌、发牌、摸打、碰、明杠/暗杠/蓄杠 | 已实现，单测覆盖 |
| 红中皮子：手上带红中不能胡、打出红中强制补摸、四张全打完按暗杠 | 已实现，单测覆盖 |
| 只能自摸，无点炮、无抢杠 | 已实现 |
| 结算：自摸 10 / 点杠 10 / 暗杠 15 / 蓄杠 5，皮子两边各自 2^n 相乘 | 已实现，单测覆盖 |
| 坐庄：首局房主、谁胡谁坐庄、流局庄家不变 | 已实现 |
| 局域网联机（Bonjour 发现 + TCP 直连，房主权威） | 已实现，未联机实测 |
| 横屏 UI：大厅 / 房间 / 牌桌 / 结算 | 已实现，未在真机渲染验证 |
| 机器人补位（三缺一也能开局） | 已实现 |
| Xcode 工程 + 共享 scheme | 已生成，未在 Xcode 打开验证 |
| CI（规则单测 + App 编译，不签名） | 脚本已写，**未入库**（见下） |

---

## 二、目录

```
JianliCore/            纯规则引擎，不依赖 UIKit，可在 Linux 上编译测试
  Tile.swift           牌编码、112 张牌墙、xoshiro256** 确定性随机
  WinChecker.swift     和牌判定（含七对；含红中直接 false）
  Engine.swift         状态机：摸打 / 声明窗口 / 杠 / 结算 / 下一局
  Snapshot.swift       按座位裁剪的可见信息（别人手牌只给张数）
  Bot.swift            皮子优先打出 + 孤张评分
App/
  Info.plist           仅横屏、Bonjour 服务声明、本地网络权限文案
  Model/AppModel.swift 全局状态机：房主跑引擎，客户端只转发动作
  Net/Wire.swift       4 字节大端长度 + JSON 帧
  Net/LanHost.swift    NWListener + Bonjour 广播
  Net/LanClient.swift  NWBrowser 发现 + NWConnection
  UI/Theme.swift       配色、横屏 Metrics、牌面绘制
  UI/HomeView.swift    大厅
  UI/RoomView.swift    房间与入座
  UI/TableView.swift   牌桌
  UI/SettlementView.swift 结算
tools/gen_xcodeproj.py 从 App/ 目录树生成 pbxproj 与 scheme
docs/缺陷与待定清单.md  真实玩家视角的缺口与 9 处规则歧义
```

---

## 三、怎么跑

### Mac（出一版能装的 App）

```bash
open JianliMahjong.xcodeproj         # 选自己的 Team 直接 Run 到真机
python3 tools/gen_xcodeproj.py       # 新增 .swift 后重跑，自动挂进 target
```

### 只验规则（任何平台，含 Linux）

```bash
swift test --package-path Packages/JianliCore
# 本机实测：Executed 14 tests, with 0 failures
```

### 局域网联机

1. 四台设备连同一个 Wi-Fi（不要开「客户端隔离」的公共热点）。
2. A 点「创建房间」，B/C/D 点「加入房间」搜到 `xxx的牌桌` 入座。
3. 人不够就点「补机器人」，本地对局同样跑完整规则。

---

## 四、为什么这样架构

**房主权威（host-authoritative）**。麻将的动作顺序、声明优先级、结算都必须由单一裁判裁决，P2P 全互联会让"谁先碰"变成分布式一致性问题。所以房主那台跑完整 `MahjongEngine`，其他三台只做两件事：把动作发上去、把裁剪过的快照画出来。客户端拿不到别人的手牌，改包也改不出信息。

**规则引擎独立成 SPM 包**。它不引用 UIKit，因此可以在没有 Mac 的机器上跑单测——112 张牌数守恒、同种子重放、皮子倍乘这些最容易错的地方，靠 14 个测试兜住，而不是靠人肉点。

**确定性随机**。牌墙用 xoshiro256\*\* + splitmix64 播种，一局的全部信息由 `seed` 决定。同一个 seed 能完整重放一局，这是后面做牌谱复盘的基础。

**横屏 Metrics 归一**。设计基准 932×430pt（Pro Max 横屏），`scale = min(w/932, h/430)`，手牌宽度另算 `min((w-56)/14, h*0.205)` 保证 14 张永不换行。所有尺寸都从 `Metrics` 取，不写死。

---

## 五、规则 → 代码 对照

| 规则条款 | 落点 |
|---|---|
| 万/筒/条 1–9 各 4 张 + 红中 4 张 = 112 | `Tile.fullSet` |
| 红中是皮子，手上带红中不能胡 | `WinChecker.isWinning` 首行短路 |
| 打红中算一次杠、从牌墙尾补摸 | `Engine.discard` 的 `redDrawn` 分支 |
| 四张红中全打完算一个暗杠（15 分） | `redsPlayed == 4` → `scoreRedSweep` |
| 只能自摸 | 声明窗口只生成 `.peng` / `.gang`，无 `.hu` |
| 可碰可杠不可吃 | `ClaimOption` 无吃 |
| 自摸 10 三家各付 / 点杠 10 独付 / 暗杠 15 / 蓄杠 5 | `RuleProfile` 基数 + `ScoreReason` |
| 皮子倍乘，两边各自相乘 | `amount(base:winner:payer:)` = base × 2^赢家皮子 × 2^付钱方皮子 |
| 首局房主坐庄、谁胡谁坐庄、流局不变 | `startHand` / `startNextHand` |

---

## 六、这一轮补掉的体验缺陷

16 条全部落地：出牌倒计时与超时托管、断线与重连、房主退出广播、结算倍乘算式逐家展开、
红中计数条、尾补标记、两段式出牌防误触、七类音效与触感、听牌剩余张数、小屏专档、结算可滚动、
种子一键复制、机器人与离线标记、机器人步进降到 300ms、Bonjour 失败时的 IP 直连兜底。

## 七、还没关掉的缺口

规则上有 9 处口径没人拍板，体验上有 16 条按真实玩家视角挑出来的毛病，全部列在
[`docs/缺陷与待定清单.md`](docs/缺陷与待定清单.md)。其中三条会直接决定手感，优先级最高：

1. **打红中到底给不给 10 分**（现在只补牌 + 翻倍，不给点杠分）。
2. **四张红中全打完的 15 分，与逐张红中的杠分是否叠加**（现在只给一次）。
3. **真人没有出牌倒计时**，有人发呆就全场卡住（现在只托管机器人）。

CI 文件 `.github/workflows/ci.yml` 已在本地写好（单测 + `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`
+ 打成 `JianliMahjong-unsigned.ipa` 上传 artifact），但**推不上去**：当前 PAT 只有 `repo` 权限，
GitHub 对 `.github/workflows/*` 一律拒绝（git push 和 contents API 都是）。换一个有 `workflow` 权限的 token，或网页手动粘贴，CI 立刻开跑。
