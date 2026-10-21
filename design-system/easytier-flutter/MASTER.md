# EasyTier Flutter — 设计系统 v5「Material 3 + Expressive」

> **溯源与权威链。**
>
> 本文件最初脱胎于 `ui-ux-pro-max` 技能的生成结果（2026-10-20 12:36:06；类别
> “VPN & Privacy Tool”；设计拨盘 Variance 3/10、Motion 3/10、Density 7/10）。
> 该输出只作为**建议**：其中 Inter/藏青/绿色板与 landing-page 的“Trust & Authority”
> 版式从未被采纳。v1/v2 走的是自研「Instrument」视觉语言，v3 把它固化成 32 个自定
> 义色令牌。**v4 推翻了自定义视觉语言，改为直接实现 Google Material 3**：颜色由
> `ColorScheme.fromSeed`（Google Blue seed）推导，字体改用平台系统字体，图标换成
> Material Symbols，组件全部落在 M3 原语上。
>
> **v5 在 v4 的 M3 基线上加了一层 Google Material 3 Expressive。** 原因很直接：
> v4 虽然技术上合规，但读起来像一个普通的设置应用 —— 用户评价“太丑了”。因此按
> M3 Expressive（Google 2025 当前方向）重做了 Home 的 hero、bento 统计、表现性
> 色彩/形状/字体/动效与更高的导航栏。**M3 的 role、可访问性和组件语义一条没丢**；
> Expressive 是覆盖层，不是新的设计系统。研究参考与取舍见
> `docs/design/expressive-inspiration.md`（只解释“为什么”，不是规格；与代码冲突时
> 代码胜）。旧视觉只保留被验证过的信息架构与工程约束（§14 逐条列出）。
>
> 权威链，不要反向：
>
> 1. **`easytier-flutter/lib/core/theme/tokens.dart` + `theme.dart`** — 机器可读
>    令牌与主题。Widget 只能读它，不能内联新值。
> 2. **本文件** — 令牌背后的 M3 / Expressive 规则与取舍。
> 3. **`pages/*.md`** — 逐屏规格；只能收紧规则，不能引入新的颜色/字体/圆角/
>    时长/图标风格。
> 4. **`tokens-reference.md`** — 令牌 ↔ M3 role / M3 组件的映射表，以及 v2/v3
>    遗留物的失效清单。
> 5. `docs/design/expressive-inspiration.md` — v5 的外部参考与方向输入。
> 6. `design-system/easytier/`（Web 控制台，Vue）+ v3「Instrument」文档 +
>    `ui-ux-pro-max` 生成结果 — **历史输入**，不再管辖 Flutter 客户端。
>
> 对比度数字全部由 `easytier-flutter/tool/check_tokens.dart` 从真实的
> `ColorScheme.fromSeed` + `EtPalette` 实测生成，**不要手改**。命令见 §16。

**Status:** v5.0 · **Platforms:** Android、iOS、Linux、macOS、Windows ·
**Visual language:** Google Material 3 **+ M3 Expressive layer**（fixed seed，
非 dynamic color）·
**Theme:** light / dark 同权（M3 两套 scheme 均由同一 seed 推导）·
**Density:** M3 标准；`buildEtTheme(compact:)` 支持 compact（宽窗密度，见 §17 V7）·
**Type:** 系统 UI 字体（Android=Roboto / Apple=SF / Windows=Segoe UI / Linux=system-ui）／平台等宽（机器数据）／系统 CJK fallback；hero 用 `displayMedium` 45/52 ·
**Icons:** Material Symbols（Outlined 变量字体）

---

## 0. 这一版是什么

v4 是**换实现范式**（自定义 Instrument → Google Material 3）；v5 是在这条基线上
加**表现力层**（M3 baseline + Expressive）。两版合起来看：

| | v3「Instrument」 | v4「Material 3 baseline」 | v5「M3 + Expressive」 |
|---|---|---|---|
| 颜色来源 | 手写 32 字段自定义色板 | 一个 seed → `ColorScheme.fromSeed` → 全部 M3 role | 同上；另加固定装饰色 `EtAccent` 与渐变 `EtGradient`（`surfaceGlow` 在用，hero 由 painter 实现） |
| 颜色语义 | accent / info / warn / danger / neutral | M3 role + 两个扩展 intent | 同上；container 更积极地编码信息（bento、chip、icon badge） |
| 字体 | 自有品牌字体 | 平台系统字体；机器数据用平台等宽 | 同上；hero 提升到 `displayMedium` 45/52、w700、紧字距 |
| 图标 | Phosphor 两套字重 | Material Symbols | 同上；图标多包在 tonal squircle（`EtIconBadge`）里 |
| 深度 | 只用明度分层 | M3 elevation 0–5 + surface container | 同上；hero/横幅加 aurora 与 surfaceGlow（装饰层） |
| 形状 | 4/8/12/16/24/pill | M3 4/8/12/16/28/pill | 卡片 24、hero 32、统计块 20、icon badge squircle |
| 状态信号 | 自绘几何符号 | Symbols 图标 + role + 文字 | 同上；Home 用 connection orb + 呼吸环 |
| 动效 | 90–280ms 自定义 | M3 short/medium + emphasized | 同上；状态变化用 `EtCurves.spring` 轻微过冲 |
| 组件 | 自研原语 | M3 组件默认值优先 | 同上 + Expressive 组合件（orb / stat tile / avatar / icon badge） |
| 导航 | 64dp bar / rail | M3 默认 bar + rail | 76dp bar、更大 pill indicator；medium（≥600）就用 rail |

**判据只有一条：每个界面元素都必须能回答两个问题。**
(a) 它对应哪个 M3 role / M3 组件？(b) 如果 M3 没有，为什么我们必须自造？
答不出 (a) 又没有 (b) 的理由，就删掉。

v5 的目标是**“一个 Google 设计师打开 App 能认出这是 2025 年的 Material 3”**：
role 名称、type scale、shape/elevation/state-layer/motion 规则、组件行为都对，
而且**有一个明确的视觉主角**（Home 的 hero），不是一叠等价的灰卡片。

> **Expressive 不是“随便加装饰”。** 装饰色/渐变/发光只允许出现在 §v5 规定的位置；
> 文字永远落在稳定的 tonal 层上；所有 M3 baseline 规则（§3–§13）仍然有效。

---

## 1. 产品与受众

| | |
|---|---|
| **Who** | 自建 mesh 的人：homelab 玩家、开发者、小团队 IT。他们知道 peer、relay、NAT、CIDR、MTU 是什么。 |
| **Where** | 手机（“通没通”首选）、桌面（配置与排查大量 peer 首选）、平板（两者皆可）。 |
| **When** | 一天里多次、每次几秒的检查；偶尔长时间配置；出故障时在压力下排查。 |
| **Constraints** | 必须离线可用；DNS/VPN 状态不能是装饰；数据面可能跑在计费网络或强制门户后；App 可能是唯一能看到通道为什么断的地方。 |
| **Tone** | 冷静、事实、技术性。报告状态，不煽情。 |

**一句话：** *一台你拥有的 mesh 网络的精密仪表 —— 它告诉你网络通不通、谁在上面、
配置成了什么、以及发生过什么。*

M3 的“个性化 / 自适应 / 表现力”三原则在这里的落点是**自适应与表现力服务于可读性**：
自适应（window size class、density、深色模式）优先，色彩个性化让位于品牌与状态语义。

---

## 2. 五条硬规则

1. **一屏一个问题。** Home = 通不通、多健康？Devices = 谁在上面、谁慢？Config =
   配置成了什么、能不能安全地改？Activity = 发生了什么、什么时候？Settings =
   App 对我怎么表现？回答不了问题的元素删掉或移到拥有该问题的屏幕。
2. **一屏一个主操作。** 每屏最多一个 `FilledButton`（及其显式 async disabled 态）。
   其余操作是 `FilledButton.tonal` / `OutlinedButton` / `TextButton` / `IconButton`。
3. **机器数据用等宽字体。** IP、端口、延迟、丢包、速率、MTU、时长、版本、ID、
   密钥：`EtText.mono` + tabular figures，按列右对齐。UI 文案用 `EtText.ui`
   （平台系统 UI 字体）。中文字符**绝不放**进 mono。
4. **状态三重编码。** 永远不是只有颜色：颜色 + 图标形状 + 文字标签，三者同时表达，
   灰度截图和色盲视角下仍然可读。M3 的状态 role 是颜色的一半，Material Symbols
   的图标是形状的一半。
5. **M3 默认优先，自造要有理由。** 先问“M3 组件能不能直接用”；能就不自绘。当前
   仍有自造（§17 D1/D3/D4 等），每一处都登记了替换路径 —— 自造是债务，不是风格。
6. **表现力服务于状态，不替代状态。** Expressive 层只放大“现在发生了什么”（hero、
   orb、bento、spring），不新增语义；颜色/动效/渐变都不能成为唯一的信息载体。

---

## v5 — M3 Expressive 层

> 本节是 v4 baseline（§3–§13）之上的**覆盖层**。本节与 baseline 冲突时本节胜；
> 本节没写的，baseline 继续有效。所有 token 都在 `tokens.dart`，代码是最终事实。

### v5.1 为什么加这一层

v4 严格按 M3 baseline 实现，结果“正确但丑”：五个屏幕都是同一张 card 叠 card 的
灰列表，没有一个视觉主角，用户明确否决。M3 Expressive 是 Google 自己的当前方向
（2025），所以加回来仍然“是 Google 风格”，只是从“合规”变成“有表现力”。

### v5.2 六条 Expressive 原则

1. **Hero-first（Home）。** 首页由一个 32dp 圆角的渐变 hero 主宰：状态 badge、
   连接 orb、状态句、45px 延迟数字、唯一主操作全在里面；其余都是支撑块。
2. **Bento 统计。** 关键数字不再是灰底 KPI 行，而是三个 tonal tile
   （`EtStatTile`，radius 20）：Peers = accent、Routes = warn、Downlink = success，
   与 Home 的状态语义一致。
3. **表现性色彩，安静表面。** 更多 palette 参与（`tertiaryContainer` 用于 routes/
   Advanced 徽章，`successContainer` 用于健康，`warningContainer` 用于降级），但
   页面表面仍是 `surface`/`surfaceContainer*`：颜色在**容器**里，不在页面上。
4. **表现性形状。** 卡片 24（`EtRadius.card`）、hero 32（`EtRadius.hero`）、统计块
   20、chip/按钮 stadium、icon badge 是 squircle（半径 = size × 0.34）。圆角变大，
   层级不变：hero > card > tile > chip。
5. **表现性字体。** Home 的延迟数字用 M3 `displayMedium`（45/52，
   `EtType.expressive`），w700 + 紧字距，mono（机器数据）；页面标题
   `headlineSmall` w600；hero 以外仍按 baseline type scale。
6. **表现性动效。** 状态变化用 `EtCurves.spring`（轻微过冲的 cubic）；orb 用
   `loopRing` 脉冲；过冲只用于 hero/状态，不用于密集数据行；reduced motion 下全部
   静态（§7.4 仍然有效）。

### v5.3 四条硬约束（Expressive 的安全带）

- **装饰色不承载语义。** `EtAccent`（blue/violet/mint/cyan）只用于 aurora、orb
  glow、avatar 底色；状态含义仍由 M3 role + 图标 + 文字承担。“紫色=中继”这类
  按色相赋义的用法禁止。
- **文字永远落在稳定的 tonal 层上。** 渐变/aurora 只是背景：hero 下半部有
  `surfaceContainerHigh` 的 scrim（alpha 0.12 → 0.48），保证状态句与延迟数字的
  对比；任何新渐变必须自带这种“文字底座”。
- **渐变只有两张（+ hero 的 painter 实现）。** Home hero 的 aurora 由
  `_AuroraPainter` 画（更强的分状态控制；`EtGradient.hero` 是同一色相族的参数化
  备用定义，**当前未被消费**，见 §17 V13）；另一张是 `EtGradient.surfaceGlow`
  （Settings 的 About 组标题，最多一次）。不要在列表、卡片、导航上铺渐变。
- **发光/描边有配额。** 允许：hero aurora、连接 orb、图表线 glow、hero 1px 内高光。
  禁止：卡片重投影 / 霓虹描边 / 每个图标都发光 / 纯黑底 / 装饰性无限动画（orb
  脉冲除外）。

其余 baseline 约束不变：48dp 触摸目标、4.5:1 文字对比度、无 emoji 图标、
一屏一个主操作、reduced motion、200% 字号。

### v5.4 新增 token 与组件

| token / 组件 | 位置 | 作用 | 约束 |
|---|---|---|---|
| `EtAccent.blue/violet/mint/cyan` | `tokens.dart` | 固定品牌装饰色（**不是** M3 role） | 只做背景/底色；控件仍用 `ColorScheme` |
| `EtGradient.hero(p)` | `tokens.dart` | 参数化 hero aurora 定义（**当前未被消费**；Home 实际用 `_AuroraPainter`） | 仅 Home；若启用，替换 painter 而非叠加 |
| `EtGradient.surfaceGlow(p)` | `tokens.dart` | 安静标题光带（primary 16% → `surfaceContainerLow`） | 仅 Settings About 组 |
| `EtRadius.card = 24` | `tokens.dart` | 卡片 / `EtSurface` / `EtSection` | `theme.cardTheme` 与 kit 默认 |
| `EtRadius.hero = 32` | `tokens.dart` | Home hero 容器 | 只有 hero 级表面 |
| `EtType.expressive = 45` | `tokens.dart` | M3 `displayMedium` 45/52，Home hero 数字 | 全 App 只此一处 |
| `EtCurves.spring` | `tokens.dart` | `Cubic(0.34,1.56,0.64,1.0)` 轻微过冲 | 状态/hero；密集数据行禁用 |
| `EtTone.tertiary` | `et_ui.dart` | `tertiaryContainer`/`onTertiaryContainer` 对 | routes chip、Advanced 徽章、About 徽章 |
| `EtToneColors.resolve`（public） | `et_ui.dart` | 让 feature 复用同一 container 映射 | 禁止各屏自造映射 |
| `EtConnectionOrb` | `et_ui.dart` | 112dp orb：状态色 glow + 三层环 + 中心图标 | 装饰；语义由旁边文字承担；reduced motion 静态 |
| `EtStatTile` | `et_ui.dart` | bento 统计块（icon + mono 值 + label，tone 底，radius 20） | 值只放数字/短字符串 |
| `EtAvatar` | `et_ui.dart` | 首字母头像，按名字从 `EtAccent` 取稳定装饰色 | 装饰；首字母用 `onSurface` |
| `EtIconBadge` | `et_ui.dart` | tonal squircle 图标（32/36/40，半径 size×0.34） | section 头 / 事件行 / 设置行 |
| `EtSection.leading` / `radius` | `et_ui.dart` | 给披露 header 一个组件位（icon badge）与圆角 | 仍是 `ExpansionTile`，不嵌套 |
| Home aurora `_AuroraPainter` | `features/home/home_widgets.dart` | 分层 radial glow + 下半部 scrim；按状态调 intensity（connected 1.0 / connecting 0.85 / degraded 0.7 / idle 0.40） | 只在 hero；暗色 screen blend、亮色降 alpha |
| 导航表达 | `theme.dart` / `et_shell.dart` | `NavigationBar` 高 76、`surfaceContainer` 底、`primaryContainer` + stadium indicator；rail 品牌 tile 34dp | 保持 5 destinations；选中图标填充仍待补（§17 D2） |

### v5.5 各屏的 Expressive 落点

- **Home**：hero（aurora + orb + 45px 延迟 + badge + 主操作）→ bento 三 tile →
  traffic（带 glow 的图表）→ Peers → Network。idle/connecting/degraded 时 aurora
  自动变暗，把亮度留给“已连接”。
- **Devices**：`EtAvatar` 行、latency pill（container 底 + stadium）、顶部三枚状态
  chip（online=success / offline=neutral / routes=tertiary）、relay path 移到
  subtitle 里的 warn 文本、宽窗 `DataTable`（Status / Device / Path / Latency）。
- **Activity**：每条事件前是 `EtIconBadge`（kind → tone：connected success、
  peerJoined info、peerLeft neutral、warning warn、error danger、info accent）；
  时间戳是 mono `HH:mm`。
- **Config**：顶部实例卡横条（选中 = primary tint + 描边 + Active badge）、四个
  section 的 leading icon badge（Basic accent / Advanced tertiary / Port forward
  info / ACL success）、校验错误数用 M3 `Badge.count` 骑在 badge 上；底部 action
  bar 只有**一个** filled `Save` + 一个安静 `Run with these settings`。
- **Config 源文件编辑**：顶栏 `<>` 打开全屏 TOML source editor（本地
  `networkConfigToToml` / `parseNetworkConfigToml` 往返，支持 `[[port_forward]]`
  与 `[[acl_rule]]`）；语法错误按行号提示并禁用 Apply，未知键降级为 warning；
  Apply 只写回 draft，仍需 Save 才持久化；secret 在编辑时明文可见（本地文件语义）。
- **Settings**：分组标题为 12sp w600 `onSurfaceVariant`（无图标徽章）；行 leading
  是 36dp 中性 `surfaceContainerHighest` 圆角方块 + 彩色图标；主题/语言为行内
  `SettingsSegmentedPill`（34dp）；机器数据放 `SettingsMonoChip`
  （`surfaceContainerHighest` pill）；tappable 行尾部有 chevron。
- **Home**：hero = 单点蓝色辉光 + 同心导轨环 + 状态胶囊/24sp 状态文案/LATENCY
  数字/一个主操作；三个统计格合并为一张 segmented card（彩色仅出现在 26dp 图标块）。

### v5.6 Expressive 的验收标准

- 截图里**有一个主角**（Home hero），不是五张等价卡片；
- 至少三种 M3 container role 参与信息编码，但页面上没有“为了好看而涂色”的任意色块；
- aurora/渐变只出现在允许位置；把 aurora 换成纯 `surfaceContainerLow` 后，所有文字
  与操作仍然可读、布局不塌；
- reduced motion 打开后 orb 静止、数字不跳、语义不变；
- 48dp / 4.5:1 / 200% 字号 / 无 emoji 四条 baseline 全部照旧通过。

---

## 3. 颜色 —— M3 色彩系统

### 3.1 seed 与推导

```dart
// tokens.dart
static const seed = Color(0xFF0B57D0); // Google Blue

final scheme = ColorScheme.fromSeed(seedColor: EtPalette.seed, brightness: brightness);
final palette = EtPalette.of(scheme);  // ThemeExtension
```

- **一个 seed 推导全部 role。** light 与 dark 是同一个 seed 的两套 tonal palette；
  所有角色、container、surface 阶梯、inverse、outline、scrim 都来自 M3 算法，
  不再手写 hex。
- **不使用 dynamic color（壁纸取色）。** M3 允许，但这里刻意关闭：产品要在每台
  设备上呈现同一个品牌蓝，且对比度门禁必须可复现。dynamic color 列入未来选项。
- **Widget 读 role，不读颜色值。** 唯一入口是 `context.et.<alias>` 或
  `Theme.of(context).colorScheme.<role>`。`Color(0x…)`、`Colors.*`、`withOpacity()`
  出现在 `lib/**`（`theme/` 除外）即缺陷，§16.4 有 grep 门禁。
- **`EtPalette` 是 `ThemeExtension`，不是第二套色板。** 它只做两件事：把 M3 role
  映射成 App 里沿用的短名（§3.2），以及补两个 M3 没有的语义 role（§3.4）。
  `copyWith` / `lerp` 重新走 `EtPalette.of(scheme)`，颜色角色是离散的，不做插值。

### 3.2 角色表（实测值）

浅色 / 深色均为 `ColorScheme.fromSeed(#0B57D0)` 的真实输出，与
`check_tokens.dart` 打印一致。**表中的 hex 只是说明，代码永远读 role。**

| M3 role | Light | Dark | 用途 | kit 短名 |
|---|---|---|---|---|
| `primary` | `#495D92` | `#B2C5FF` | 主操作、选中、focus ring、连接中 | `accent` / `info` / `focus` |
| `onPrimary` | `#FFFFFF` | `#172E60` | 主操作上的文字/图标 | `onAccent` / `onInfo` |
| `primaryContainer` | `#DAE2FF` | `#304578` | tonal 容器、选中指示器、accent 徽章 | `accentQuiet` |
| `onPrimaryContainer` | `#304578` | `#DAE2FF` | 上述容器上的文字 | `accentOnTint` |
| `secondaryContainer` | `#DCE2F9` | `#404659` | 次级 tonal：info 徽章/横幅 | `infoQuiet` |
| `onSecondaryContainer` | `#404659` | `#DCE2F9` | 次级容器上的文字 | `infoOnTint` |
| `tertiary` | `#735471` | `#E1BBDD` | 第二强调：图表 tx 线、`EtTone.tertiary` 的文字/图标 | 直接读 `scheme.tertiary` |
| `tertiaryContainer` | `#FED7F9` | `#5A3D59` | Routes 统计 chip、Advanced section badge、About 徽章 | `EtTone.tertiary` 底 |
| `onTertiaryContainer` | `#5A3D59` | `#FED7F9` | 上述容器上的文字 | `EtTone.tertiary` 文字 |
| `error` | `#BA1A1A` | `#FFB4AB` | 失败、断开、破坏性操作、错误文字 | `danger` |
| `onError` | `#FFFFFF` | `#690005` | 错误填充上的文字 | `onDanger` |
| `errorContainer` | `#FFDAD6` | `#93000A` | 错误横幅/徽章底 | `dangerQuiet` |
| `onErrorContainer` | `#93000A` | `#FFDAD6` | 错误容器上的文字 | `dangerOnTint` |
| `surface` | `#FAF8FF` | `#121318` | Scaffold / canvas | `bg` |
| `onSurface` | `#1A1B21` | `#E2E2E9` | 主文字、主图标 | `text` |
| `onSurfaceVariant` | `#45464F` | `#C5C6D0` | 次级文字/图标（M3 只有一个次级文字 role） | `text2` / `text3` / `neutral` |
| `surfaceContainerLowest` | `#FFFFFF` | `#0D0E13` | 内凹井、代码/TOML 预览、图表底 | `sunken` |
| `surfaceContainerLow` | `#F4F3FA` | `#1A1B21` | 卡片（elevated card） | `surface1` |
| `surfaceContainer` | `#EEEDF4` | `#1E1F25` | 输入行、次级块、分组底 | `surface2` |
| `surfaceContainerHigh` | `#E8E7EF` | `#282A2F` | 抬升行、tooltip、snackbar 备选 | `surface3` |
| `surfaceContainerHighest` | `#E2E2E9` | `#33343A` | 中性 chip 底、选中行 | `neutralQuiet` |
| `outline` | `#757780` | `#8F909A` | **控件边界**（input/switch/分段），≥3:1 | `borderStrong` / `controlBorder` |
| `outlineVariant` | `#C5C6D0` | `#45464F` | 分隔线、装饰性描边（无对比契约） | `border` |
| `inverseSurface` | `#2F3036` | `#E2E2E9` | Snackbar / tooltip 反色底 | — |
| `onInverseSurface` | `#F1F0F7` | `#2F3036` | 反色底上的文字 | — |
| `scrim` | `#000000` | `#000000` | modal barrier | `scrim` |
| `surfaceTint` | `#495D92` | `#B2C5FF` | 交给 M3 的 elevation tint | — |

`secondary`（非 container）当前未被组件使用：M3 里它的职责是“没有 primary 那么
重的强调”，本产品没有第三个强调层级。若新增，必须先在这里登记用途。

### 3.3 角色使用规则

- **`primary` 是“操作/选中/focus”，不是“装饰”。** 主按钮、导航选中指示器、
  focus ring、连接中信号都用它。不要用它画图表、画分隔线或做 hover 色。
- **`primaryContainer` / `secondaryContainer` 是 tonal 容器。** 文字必须用对应的
  `on*Container`，不要把 `primary` 叠到 `primaryContainer` 上。
- **`tertiary` / `tertiaryContainer` 是“补充强调”。** v5 里它编码“路由/路径”类
  信息（routes chip、Advanced section badge、About 徽章）与图表的上行线。它是
  **信息容器**，不是第三个操作色 —— 不要给按钮或主操作使用。
- **surface 阶梯表达高度**（M3 的 surface container roles，取代了 tint 叠加）：
  `surface`（页面）→ `surfaceContainerLowest`（内凹）→ `Low`（卡片）→
  `Container`（输入行/次级块）→ `High`（抬升行）→ `Highest`（chip/选中行）。
  相邻层级只差一档，不要跳级；层级不是“越深越重要”。
- **控件边界用 `outline`，分隔线用 `outlineVariant`。** 后者是装饰，没有对比度
  契约；一个只有 `outlineVariant` 边界的输入框在浅色下几乎不可见（v1 的 bug）。
- **`error` 是错误/危险/断开；`warning` 是降级/需要关注。** 二者不得互换，也不得
  用 `error` 表达“未开始”（那是 `onSurfaceVariant` 的中性态）。
- **`inverseSurface` 只给 snackbar / tooltip**，这是 M3 的 inverse 语义；不要用它
  做“深色卡片”。
- **`scrim` 只用于模态。** 不要用它“压暗某个区域”，要压暗就用更低的 surface。
- **状态颜色必须与阶段绑定，不随情绪变化**（§9.1 的状态矩阵是唯一映射表）。

### 3.4 `success` / `warning` —— M3 的扩展语义

M3 没有 success/warning role。产品需要两个 M3 没覆盖的状态：**已连接/健康**
（不能借用 `primary`，primary 已被“操作”占用）与**降级/需要关注**（不能借用
`error`，error 表示失败）。因此 `tokens.dart` 增加了 8 个字段，成对提供 foreground
与 container：

| M3 扩展 role | Light | Dark | 用途 |
|---|---|---|---|
| `success` | `#137333`（Google Green 700） | `#81C995` | 已连接、健康、≤40ms 延迟 |
| `onSuccess` | `#FFFFFF` | `#00390F` | success 填充上的文字 |
| `successContainer` | `#C4EED0` | `#005322` | success 徽章/横幅底 |
| `onSuccessContainer` | `#072711` | `#A6F4B6` | success 容器上的文字 |
| `warning` | `#8F4C00` | `#FFB95C` | 降级、relay-only、高延迟 |
| `onWarning` | `#FFFFFF` | `#4A2800` | warning 填充上的文字 |
| `warningContainer` | `#FFDDB3` | `#6A3B00` | warning 徽章/横幅底 |
| `onWarningContainer` | `#2D1600` | `#FFDDB3` | warning 容器上的文字 |

**契约：**

- 它们与 M3 role **同权**：必须走同一套对比度门禁（§3.5），必须同时提供 container
  对，必须遵守 §3.6 的状态层规则。
- **浅色 `success` 必须深到能做 14px 标签文字**。`#1E8E3E` 一类的 Google Green 600
  在白底只有 **4.21:1**，达不到正文 AA；所以浅色取值是 `#137333`（5.95:1）。
  如果以后要回到更亮的绿，只能把它降级为“纯图形 role”（图标/圆点，3:1），
  并且状态标签必须改回 `onSurface`。
- 深色下的绿/琥珀是 Google 语义色（`#81C995` / `#FFB95C`），保持高亮度以便在
  `#121318` 上读得清。

### 3.5 实测对比度（WCAG 2.1 AA）

`check_tokens.dart` 构建真实的 light/dark `ColorScheme.fromSeed` + `EtPalette`，
测量 UI 实际会渲染的配色对，**74/74 断言通过**。文字 4.5:1，图形/控件边界 3:1。

| Pair | Light | Dark |
|---|---:|---:|
| `onPrimary` / `primary` | 6.43 | 7.72 |
| `onPrimaryContainer` / `primaryContainer` | 7.25 | 7.25 |
| `onSecondaryContainer` / `secondaryContainer` | 7.28 | 7.28 |
| `onSurface` / `surface` | 16.31 | 14.39 |
| `onSurface` / `surfaceContainerLow` | 15.58 | 13.32 |
| `onSurfaceVariant` / `surface` | 8.89 | 10.92 |
| `onSurfaceVariant` / `surfaceContainerLow` | 8.50 | 10.11 |
| `onSurfaceVariant` / `surfaceContainerHighest` | 7.27 | 7.30 |
| `primary` / `surface` | 6.11 | 10.89 |
| `error` / `surface` | 6.13 | 10.93 |
| `onError` / `error` | 6.46 | 7.72 |
| `onErrorContainer` / `errorContainer` | 7.24 | 7.24 |
| `warning` / `surface` | 6.23 | 10.91 |
| `onWarning` / `warning` | 6.56 | 7.74 |
| `success` / `surface` | 5.65 | 9.47 |
| `onSuccess` / `success` | 5.95 | 6.73 |
| `onSuccessContainer` / `successContainer` | 12.61 | 7.18 |
| `onWarningContainer` / `warningContainer` | 13.25 | 7.26 |
| `onInverseSurface` / `inverseSurface` | 11.61 | 10.20 |
| `outline` / `surface`（≥3.0） | 4.24 | 5.85 |
| `outline` / `surfaceContainerLow`（≥3.0） | 4.05 | 5.42 |
| `outline` / `surfaceContainer`（≥3.0） | 3.84 | 5.18 |
| `outline` / `surfaceContainerHigh`（≥3.0） | **3.63** | 4.53 |

**最紧的余量（不要“优化”掉）：** 浅色 `outline` / `surfaceContainerHigh` =
**3.63:1（+0.63）**，浅色 `onPrimary` / `primary` = 6.43（+1.93），浅色
`success` / `surfaceContainerLow` = 5.40（+0.90）。完整表由脚本打印。

**不参与断言的两项（脚本以 INFO 打印）：**

- **禁用态** 按 M3 = `onSurface` 38% 叠在 surface 上：浅色 2.35:1 / 深色 3.04:1。
  WCAG 明确豁免禁用控件，所以**不要**为了凑 4.5 去改 disabled 颜色（那会让禁用态
  看起来像可点）。禁用必须同时有形状/文字线索（§11）。
- **`outlineVariant` 分隔线** 1.61/1.98：装饰元素，没有对比契约；不要拿它当控件边界。

### 3.6 状态层（state layers）

M3 用**叠加层**表达交互态，不改变组件底色：

| 状态 | 叠加不透明度 | 说明 |
|---|---:|---|
| hover | 8% | 桌面指针悬停 |
| focus | 10% | 键盘 focus |
| pressed | 10% | 按压 |
| dragged | 16% | 拖拽 |

- 叠加颜色取该组件的 **on 色**（如 primary 容器上用 `onPrimary`），透明度从
  `ThemeData` 的 M3 默认值来。**不要手写 `withOpacity`**：Material 组件已经做了，
  手写会双重叠色。
- **禁用态**：content 38%，container 12%（M3 数字）。`EtPalette.textDisabled`
  就是 `onSurface.withValues(alpha: 0.38)`，代码里唯一允许出现的透明度。
- 状态层不得表达**业务状态**：连接中/已连接/降级是颜色 role + 图标 + 文字，
  不是 hover 叠加。
- 选中（selected）不是状态层，它是 role 变化：导航选中 = `primaryContainer`
  指示器 + `onPrimaryContainer` 图标；列表选中行 = `surfaceContainerHighest`。

### 3.7 深色模式

- light / dark 由同一个 seed 推导，**两者都是正式主题**，不允许“只调好一个”。
- 深色 surface 不是纯黑（`#121318`），这是 M3 的 dark surface，避免 OLED 上的
  硬边与眩光；不要回退到 `#000000`。
- 深色下的语义色必须重新取（M3 自动给出更亮的 tonal 值），不能把浅色值直接反转。
- **发光只允许在 v5 规定的四处**：hero aurora、连接 orb、图表线 glow、hero 1px
  内高光（§v5.3）。除此之外 M3 用 tonal surface + elevation 表达层级，不用发光；
  卡片重投影、霓虹描边、每个图标都发光都是缺陷。
- **aurora / 渐变上的文字必须落在 scrim 或实色容器上**（hero 下半部的
  `surfaceContainerHigh` scrim），不能让文字直接压在最亮的 blob 上。

### 3.8 表现性装饰色与渐变（v5）

这些**不是 M3 role**，只做背景/底色，控件不得使用：

| token | 值 | 用在哪里 | 禁止 |
|---|---|---|---|
| `EtAccent.blue` | `#3D7BFF` | hero aurora 主 blob、avatar 底色 | 按钮、文字、边框 |
| `EtAccent.violet` | `#8B5CF6` | hero aurora 第二 blob、avatar 底色 | 同上 |
| `EtAccent.mint` | `#25E0B0` | avatar 底色 | 同上 |
| `EtAccent.cyan` | `#22D3EE` | hero aurora 第三 blob（“success”位） | 同上 |
| `EtGradient.hero(p)` | primary 30% + tertiary 22% + success 14% 叠在 `surfaceContainerHigh` | 参数化备用定义（当前未消费；Home 用 `_AuroraPainter`） | Home 以外任何地方 |
| `EtGradient.surfaceGlow(p)` | primary 16% → `surfaceContainerLow` | Settings About 组标题（最多一次） | 列表/卡片/导航 |

规则：

- `EtAccent` 按 `name.codeUnits` 求和取模，为头像给出**稳定**的装饰色；同一个名字
  永远同一个颜色，但它**不代表任何状态**。
- 装饰色的对比度**不由 `check_tokens.dart` 断言**（它们不承载文字）。规则是：
  文字只能放在实色容器或 scrim 上，装饰层本身不参与文字对比度（§17 V3 是待补的
  自动断言）。
- 渐变必须在暗色/亮色两套主题下分别调 alpha；亮色下 aurora 换 `srcOver` 且降低
  alpha，不能把亮色主题涂成荧光板。

---

## 4. 字体 —— M3 type scale

### 4.1 字体族 —— 系统字体，不内嵌

**文本字体一律使用操作系统的系统 UI 字体**：Android 是 Roboto，Apple 平台是 SF，
Windows 是 Segoe UI，Linux/其他由 fontconfig 决定。App **不内嵌任何文本字体**，
因此客户端会跟随用户的系统排版偏好，也避免包体与首帧闪烁。

| 用途 | 字体来源 | 说明 |
|---|---|---|
| **UI 文案、标题、标签、正文** | 平台系统 UI 字体（`EtText.ui` 不指定 family，继承主题 Typography） | M3 `Typography.material2021` 会按平台选择默认字体栈 |
| **机器数据**（IP、端口、延迟、丢包、速率、MTU、ID、版本、时长、密钥） | 平台等宽：Android/Linux `monospace`、Apple `Menlo`、Windows `Consolas` | `EtText.mono` 按 `defaultTargetPlatform` 解析；等宽 + 右对齐 + tabular 数字 |
| **CJK fallback** | 平台自带 CJK 字体（Noto Sans CJK / PingFang / 微软雅黑 / 文泉驿等） | `EtText.uiFallback` 只是系统字体名列表，不是随包字体 |
| **图标** | Material Symbols（`material_symbols_icons` 包自带图标字体） | 图标字体是 M3 规范的一部分，不是文本字体 |

规则：

- **禁止把文本字体打包进 App**（`pubspec.yaml` 不得出现 `flutter.fonts` 的文本
  family，`assets/fonts/` 不得存在于发布产物）。用户要的是系统字体。
- **禁止网络字体**（Google Fonts / 任何 CDN）：离线可用、无首帧闪烁。
- **等宽只给机器数据。** 混排标签必须拆：中文用 `EtText.ui`，数字/ID 用
  `EtText.mono`；用 `Text.rich` 两个 `TextSpan`，不要拼成一个字符串。
  （平台等宽字体可能没有 CJK 字形，混排会 tofu。）
- **中文字体是 fallback，不是第二套排版。** 行高、字号、字重都由同一 `EtText`
  构造器决定，中文只影响字形覆盖。
- **数字对齐**：`EtText.mono` 启用 `FontFeature.tabularFigures()`；UI 文案不加
  tabular（比例数字更自然）。
- **权重**：只使用系统字体实际提供的 400/500/700；不要依赖合成粗体。
- **测试渲染**：`flutter_test` 没有系统字体，goldens 会退化为 Ahem 方块，因此
  `test/fixtures/fonts/` 保留三份 **仅测试用** 的字体文件（Roboto / Roboto Mono /
  Noto Sans SC 子集），只在测试 runner 里 `FontLoader` 加载；它们不进入 App 包。
  这是 golden 的确定性夹具，不是产品字体契约。

**字体资产契约（校验见 §16.3）：** `pubspec.yaml` 不含文本 `fonts:` 段；
`assets/fonts/` 不存在；`test/fixtures/fonts/` 存在且仅被测试代码引用。

### 4.2 字号表（M3 scale）

M3 的 type scale 有 15 个 role；本 App 用其中 9 个（缺的 role 不硬造，直接用
对应组件的默认 `textTheme`）：

| M3 role | 字号 / 行高 | M3 默认字重 | App 令牌 | 用途 |
|---|---|---:|---|---|
| `displayMedium` | 45 / 52 | 400 | `EtType.expressive` | **v5：Home hero 延迟数字**（w700，mono，height 1.05） |
| `displaySmall` | 36 / 44 | 400 | `EtType.hero` | 大数字（v5 里 Home 已改用 45，此 token 留给其他大数值） |
| `headlineMedium` | 28 / 36 | 400 | `EtType.display` | 大状态数字（非 hero） |
| `titleLarge` | 22 / 28 | 400 | `EtType.headline` | App bar 标题、页面标题 |
| `titleMedium` | 16 / 24 | 500 | `EtType.title` | 卡片标题、区块标题 |
| `bodyLarge` | 16 / 24 | 400 | `EtType.body` | 正文 / 表单值 |
| `bodyMedium` | 14 / 20 | 400 | `EtType.bodySm` | 密排行、列表副标题 |
| `bodySmall` | 12 / 16 | 400 | `EtType.caption` | 辅助说明、单位 |
| `labelSmall` | 11 / 16 | 500 | `EtType.micro` | 徽章、极小标签 |

**注意 16 出现两次不是笔误**：M3 的 `bodyLarge` 与 `titleMedium` 都是 16px，差别
在行高（24 vs 24）与字重（400 vs 500）。App 用 `EtType.body` / `EtType.title`
区分“正文 400”与“标题 500”。

- **正文不小于 16**（`bodyLarge`）。密排列表可用 14，但正文和主数值不得低于 16。
- **caption / micro 不承载关键信息**：只放单位、时间戳、辅助说明。
- **行高来自 M3，不手写像素值**；`EtText` 接受无单位倍数：正文默认 1.5，≥22 的
  role 默认 1.27（对应 M3 36/44），hero 显式覆盖为 1.05（45px 数字的紧行高）。
- **表现性排版只用于 hero。** `EtType.expressive`（45）+ w700 + 紧字距只给 Home
  延迟数字；页面标题是 `headlineSmall` w600（AppBar），正文/列表仍是 baseline
  字号。把 45px 用到卡片或列表上是缺陷。
- **字距默认 0**；micro 标签最多 +0.5。M3 不鼓励为每种字号自定义 letter-spacing。
- **文本缩放**：支持到 200%（`MediaQuery.textScaler`），不写死文本容器高度，
  不用 `FittedBox` 压缩关键数值；放不下就换行或换成详情行，绝不裁切。
- 主题层：`buildEtTheme` 不指定文本 family（继承平台 Typography），只注入系统 CJK fallback 列表；其余 role
  全部走 Flutter 的 M3 默认 type scale。组件的 `Text` 尽量不传自定义 `fontSize`，
  用 `Theme.of(context).textTheme.<role>`。

---

## 5. 形状 —— M3 shape scale

M3 的 shape scale 是 0 / 4 / 8 / 12 / 16 / 28 / full；v5 在其上增加两个**表现性
尺寸**（仍是 M3 形状语言的一部分，只是更大的圆角）：

| M3 shape | 值 | token | 适用 M3 组件（代码现状） |
|---|---:|---|---|
| none | 0 | — | 全出血表面（app bar、nav bar、rail、divider） |
| extra small | 4 | `EtRadius.xs` | 文本框（outlined）、snackbar |
| small | 8 | `EtRadius.sm` | chip / 徽章、菜单 |
| medium | 12 | `EtRadius.md` | 内联横幅、旧版卡片（保留 token） |
| large | 16 | `EtRadius.lg` | surfaceGlow 标题带、大容器 |
| **expressive card** | **24** | **`EtRadius.card`** | **卡片 / `EtSurface` / `EtSection`（`theme.cardTheme`）** |
| extra large | 28 | `EtRadius.xl` | dialog、modal bottom sheet（M3 默认值） |
| **expressive hero** | **32** | **`EtRadius.hero`** | **仅 Home hero 表面** |
| full | 999 | `EtRadius.pill` | 胶囊按钮、latency pill、summary chip、导航指示器 |

另有三个**组件内**形状常量（不是全局 token）：统计块 20、icon badge squircle
半径 = `size × 0.34`（32→11、40→14）、rail 品牌 tile 11。它们是 Expressive 的
局部配方，不要扩散成“到处 20/11”。

规则：

- **圆角层级：hero(32) > card(24) > stat tile(20) > chip/pill。** 子元素圆角 =
  父圆角 − inset，永远不大于父元素；全出血表面是直角。
- **组件用 M3 默认形状，不逐个覆盖。** `FilledButton` 默认就是 stadium；
  dialog / sheet 28；outlined text field 4；snackbar 4。
- **28 只属于 dialog/sheet。** 卡片一旦 28 就不再是 M3 的 card；hero 的 32 只给
  Home hero，不能复用到别的卡片。
- M3 的 nav bar 选中指示器是 full/pill（stadium），不是圆角矩形。

---

## 6. 高度与色调表面（elevation & tonal surfaces)

M3 用 **elevation level + surface container role** 表达高度，取消 v3 的
“只用明度分层、全场 elevation 0”。

| M3 level | 表现 | 本 App 的用途 |
|---:|---|---|
| 0 | `surface` | 页面 canvas、app bar（未滚动） |
| 1 | `surfaceContainerLow` | **卡片**（elevated card，`elevation: 1`） |
| 2 | `surfaceContainer` | 输入行、次级块 |
| 3 | `surfaceContainerHigh` | 抬升行、tooltip；app bar scrolled-under |
| 4 | `surfaceContainerHighest` | 选中行、中性 chip |
| 5 | 最高 tint | 本 App 不使用 |

组件映射（`theme.dart` 的实际行为）：

| 组件 | M3 规格 | 代码 |
|---|---|---|
| Top app bar（small） | `surface`，level 0；内容滚到下面时 level 3；标题 `headlineSmall` w600 | `appBarTheme`: `surface`、`elevation 0`、`scrolledUnderElevation 3`、`centerTitle false`；`EtPage` 用 `headlineSmall` + `letterSpacing -0.4`，`toolbarHeight: kToolbarHeight`（64） |
| Card（elevated） | `surfaceContainerLow`，level 1，**radius 24（Expressive）** | `cardTheme`: 颜色/24 圆角/`margin: zero` |
| Home hero（自定义表面） | `surfaceContainerLow` 底 + aurora + 下半部 scrim，**radius 32 + 1px primary 22% 描边** | `HomeHero` 的 `Container`（`EtRadius.hero`）；不是 Card，但遵守同一个“文字落在稳定 tonal 层”规则 |
| Navigation bar | `surfaceContainer` 底，**height 76**，stadium `primaryContainer` indicator，`labelMedium`（选中 w600） | `navigationBarTheme`（v5 提高高度与指示器） |
| Navigation rail | `surface` 底，`primaryContainer` indicator，选中图标/文字 w600 | `navigationRailTheme`；品牌 tile 34dp（`Symbols.shield`） |
| Dialog | `surfaceContainerHigh`，level 6（M3 默认），radius 28 | 只覆盖 shape；背景/高度保留 Flutter M3 默认 |
| Modal bottom sheet | `surfaceContainerLow`，level 1，radius 28，drag handle | `bottomSheetTheme`: 28 + `showDragHandle: true` |
| Snackbar | `inverseSurface`，floating，radius 4 | `snackBarTheme`: floating + 4 |
| Outlined text field | 1dp `outline`；focus 2dp `primary`；radius 4 | `inputDecorationTheme` |
| 底部 action bar（Config） | `surfaceContainer` + **elevation 3**，作为滚动区兄弟节点 | `_BottomActionBar` 的 `Material`；一个 filled `Save` + 一个 `TextButton` |
| Filled button | `primary` 容器，stadium，40dp 视觉 / 48 触摸目标；disabled = `onSurface` 38% | `EtPrimaryButton`（v5 已修正 disabled 前景色，见 §17） |

规则：

- **阴影不是层级工具。** M3 的 elevation 是“色调 + 极轻阴影”，不是重投影；除了
  Config 底部 action bar（elevation 3，浮在滚动内容之上）之外不要自定义
  `BoxShadow`，不要用 `elevation: 8`“让卡片浮起来”。
- **玻璃/aurora 属于 hero，不属于层级。** hero 的 1px 内高光与 aurora 是装饰，
  不能让 hero 看起来比 dialog 更“高”；高度仍由 role/圆角表达。
- **模态用 scrim + 更高的 surface container + 大圆角区分**，不是靠投影。
- **`surfaceTintColor` 保留给 M3 的 tint 机制**（app bar/card 显式设置），
  不要手写 tint 色值。
- Popup menu / dropdown 用 `surfaceContainer` 或 M3 默认的 `PopupMenuTheme`，
  不要自造“深色浮层”。

---

## 7. 动效 —— M3 motion

动效的职责是解释**什么变了、去了哪里**，不是装饰。工具类 App 里 90% 的交互应当

### 7.3 v5.x 动效与细节落地清单

实现位置：`lib/core/ui/et_motion.dart`（`EtEnter` / `EtPressScale` / `EtHaptics`）
与各屏页面。所有一次性动效在 `EtDuration.hero`（280ms）或更短内完成，
保证 golden 在 320ms 的固定 pump 后看到终态；reduced motion 下全部降为 0。

| 场景 | 动效 | 规格 |
|---|---|---|
| 切换底部/侧边导航 | 内容淡入 + 上移 12dp | `EtDuration.base` 200ms，`EtCurves.enter`；IndexedStack 保留各页状态 |
| 首页 hero 首次/状态变化 | 徽章 → orb → 状态文案 → 延迟 → 主操作分段入场 | 280ms，Interval 0/0.08/0.16/0.24/0.32，上移 10dp |
| hero 主操作按压 | 缩到 0.98 再回弹 | 120ms，`EtCurves.exit` |
| 主题/语言胶囊、筛选 chips | 容器颜色渐变 + 选中字重 | 150ms，`EtCurves.standard` |
| 页面副标题、状态行、badge、mono 值 | AnimatedSwitcher 淡入淡出 | 150ms |
| 流量图 | 最新采样点的呼吸光环 | 1400ms 循环；reduced motion 静态 |
| 空状态 / 闪屏 | 淡入 + 轻微上移/缩放 | 200ms / 300ms 一次性 |
| EtSection 展开箭头 | 旋转 180° 而非换字形 | 150ms |
| 触感 | 导航切换、筛选、复制、保存、连接 | `EtHaptics.selection()` / `.impact()`（桌面/测试静默） |

细节约定：

- Activity 的导航角标只统计「未读事件」，进入 Activity 即清零（商业 App 常规行为）；
- 删除网络属于破坏性操作，从 Config 顶栏移到 `⋮` 溢出菜单，避免与 `+` 相邻误触；
- 所有动效都是解释性的：颜色/动效从不单独承载状态，文字与图标始终同步变化。

“立刻完成”。

### 7.1 时长与缓动

M3 的 duration token 是短/中/长/超长四组；本系统只用短与中：

| M3 token | 时长 | App token | 用途 |
|---|---:|---|---|
| short2 | 100 ms | `EtDuration.instant` | 按压、hover、开关、ripple |
| short3 | 150 ms | `EtDuration.fast` | 退出、关闭、item 移除（必须比进入快） |
| short4 | 200 ms | `EtDuration.base` | 进入、展开、对话框内容、路由 |
| medium2 | 300 ms | `EtDuration.slow` | 状态变化、主题切换、数值变化 |

缓动（M3 命名）：

| M3 easing | 曲线 | App token |
|---|---|---|
| standard | `Cubic(0.2, 0, 0, 1)` | `EtCurves.standard` |
| emphasized decelerate | `Cubic(0.05, 0.7, 0.1, 1)` | `EtCurves.enter` |
| emphasized accelerate | `Cubic(0.3, 0, 0.8, 0.15)` | `EtCurves.exit` |
| standard（hover） | `Cubic(0.2, 0, 0, 1)` | `EtCurves.hover` |
| **spring（Expressive）** | `Cubic(0.34, 1.56, 0.64, 1.0)` | **`EtCurves.spring`** |

规则：**到达时减速，离开时加速**；退出时长必须短于进入。不要“一个 easing 用到底”。

**v5 spring 的用法：** 只用于**状态变化与 hero 时刻**（Home 延迟数字的
`AnimatedSwitcher`、连接/断开时的 hero 内容切换）。曲线在中段轻微过冲（约 2–3%），
给“状态刚刚改变”一点物理感；**不要**用在密集数据行、列表重排、滚动或文字位移上
（会显得廉价且影响可读性）。reduced motion 下时长置 0，直接落终态。

### 7.2 循环动效（唯一允许重复的地方）

| token | 周期 | 用途 | 缓动 |
|---|---:|---|---|
| `EtDuration.loopSpin` | 700 ms | 不定进度 | linear |
| `EtDuration.loopSweep` | 900 ms | 顶部刷新细线 | linear |
| `EtDuration.loopShimmer` | 1400 ms | 骨架 shimmer | linear |
| `EtDuration.loopBreathe` | 1400 ms | “Connecting…”呼吸（语义信号） | standard |
| `EtDuration.loopPulse` | 1400 ms | 状态点脉冲 | standard |
| `EtDuration.loopRing` | 2000 ms | 状态环扩散 | standard |

**重复只允许用于“进度”和“状态”。** 装饰性无限动画禁止。永远不要让状态依赖动画：
动画没跑起来时，状态也必须是正确的。

### 7.3 组合规则

- 只动 `transform` / `opacity` / `color` / `backgroundColor`；不动 width/height/
  margin/top/left（会触发布局）。
- **一帧只讲一个故事**：同时最多两组不相关元素运动；列表进入按 20–40ms 错峰，
  整体 ≤400ms，再长就整块淡入。
- 按压反馈是 `scale(0.98)` 或颜色/状态层变化，不做把邻居推开的位移。
- 路由转场用平台默认（`MaterialPageRoute`）；sheet 用主题化的
  `showModalBottomSheet`。不要自定义“华丽转场”。
- 不依赖 `AnimationController` 完成来保证正确性：被取消时立刻写入最终语义状态。

### 7.4 减少动效（reduced motion）

`context.etReducedMotion` 是唯一入口（`MediaQuery.maybeDisableAnimationsOf`
或平台 `accessibilityFeatures.disableAnimations`）。为 true 时：

- 所有转场时长变 0 或跳过；`TweenAnimationBuilder` 首帧就渲染终态。
- 循环变成静态：spinner 可用静态进度图标；骨架是实心块（不是空框）；
  “Connecting…”显示静态图标 + 文字。
- **语义信号不消失**：状态是颜色 + 图标 + 文字，静态形态仍然表达同一件事。
- 永远不要把含义只编码在动效里。

---

## 8. 图标 —— Material Symbols

- **唯一图标族：Material Symbols**（`package:material_symbols_icons`,
  `Symbols.*`）。这是 Google 官方 M3 图标集，变量字体带 `FILL`、`wght`、`GRAD`、
  `opsz` 轴。
- `Symbols.*` = **Outlined** 变体（weight 400、fill 0），这是 M3 的默认外观。
  `Rounded` / `Sharp` 变体一律不用，避免风格混杂。
- **已选中的导航目的地图标应使用 filled 变体**（`FILL 1`）；未选中用 outlined。
  ⚠️ 当前 `EtDestination.selectedIcon` 与 `icon` 相同（§17 D2）。
- **v5：图标经常包在 `EtIconBadge` 里**（tonal squircle，32/36/40）。这是 Expressive
  的“图标有底座”配方，用于 section 头、事件行、设置行；装饰性圆点/几何符号仍然
  不允许自绘。`EtIconBadge` 的颜色来自 `EtTone` 的 container 对，不直接用 accent。
- **禁止 emoji 与 Unicode 字形当图标**（✓ ⚠ ● → 都是文字字形，不是图标）。
  状态用 `Symbols.check_circle` / `Symbols.warning` / `Symbols.error` 等。
- **禁止混用 `Icons.*`**（Flutter 自带的 Material Icons）：两套图标字体的
  光学尺寸不同，混用会看出“不是一个系统”。§16.4 有 grep 门禁。
- 尺寸：24（导航、app bar 动作，M3 默认）、20（内联/leading）、18（按钮内）、
  16（密排表格）。图标不随文字缩放而缩放；要更大就换更大的文本 role。
- 颜色：默认 `onSurfaceVariant`；选中/激活 `primary`（或对应 container 的
  `on*Container`）；语义色只在图标**本身就是信号**时使用，并且必须有文字伴随。
- 仅图标控件必须有语义标签（`Tooltip` 或 `Semantics(label:)`）且 ≥48×48 触摸目标；
  旁边文字已经说明含义的装饰图标用 `ExcludeSemantics`。
- 目的地图标映射（必须与 §10 一致）：

| 目的地 | Material Symbol |
|---|---|
| Home | `Symbols.shield` |
| Devices | `Symbols.devices` |
| Config | `Symbols.tune` |
| Activity | `Symbols.monitoring` |
| Settings | `Symbols.settings` |

常用动作/状态：`check_circle`（已连接）、`progress_activity`（连接中）、
`warning`（降级）、`link_off`（断开）、`radio_button_unchecked`（未运行）、
`monitor_heart`、`report`、`verified_user`、`person_add`/`person_remove`、
`search`、`close`、`filter_alt`、`swap_vert`、`refresh`、`power_settings_new`、
`cable`、`code`、`add`、`delete`、`chevron_right`、`expand_more`/`expand_less`、
`arrow_downward`/`arrow_upward`、`menu_book`、`sync_alt`、`gpp_bad`、`history`。
名字缺失时从 Material Symbols 官方库挑最近的，登记到本表，不要自造 SVG。

---

## 9. 组件词汇（kit → M3）

`lib/core/ui/` 的每个组件都是 M3 原语的薄组合；**组件名是 App 的，内部实现必须
是 M3 的**。所有组件只读 `context.et` / `Theme.of(context)` / `EtSpace` /
`EtRadius` / `EtType` / `EtText` / `EtDuration`。

| App 组件 | M3 对应 | 契约 |
|---|---|---|
| `EtShell` | `NavigationBar`（compact）/ `NavigationRail`（medium+） | `etUseRail` = ≥600 用 rail；5 个目的地；`Badge.count` 显示活动数；bar 76 高、`surfaceContainer` 底、`primaryContainer` + stadium indicator；rail 在 ≥1200 扩展带文字（M3 large） |
| `EtPage` | `Scaffold` + `AppBar`（small top app bar） | 标题 **`headlineSmall` w600**（v5）；可选副标题；`toolbarHeight: kToolbarHeight`（64）；`actions` 放 `IconButton` |
| `EtScrollBody` | 布局原语（非组件） | 居中、`maxWidth: 1040`、块间距 16 |
| `EtSurface` | `Card`（elevated）+ `InkWell` | level 1、`surfaceContainerLow`、**radius 24**；可点整卡 |
| `EtSection` | `Card` + `ExpansionTile` | **radius 24**、新增 `leading` 组件位（icon badge）；一级披露；默认展开/折叠由屏幕决定；禁止嵌套第二层 |
| `EtTone` / `EtToneColors.resolve` | container role 映射 | accent/info/**tertiary**/warn/danger/neutral/success → (`*Container`, `on*Container`)；feature 复用，不自造映射 |
| `EtAvatar` | 无 M3 组件（Expressive 配方） | 首字母圆形头像；装饰色来自 `EtAccent`，文字用 `onSurface`；装饰 `ExcludeSemantics` |
| `EtIconBadge` | tonal squircle（无 M3 组件） | 32/36/40，radius = size×0.34；颜色来自 `EtTone`；用于 section 头/事件行/设置行 |
| `EtConnectionOrb` | 无 M3 组件（Expressive 配方） | 112dp；状态色 glow + 三层环 + 中心 Symbols 图标；`loopRing` 脉冲；`ExcludeSemantics`（语义由文字承担）；reduced motion 静止 |
| `EtStatTile` | 无 M3 组件（bento 配方） | icon + mono 值 + label，tone 容器底，radius 20；值只放数字/短字符串 |
| `EtTile` | `ListTile` | 设置行；leading 图标、trailing 默认 `chevron_right`；破坏性行用 `error` 文字并二次确认 |
| `EtSwitchRow` | `SwitchListTile` | 标题 + 副标题 + 开关；`dense: true`，行高 ≥48 |
| `EtTextField` | `TextFormField`（outlined） | 浮动 label 永远可见；`errorText` 与字段绑定；长值换行不裁切 |
| `EtPrimaryButton` | `FilledButton` / `FilledButton.tonal` | 每屏最多一个 filled；48 高；busy = 图标保留 + inline spinner + 文案不变；disabled 前景 = `onSurface` 38%（v5 已修正） |
| `EtIconButton` | `IconButton` | 必须有 tooltip；48×48 目标；颜色默认 `onSurfaceVariant` |
| `EtBadge` | 自定义 chip（M3 无“小徽章”组件） | container role + `on*Container` 文字；radius 8；⚠️ 高度约 20，M3 chip 是 32（§17 D3） |
| `EtBanner` | 自定义内联横幅（M3 无 banner 组件） | container role 底色 + 图标 + 标题/说明 + 可选 action；**不是** snackbar，不浮层 |
| `EtSignal` | 状态信号（M3 无对应组件） | 5 态，图标 + role 颜色 + 文字；颜色永不单独承担语义（§9.1）；hero 内改用 `EtBadge` + orb |
| `EtKpi` | 数据展示（M3 无对应组件） | label（caption）+ 数值（mono，`headlineMedium`）；label 与 value 分离 |
| `EtPeerRow` | `ListTile`（两/三行） | **leading = `EtAvatar` 40**；hostname + IP（mono）；**relay path 在 subtitle**（warn 文本）；**trailing = latency pill**（Home/Devices 列表里是 14% 语义色叠 `surfaceContainerHigh` 的手工合成；宽窗/详情用 `LatencyPill` 的 container —— 差异见 §17 V12）；离线 peer 保留 |
| `EtEmptyState` | 自定义空状态 | 图标（装饰）+ 一句解释 + 恰好一个下一步；绝不只写“No data” |
| `EtSpeedGraph` | 自定义数据可视化（M3 有图表指南，无组件） | 60s rx/tx 面积图；读 `primary`/`tertiary`；**line glow + 末点圆点**（v5）；`CustomPaint`；有文本等价物与 `Semantics` |
| `EtTrafficLegend` | 数据展示 | 方向图标 + 标签 + mono 数值 |
| `showEtSheet` | `showModalBottomSheet` | `isScrollControlled`、`useSafeArea`、M3 drag handle、radius 28 |
| 对话框 | `AlertDialog` | 保留 M3 默认（`surfaceContainerHigh`、radius 28、scrim）；破坏性确认写明对象与后果 |

### 9.1 状态矩阵（Home / Devices 共用）

| 阶段 | Material Symbol | role | 文字（canonical） | 动效 |
|---|---|---|---|---|
| off | `radio_button_unchecked` | `onSurfaceVariant`（neutral） | “Not running” / “Stopped” | 无（hero aurora 变暗到 0.40） |
| connecting | `progress_activity` / `sync` | `primary` | “Connecting…” | `EtConnectionOrb` 环脉冲（`loopRing`，intensity 0.85） |
| connected | `check_circle` | `success` | “Connected” | orb 环脉冲（intensity 1.0）；hero 满亮度 |
| degraded | `warning` | `warning` | “Degraded — relay only” / 具体原因 | 无（intensity 0.7） |
| disconnected / error | `link_off` / `error` | `error` | “Disconnected — {cause}” | 无（intensity 0.40） |

reduced motion 下所有 orb 环静止、数字不跳、aurora 仍在但不动；语义完全不变。

空数据不是阶段：它是独立状态，有自己的文案与下一步（`EtEmptyState`）。

**三编码不变式：** 去掉颜色后仍能用图标形状 + 文字区分五个阶段；去掉动效后
语义不变；语音朗读拿到的是文字标签，不是“icon”。

### 9.2 每屏主操作

| 屏幕 | 主操作（唯一 filled） | 次操作 |
|---|---|---|
| Home | Connect / Reconnect / Disconnect（hero 内唯一动作，v5 三者都是 filled） | 无（断开就是 hero 里的动作） |
| Devices | —（导航屏） | 搜索、排序 `IconButton`；peer 行 |
| Config | **Save**（底部 action bar 的 filled pill） | **Run with these settings**（`TextButton`，安静）；Reset/Discard 在横幅里 |
| Activity | — | 过滤 `MenuAnchor`、清空（破坏性） |
| Settings | — | 行内 segmented/dropdown；破坏性删除走确认对话框 |

---

## 10. 布局与信息架构 —— M3 window size classes

M3 的窗口尺寸类别（v5 已按 M3 数字对齐）：

| Class | 宽度 | M3 推荐布局 | 本 App（v5） |
|---|---|---|---|
| compact | < 600 | bottom `NavigationBar` | bottom bar（`etUseRail == false`） |
| medium | 600–839 | `NavigationRail` | **rail**（`etUseRail`） |
| expanded | 840–1199 | `NavigationRail` / 双栏 | rail + `etDesktop` 双栏 |
| large | 1200–1599 | rail + 更宽内容 | rail 扩展带文字（≥1200） |
| extra-large | ≥ 1600 | 同上，内容不无限拉宽 | 同上，内容 ≤1040 |

代码里的真实阈值（`theme.dart` / `et_shell.dart`）：

- `context.etUseRail` = `width >= 600` → 决定 `NavigationRail` vs `NavigationBar`。
- `context.etDesktop` = `width >= 840` → 决定双栏、density、gutter、宽窗表格。
- 扩展 rail（带文字）= `width >= 1200`。
- 页面 gutter：`EtSpace.gutter(width)` = 16（<900）/ 24（≥900）（gutter 自身阈值
  仍是 900，见 §17 V8 的一致性说明）。
- 内容最大宽度：`EtSpace.maxContentWidth = 1040`（外壳再留 96 给 padding）。

> **一致性提醒（§17 V8）：** 框架层已经用 600/840/1200 的 M3 数字，但个别页面
> 仍写死 `MediaQuery.size.width >= 900` 作为自己的双栏阈值（Home 的 hero/两栏、
> Config 的 `ConfigTwoColumn`）。这些页面在 840–899 之间仍是单列 —— 不是错误，
> 但和 `etDesktop` 不一致，应逐步收敛到 `context.etDesktop`。

```
compact（手机，<600）—— bottom NavigationBar（76 高），5 destinations
  Home      一个 hero（aurora + orb + 45px 延迟 + badge + 唯一主操作）
            + bento 三 tile + traffic + Peers + Network
  Devices   peer 全表（avatar 行 + latency pill + 状态 chip）；离线排尾
  Config    实例卡横条 + 一级披露四 section（leading icon badge）+ 底部单 Save
  Activity  按天分组的事件时间线（icon badge + mono HH:mm）
  Settings  分组卡（icon badge 组头）+ 行内 badge/chip

medium（600–839）—— 左侧 NavigationRail（rail 从 600 开始）；页面仍可单列
expanded（≥840）—— rail + 双栏（内容列 ≤1040），无 bottom bar
large（≥1200）—— rail 显示文字标签 + 品牌 tile + EasyTier 字标
```

规则：

- **一个目的地只有一个入口。** Home 的 network 卡片是**快捷方式**，切到 Config
  destination，不 push 第二个 Config 页面。没有“高级控制台”外壳。
- **tab 表达目的地，push 表达层级。** 任何进入的详情页都有真实返回栈（Android
  back 必须可用）。模态 sheet 有可见关闭按钮 + drag handle。
- 导航状态跨 tab 保留；切 tab 不重新拉数据（轮询循环负责新鲜度）。
- 核心操作绝不只有手势：连接/断开、保存/放弃、停止隧道、关闭对话框都有可见按钮。
- 默认打开 Home，跟随系统 light/dark，选上次 active 的 instance。
- 5 个目的地是上限。不要加第 6 个 tab；新目的地变成 Settings 的 section 或 push 路由。

---

## 11. 无障碍

**基线：WCAG 2.1 AA。** 自动化门禁是 `check_tokens.dart`（§16.1），人工清单是 §16.5。

- **文字对比度 ≥4.5:1**；大字号（≥24px，或 ≥18.66px bold）≥3:1。所有登记配色对
  通过（§3.5）。
- **非文字对比度 ≥3:1**：控件边界、focus 指示、开关轨道、chart 线、状态图标。
  用 `outline`，不用 `outlineVariant`。
- **触摸目标**：Android 48dp、iOS 44pt、桌面指针 24 CSS px（WCAG 2.5.8）。
  Flutter 逻辑像素下：按钮 48 高、text button 44、icon button 48、列表行 ≥48；
  相邻目标至少 8（`EtSpace.x2`）。48/44/24 是三个独立标准，不要“统一”成一个数。
- **focus**：每个可交互元素可键盘到达（桌面），顺序与视觉一致，focus ring 2px
  `primary` + 2px offset，永不移除、不被吸顶栏遮挡。对话框 trap focus 并在关闭时
  还原到触发元素。自绘控件需要 `FocusNode` + `FocusableActionDetector`，裸
  `GestureDetector` 不够。
- **屏幕阅读器**：仅图标控件有 label；状态变化通过一个
  `Semantics(liveRegion: true)` 区域播报（节流：阶段变化时播报，不是每次轮询），
  播报完整句子（“Connected, 4 peers online”，不是“connected”+ 一个孤立的“4”）；
  图表有文字等价物；状态 badge（或 `EtSignal`）的可访问名是状态句，不是“icon”。
- **错误**：字段错误通过 `errorText` 关联到输入框；提交失败时焦点移到可聚焦的
  错误摘要，字段级错误保留；破坏性确认写明对象与后果。
- **动态字号**：支持 200% 缩放；允许换行；避免固定高度；关键数值不截断；在最大
  系统字号下测试。
- **减少动效**：§7.4；语义信号不因关闭动效而丢失。
- **颜色独立性**：每个状态通过灰度截图检查；§9.1 的图标形状是 fallback。
- **装饰层必须无声。** aurora、`EtConnectionOrb`、`EtAvatar`、`EtIconBadge` 都是
  装饰：orb/avatar 内部用 `ExcludeSemantics`（`EtAvatar` 的首字母不朗读），语义由
  hero 的文字、hostname、section 标题承担。没有文字的装饰不进入可访问树。
- **hero 的对比度约定：** 45px 延迟是 large text（≥3:1）；状态句（16px）与 badge
  落在 hero 下半部的 scrim 上（按 4.5:1 要求）；aurora 本身不参与对比度断言，这是
  §17 V3 要补的自动测试。
- **语言**：UI 文案 en/zh；当前只 LTR，但布局不用硬编码 left/right，用
  `EdgeInsetsDirectional` / `AlignmentDirectional`。
- **动效永远不是唯一反馈**：pressed/selected/disabled 都有颜色/形状/文字状态。

---

## 12. 平台差异

| | Phone (<600) | Tablet/medium (600–839) | Desktop / expanded (≥840) |
|---|---|---|---|
| Navigation | bottom `NavigationBar`（76 高） | 左侧 `NavigationRail`（v5 起 600 就用 rail） | 左侧 `NavigationRail`；≥1200 扩展带文字 |
| Density | M3 标准 | 标准 | 标准（`buildEtTheme(compact:)` 为预留能力，当前未在调用点启用，§17 V7） |
| Gutter | 16 | 16 | 24（`EtSpace.gutter` 的 900 阈值） |
| Content width | 全宽 | 全宽 | 居中 ≤1040 |
| Type | M3 phone scale | phone scale | M3 scale（density 不压字号） |
| Rows | `ListTile`（≥56） | 同 | `DataTable` 行 56–72（只读表） |
| Charts | 全宽 140 | 全宽 | 卡片内 180–240 |
| Safe area | `SafeArea` / `MediaQuery.padding` | 同 | Flutter 处理窗口 inset |
| Android | 系统返回；VPN 授权流；常驻通知镜像传输状态 | — | — |
| iOS | 44pt 目标；侧滑返回必须匹配路由栈；无 VPN 通知模式 | — | — |

测试宽度：**360、390（手机）、600（rail 起点）、840（expanded 起点）、900
（`EtSpace.gutter` 阈值 / 部分页面双栏）、1200（rail 扩展）、1440** + 横屏手机。
框架断点用 600/840/1200；页面自己的双栏阈值暂时还混用 900（§17 V8）。

**安全区不是 token。** 用 `MediaQuery.padding`/`viewPadding` + `SafeArea`；
不要写死 44/34 的刘海常量。

---

## 13. 文案规则

- **Sentence case**（句首大写）。除标准缩写（IP、VPN、MTU、TOML、ACL、RX、TX）外
  不用全大写。
- **按钮说结果**：“Connect”、“Disconnect”、“Save changes”、“Delete network”、
  “Copy IP”。有具体动词就不要“OK/Submit/Yes/No”。
- **状态文案是事实**：“Connected”、“Connecting…”、“Degraded — relay only”、
  “Disconnected — handshake timed out”。无感叹号、无“Oops”、不指责用户、不虚假安慰。
- **错误 = 什么失败了 + 为什么（若已知）+ 下一步**：
  “Virtual IP is outside 10.144.0.0/24. Use an address in that range or enable DHCP.”
  字段级错误点名具体片段：“Last octet 999 is outside 0–255.”
- **数字**：tabular；单位可读（`formatRate` → `B/s`/`KB/s`/`MB/s`；`formatUptime`
  → `12s`/`5m`/`2h 14m`）。延迟 `ms`、丢包 `%`、MTU 整数，不写“about”。
- **时间**：列表用相对（“2m ago”），详情用绝对 + 时区。不要裸时间戳。
- **空状态**说明原因并给下一步：“No peers yet. Connect on Home to join
  <network>.”，不是“No data”。
- **截断**只用于不可预测值（IPv6、key、URL），且必须保留完整值的路径
  （展开/复制/详情 sheet）。不为了两张卡片等高而截断。
- **双语**：英文为准，中文保义并保持标点风格；不要拼接翻译片段（语序会坏），
  用整条 message key。产品名词（EasyTier、WireGuard、TOML）不翻译。
- **一个概念一个词**：peer（不混用 node/device）、network（mesh）、instance
  （持久化配置）、tunnel（数据面）。Devices tab 列的是 peers，nav label 是 Devices。

---

## 14. 从 v3「Instrument」迁移

v3 的视觉语言被整体移除；信息架构、机器数据排版、一层披露、48dp 目标这些
**工程约束被保留**。逐条如下。

### 14.1 被丢弃的东西

| v3「Instrument」 | v4 Material 3 | 为什么 |
|---|---|---|
| 自定义视觉语言（近黑 + mint + 细线 + 仪器感） | Google Material 3（seed 推导的 M3 role） | 用户明确要求 Google 风格；自研视觉语言与平台组件系统不一致，且无法复用 M3 的可访问性保障 |
| 32 字段手写 hex 色板（mint `#2DE0B0`、cyan、amber、五套 quiet/onTint） | 一个 seed `#0B57D0` → `ColorScheme.fromSeed` 的全部 role | 手写色板每年维护成本高、对比度靠人肉校验；M3 算法保证 role 关系与 tonal 一致性 |
| `accent` / `info` / `warn` / `danger` / `neutral` 五个自造 intent | M3 `primary`/`secondary`/`tertiary`/`error`/surface 阶梯 + 两个扩展 intent | M3 的 role 名称是行业通用语；五个 intent 里 `accent` 与 `info` 在 M3 里就是 primary 的两个用途 |
| ET Sans / ET Sans CJK / ET Mono | 平台系统字体 + 平台等宽 + 系统 CJK fallback | 用户要求使用系统字体；不再内嵌任何文本字体，跟随 OS 排版偏好 |
| Phosphor outline 图标（两套字重） | Material Symbols 变量字体（Outlined，FILL 轴） | Material Symbols 是 M3 官方图标集，与 Roboto 光学尺寸匹配；变量字体省体积 |
| 自绘状态几何（空心环/方块/三角/横条） | Material Symbols 图标 + role 颜色 + 文字 | M3 状态用“图标 + label”；自绘几何是纯自定义符号，用户不认，且难以做 fill 变体 |
| 只用明度分层、全场 `elevation: 0`、禁止阴影 | M3 elevation level 0–5 + surface container 阶梯，卡片 level 1 | M3 的高度是 tonal + 轻阴影；深度不再需要“靠肉眼分四档深色” |
| `text3` 不得放在 `surface3` 的禁令 | 取消：M3 只有一个次级文字 role `onSurfaceVariant` | v3 有 text2/text3 两个层级却只差一点；M3 用 container 高度而非文字层级表达层次 |
| 自定义 90/140/200/280ms + 六个自定 loop | M3 short2/short3/short4/medium2 + emphasized easing（数值几乎一致） | 顺手对齐 M3 命名；行为不变，语义更清楚 |
| focus 必须是 accent 之外的另一色（cyan） | M3：focus ring = `primary` | M3 用 primary 做 focus 是平台惯例；v3 的“第三色”在 M3 里没有位置 |
| `EtBadge` pill 形（999） | chip 形状 8dp 圆角 | M3 chip 是 8dp 小圆角，pill 只属于导航指示器/胶囊按钮 |
| `EtRadius.xl = 24`（dialog） | M3 28（dialog/sheet） | M3 规格就是 28；24 是自定值 |
| 品牌 hero 字号 40 / title 17 / headline 20 | M3 scale 36 / 16 / 22 | 不再自定字号；M3 type scale 是唯一来源 |
| `<style>` / CSS parity、opaque quiet tint 规则、z-index 映射 | 不再需要（Flutter 主题 + route/overlay） | 这些是 v2/v3 为“与 Web 客户端 token 对齐”付出的成本；v4 不再与 Web 共享视觉令牌 |
| `check-tokens.py`（解析 tokens.dart 里的 32 字段色板） | `tool/check_tokens.dart`（构建真实 M3 scheme） | 色板不存在了；门禁改为在 Flutter 运行时里测真实 role |

### 14.2 被保留的东西

- **一屏一问的 IA** 与 5 个目的地（M3 bottom nav 正好上限 5 个）。
- **机器数据等宽 + 右对齐**（平台等宽字体替代 ET Mono，规则不变）。
- **状态三重编码**（颜色 + 形状 + 文字）——现在是 M3 role + Symbols 图标 + label。
- **一层披露**（Config 的四个 section，不嵌套第二层）。
- **48dp 触摸目标、4-based 间距、200% 字号支持、reduced motion 契约**。
- **文案规则**（结果动词、事实状态、错误三段式、双语整句）。
- `ui-ux-pro-max` 的三个拨盘（Variance 3/10、Motion 3/10、Density 7/10）作为
  输入保留，但视觉层已不再由它决定。

### 14.3 技能溯源说明

本文件的前身是 `ui-ux-pro-max` 的生成结果。v4 明确：**该技能只提供过产品/IA
建议，没有提供视觉方向**。v4 的视觉方向是 Google Material 3，来源是
material.io 的 M3 规范与 Flutter 的 M3 默认实现。技能里与 M3 冲突的建议
（Inter 字体、藏青主色、shadows 深度、landing-page 版式、GSAP 滚动揭示）全部不采用。

### 14.4 v4 → v5：从“合规”到 Expressive

v4 的 baseline 规则（role、type、a11y、组件语义）**全部保留**；v5 只加表现层：

| v4（flat M3） | v5（M3 + Expressive） | 为什么 |
|---|---|---|
| 五屏都是等价的 card stack，没有主角 | Home 一个 32dp hero（aurora + orb + 45px 延迟 + 唯一主操作），其余是支撑块 | 用户否决“正确但丑”；hero-first 是 M3 Expressive 的核心模式 |
| KPI 是灰底 caption + 数字 | 三枚 tonal `EtStatTile`（accent / warn / success），radius 20 | 统计信息参与色彩编码，页面因此有节奏 |
| 卡片 12、按钮/徽章各自小圆角 | 卡片 24、hero 32、统计 20、badge squircle、chip/pill stadium | Expressive 的“大而友好”形状语言 |
| hero 36px（displaySmall） | hero 45px（displayMedium）+ w700 + 紧字距 | 表现性排版：一个屏幕只能有一个 45px 数字 |
| 只有 M3 standard/emphasized 缓动 | 新增 `EtCurves.spring`（轻微过冲），只给状态/hero | 状态变化有物理感，但不干扰数据阅读 |
| 导航 80（M3 默认）→ 实际 76 + 大 pill indicator | 76 高、`surfaceContainer` 底、stadium `primaryContainer` indicator | 更“软”的导航；76 是自定义值，§17 V9 |
| 灰底上的裸图标 | `EtIconBadge` 的 tonal squircle；`EtAvatar` 首字母圆 | 图标有底座，视觉重量更接近 Google 2025 产品 |
| 无渐变（v4 明确禁止 glow） | hero 用 `_AuroraPainter` 自绘 aurora；`surfaceGlow` 用于 Settings About；glow 只允许 4 处（§v5.3） | 表现力需要有边界，否则退回“霓虹 VPN”俗套 |
| 断点 900/1240（v4 遗留） | 600（rail）/ 840（expanded）/ 1200（扩展 rail） | 对齐 M3 window size classes |
| 图标/文字全用系统字体、无 bundled | 不变；新增 heading 字号与字距规则 | 系统字体仍是硬约束，Expressive 不改字体来源 |

被 v5 **取消**的 v4 规则只有一条：v4 的“禁止 glow / 光晕”改成“配额制”
（hero aurora、orb、图表 glow、hero 内高光），其他场合仍然禁止。

---

## 15. 决策记录（v4 baseline + v5 rulings）

| 决策 | 选择 | 理由 |
|---|---|---|
| 视觉语言 | Google Material 3 | 用户要求“看起来像 Google”；M3 提供完整的 role/组件/无障碍体系 |
| seed | `#0B57D0`（Google Blue） | Google 产品的主蓝，与 Roboto/Symbols 成套；`fromSeed` 保证明暗两套 role 一致 |
| dynamic color | **不启用** | 品牌稳定 + 对比度可复现；壁纸取色会让每台设备的 primary 不可预测 |
| 字体 | 系统 UI 字体 + 平台等宽 + 系统 CJK fallback | 用户明确要求系统字体；不内嵌文本字体，跟随 OS |
| 图标 | Material Symbols | M3 官方图标集；变量字体；与 Roboto 光学匹配 |
| success/warning | 作为 M3 扩展 role，成对提供 container | M3 没有这两个语义；产品必须有“健康/降级”状态 |
| 浅色 success | `#137333`（Green 700） | 浅色下 14px 状态标签必须 ≥4.5:1；`#1E8E3E` 只有 4.21:1 |
| dialog/sheet 圆角 | 28（M3） | 规范值；与 v3 的 24 不同 |
| Card | `surfaceContainerLow` + elevation 1（elevated card） | M3 的 elevated card 定义；不是 filled card |
| 按钮高度 | 48（M3 视觉 40） | 触摸目标优先；M3 允许 ≥48 的点击区域，视觉高度由 `FilledButton` 决定（产品决定，不是偏差） |
| 断点 | **600（rail）/ 840（expanded）/ 1200（扩展 rail）** | v4.1 已按 M3 window class 对齐；页面内残留的 900 双栏阈值见 §17 V8 |
| 密度 | 宽窗 `VisualDensity.compact` | M3 桌面密度；只压组件，不压字号 |
| 自造组件 | 只保留 M3 没有的（signal / banner / chip / chart / kpi / empty） | M3 组件能覆盖的一律用 M3 |
| **v5：Expressive 层** | 采用 Google M3 Expressive（2025）作为 v4 之上的覆盖层 | 用户否决 flat M3 的观感；Expressive 是 Google 自己的当前方向，仍属“Google 风格” |
| **v5：装饰色** | `EtAccent` 4 个固定值（blue/violet/mint/cyan）+ `surfaceGlow`（`EtGradient.hero` 未消费） | 头像/aurora 需要稳定、可复现的品牌装饰色；不引入 dynamic color |
| **v5：形状** | 卡片 24、hero 32、统计块 20、squircle icon badge | Expressive 的形状语言；层级仍是 hero > card > tile > chip |
| **v5：hero 字号** | `displayMedium` 45/52（`EtType.expressive`）、w700、mono | 一个屏幕只能有一个 45px 数字；hero 是唯一主角 |
| **v5：导航** | bar 76、stadium `primaryContainer` indicator；rail 从 600 开始 | M3 medium 就推荐 rail；76 是自定义值（§17 V9） |
| **v5：动效** | 新增 `EtCurves.spring`（cubic 过冲），只给状态/hero | 表现性状态变化；密集数据行禁用 |

---

## 16. 验证

### 16.1 令牌对比度门禁（必须绿）

```bash
bash /home/chance/Projects/.flutter-run.sh \
     /home/chance/Projects/easytier/easytier-flutter test tool/check_tokens.dart
```

它做五件事（5 个 test，74 条对比度断言 + 结构断言）：

1. 构建 light/dark 的**真实** `ColorScheme.fromSeed(#0B57D0)` + `EtPalette`，
   打印配色表并断言 WCAG AA：文字 4.5:1、图形/边界 3:1。
2. 断言 `EtPalette` 的每个短名都解析到 M3 role（不是第二套色板），
   且 disabled 是 `onSurface` 38%。
3. 断言 `buildEtTheme()` 真的是 M3（`useMaterial3`、**card 24/`surfaceContainerLow`**、
   dialog/sheet 28、text field 4、snackbar 4、app bar role、**navigation bar 76** 等）。
4. 断言 type / shape / spacing / motion 令牌落在 M3 scale 上（含 **`EtType.expressive=45`、
   `EtRadius.card=24`、`EtRadius.hero=32`、`EtCurves.spring`、`EtAccent`**）。
5. 断言**没有**内嵌文本字体（`pubspec` 无文本 `fonts:`、无 `assets/fonts/`）、测试夹具存在、Material Symbols 依赖正常，并且 `lib/**`
   没有 Phosphor / `Icons.*` / emoji 图标。

退出码：`0` = 全部通过；`1` = 有断言失败（失败项会打印 role 对与实测值）。
**CI 必须把它当作阻断门禁**，与 `flutter analyze` 并列。

> 注：脚本用 `flutter test` 运行，因为 `ColorScheme` 依赖 `dart:ui`，普通
> `dart run` 无法在无 Flutter 引擎的 VM 里加载。它不是单元测试套件的一部分，
> 只是借用 test harness 的 headless VM；`flutter test`（全量）也会顺带跑它。

### 16.2 静态/构建门禁

```bash
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter analyze
bash /home/chance/Projects/.flutter-run.sh /home/chance/Projects/easytier/easytier-flutter test
```

### 16.3 资产检查

```bash
# 产品包不得有文本字体：以下两条都应“没有输出”
ls easytier-flutter/assets/fonts/*.ttf 2>/dev/null
grep -n '^\s*fonts:' easytier-flutter/pubspec.yaml

# 只有 golden 测试夹具（3 个文件，仅 test runner 用 FontLoader 加载）
ls easytier-flutter/test/fixtures/fonts/*.ttf
```

### 16.4 评审时必须做的 grep 检查

```bash
# 1) 组件里出现裸色值/裸时长 = 缺陷（theme/ 目录除外）。
#    已知唯一例外：home_widgets 的 hero 暗色底 Color(0xFF0E0D12)（§17 V1）
rg 'Color\(0x|Colors\.|Duration\(milliseconds' easytier-flutter/lib --glob '!core/theme/**'
# 2) 混用 Material Icons = 缺陷（只允许 Symbols.*）
rg '\bIcons\.[a-z]' easytier-flutter/lib
# 3) emoji / 文字字形当图标 = 缺陷
rg -n '[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]' easytier-flutter/lib
# 4) 旧图标族残留 = 缺陷
rg 'phosphor' easytier-flutter
# 5) v5：渐变只允许 hero（_AuroraPainter + 下半部 scrim）与 surfaceGlow；
#    其余 LinearGradient/RadialGradient = 缺陷
rg 'LinearGradient|RadialGradient' easytier-flutter/lib --glob '!core/theme/**'
#    允许的命中：home_widgets.dart 的 _AuroraPainter / hero scrim、settings_widgets.dart 的 surfaceGlow
```

### 16.5 人工检查清单（任何 UI 合并前）

- [ ] `check_tokens.dart` 退出 0；`flutter analyze` 对改动文件干净。
- [ ] light **和** dark 都打开看过 —— 不要用一个推断另一个。
- [ ] 360 / 390 / 600 / 840 / 900 / 1200 / 1440 + 横屏：无 overflow、无裁切，
      rail/bottom bar 在 **600** 精确切换，双栏在 840 生效（页面遗留 900 见 V8）。
- [ ] Home 与 Devices 看全五个阶段 + empty/error/loading；灰度截图仍可读。
- [ ] **v5 Expressive：** hero 里只有一个主角；aurora 只出现在 hero；About 最多一次
      surfaceGlow；orb 在 reduced motion 下静止；hero 文字在 scrim 上可读。
- [ ] **v5 Expressive：** 没有任何“为了好看”的任意色块；装饰色不承载状态；
      accent 色没有出现在文字/边框/按钮上。
- [ ] 键盘（桌面）：focus 可见、顺序正确、对话框 trap 并还原 focus、无 focus 被吸顶栏遮挡。
- [ ] 屏幕阅读器：图标按钮有名字；orb/avatar 被 `ExcludeSemantics`；阶段变化只播报
      一次；图表有文字等价物。
- [ ] 减少动效：orb 静止、无循环装饰、数字不跳；状态语义完整。
- [ ] 最大系统字号（200%）：无重叠、关键值不裁切（hero 45px 也要检查）。
- [ ] 长 IPv6 / base64 key / URL 不破坏布局。
- [ ] 每屏一个主操作；没有第二个 filled 按钮（Config 的 Run 是 TextButton）。
- [ ] 没有 emoji 图标；没有裸 hex / `Colors.*` / 裸 `Duration`；没有 `Icons.*` 混用；
      控件边界用 `outline` 而非 `outlineVariant`。

---

## 17. 已知偏差与待修项（code vs M3 / vs 本文）

这些是**代码现状与规格不一致**的地方，逐条登记以便修复；规格以本文件为准。
v4 迁移与 v5 Expressive 两轮已修掉的项目在 §17.1，避免重复报告；仍在的 baseline
债务在 §17.2，Expressive 层新增的在 §17.3。

### 17.1 已修复（不再算偏差）

| 已修复项 | 处理方式 |
|---|---|
| 断点（旧 900/1240） | 按 M3 window class：`etUseRail` ≥600、`etDesktop` ≥840、扩展 rail ≥1200 |
| AppBar 高度（旧 68） | `EtPage` 统一 `kToolbarHeight`（64），标题 `headlineSmall` w600 |
| 禁用态按钮（旧 onPrimary 落在灰底） | `EtPrimaryButton` disabled 用 `onSurface` 38% 前景；busy 保留 label + inline spinner |
| 字体细节（旧全局 tabular、36px 也用 1.5） | `EtText.ui` 取消全局 tabular（只保留 mono），行高按 role（≥22 用 1.27）；hero 显式 1.05 |
| 自绘分段控件（旧 `ConfigSegmented` / `SettingsSegmented`） | 改为 M3 `SegmentedButton`（config 的 `ConfigSegmentedField`、settings 的 Theme/Language） |
| settings 日志级别 `DropdownButton` | 改为 M3 `DropdownMenu` |
| Devices 搜索 | 改为 M3 `SearchBar`（primary tint 的 `surfaceContainerHigh`、全圆角） |
| Activity 过滤 | 改为 M3 `MenuAnchor` + `CheckboxMenuButton`（带计数） |
| Devices 排序 | `PopupMenuButton` + `CheckedPopupMenuItem`（M3 主题渲染） |
| Devices 桌面表格 | 改为 M3 `DataTable`（排序指示器、行高 56–72；桌面 >100 peer 的性能债务仍在） |
| 自绘 peer 状态点 `peer_status_dot.dart` | 删除；统一 `Symbols.circle` / `radio_button_unchecked`（v5 再升级为 `EtAvatar` + `LatencyPill`） |
| 浅色 `success` 不达 AA（`#1E8E3E` = 4.21:1） | 改为 `#137333`（5.95:1），14px 状态标签达标 |
| 组件里混用 `Icons.*` / emoji | 已清零；`check_tokens.dart` 的 grep 断言常驻 |
| 自绘 banner / sticky 底栏 | 改为 `EtBanner`（container tone）与 `Material(elevation 3, surfaceContainer)`；滚动区预留底部 padding |

### 17.2 仍存在的 baseline 偏差（D）

| # | 位置 | 现状 | 规格 / 建议 |
|---|---|---|---|
| **D1** | `config_widgets.dart` `ConfigSelectField` | `DropdownButtonFormField`（M2 时代 API） | 迁到 M3 `DropdownMenu` + `FormField` 包装；settings 的日志级别已是 `DropdownMenu` |
| **D2** | `et_shell.dart` `EtDestination.selectedIcon` | 选中图标与未选中相同（未用 FILL 轴） | M3 选中项用 filled 变体；当前靠 indicator pill 承担选中态，语义可辨；换支持 FILL 轴的图标字体后补 |
| **D3** | `et_ui.dart` `EtBadge` | 行内小徽标（约 24 高，label 11），非 M3 chip 的 32/14 | **有意的密度取舍**：列表内联元数据（offline/relay/allow-deny），不是独立可点 chip；要可交互标签就改用 `Chip`/`FilterChip`，不要放大 `EtBadge` |
| **D4** | `et_ui.dart` `_SpeedGraphPainter` | 自绘图表；渐变 alpha 0.28、描边 2/2.4/5、glow blur 6 与末点 3 为字面量 | M3 无 chart 组件，自绘允许；待办：把 alpha/描边/glow 收进令牌（v5 加 glow 后更值得做） |
| **D5** | 多屏 | 硬编码布局宽度：Devices `SizedBox(width: 260)` / `96`、Config `280` / `220` / `92`、Home `176` | 布局常量可接受，但 200% 字号/zh 文案回归时改为弹性约束 |
| **D6** | `tokens.dart` | `secondary`、`onTertiary` 等 role 暂未使用 | 非错误；新增用途前登记到 §3.2 |
| **D7** | `et_ui.dart` `EtSignal` | 14px 状态标签直接用语义色 | 当前全部 ≥4.5:1；M3 更常见的做法是“图标着色 + 文字 onSurface”。语义色变浅则必须回退为图标着色 |
| **D8** | `theme.dart` | 显式设置 `surfaceTintColor` | 保留；M3 长期方向是用 surface container role 表达层级，tint 是兼容层 |

### 17.3 v5 Expressive 层的新偏差（V）

| # | 位置 | 现状 | 规格 / 建议 |
|---|---|---|---|
| **V1** | `home_widgets.dart:94` | hero 暗色底用裸色值 `const Color(0xFF0E0D12)` | 应改为令牌（例如在 `EtGradient` 或 `EtPalette` 暴露 hero base），或 `surfaceContainerLowest` + primary tint 计算 |
| **V2** | `home_widgets.dart` `_AuroraPainter` / hero 容器 | 下半部 scrim alpha 0.12/0.48、1px 高光 0.16、边框 primary 0.22、aurora blob alpha 全是 painter 字面量 | Expressive 的“渐变配方”应有名字；至少把 hero 的 scrim/highlight/border 三个值收进 `EtGradient` |
| **V3** | hero / `EtAvatar` / `EtStatTile` | 装饰合成层的文字对比度**没有被 `check_tokens.dart` 断言**（脚本只测 M3 role 对） | 需要补一个“合成后对比度”断言：hero scrim 叠 aurora 后的 `onSurface`、avatar `onSurface` 叠 `EtAccent` tint、stat tile 的 container 对。当前靠 §v5.3 的“文字落在稳定 tonal 层”规则人工保证 |
| **V4** | `tokens.dart` `EtCurves.spring` | 是 `Cubic(0.34,1.56,0.64,1.0)` 的**曲线近似**，不是 stiffness/damping 的物理 spring | M3 Expressive 用 spring token 描述运动；当前只有一条定值曲线，没有速度/中断重定向语义。够用，但登记为近似 |
| **V5** | 全局 | 没有 shape morph（M3 Expressive 的 35-shape 库与形状过渡未实现） | 当前是静态圆角；shape morph 需要 `ShapeBorder` 插值或 `AnimatedContainer` 组合，列入未来项 |
| **V6** | `tokens.dart` `EtAccent` | 4 个固定装饰色（brand-fixed），不随 seed / dynamic color 变化 | 有意为之（稳定、可复现）；但意味着“Expressive 色彩”不是完全由 M3 动态生成，文档不要声称它是 scheme role |
| **V7** | `app.dart` | `buildEtTheme(compact:)` 存在但没有调用点传 `true` | 宽窗 density 实际仍是 standard；要么在 `MaterialApp.builder` 里按 `etDesktop` 重建主题，要么删掉这个参数 |
| **V8** | `home_page.dart` / `config_widgets.dart` | 页面自己的双栏阈值仍写死 `width >= 900`，与 `etDesktop`（840）不一致 | 收敛到 `context.etDesktop`；在 840–899 区间，框架已切 rail 但页面仍单列 |
| **V9** | `theme.dart` `navigationBarTheme` | 高度 76（M3 baseline 是 80；Expressive 方向通常更高） | 76 是自定义值。要么回到 80（M3 规格），要么明确登记为 Expressive 品牌尺寸；当前按后者接受 |
| **V10** | kit / features | 组件内尺寸字面量：stat tile radius 20、avatar 32/40/44/48、rail 品牌 tile 34、summary chip padding 6、icon badge 32/36/40 | 属于 Expressive 的局部配方，可接受；若第三处复用同一数值，再提取为 token |
| **V11** | `theme.dart` `navigationBarTheme.labelTextStyle` | 选中标签用 `onSecondaryContainer`，而 indicator 是 `primaryContainer`；两个 role 不属于同一语义对 | 标签不在 indicator 上（在 `surfaceContainer` 上），对比度够；但语义应改为 `onSurface`（M3 nav label）或与 indicator 配对的 `onPrimaryContainer`。这是 v5 的一处颜色语义错配 |
| **V12** | `et_ui.dart` `EtPeerRow` trailing | Home/Devices 列表的 latency pill 是“语义色 14% 叠在 `surfaceContainerHigh`”的**手工合成**，不是 M3 container；且这段文字对比度未进 `check_tokens.dart`。宽窗 `DataTable`/详情却用 `LatencyPill`（真正的 container role） | 同一个数据两套处理。建议 `EtPeerRow` 改用 `LatencyPill`（或至少用 container role + 断言），消除手工 alpha |
| **V13** | `tokens.dart` `EtGradient.hero` | 定义了参数化 hero 渐变，但没有任何调用点；Home 实际由 `_AuroraPainter` 自绘 aurora | 两个“hero 渐变”来源。要么让 painter 消费 `EtGradient.hero`，要么删除 token；保留时必须在文档标注“未被消费”（本文件已标注） |
| **V14** | `et_ui.dart` `EtSignal` | kit 仍提供 5 态 `EtSignal`，但 v5 起全库没有调用点（Home 改用 `EtBadge` + orb） | 要么删除，要么在 Devices/详情里重新使用；文档把它当“状态信号组件”描述，代码里是死组件，需二选一 |

### 17.4 修复顺序建议

V3（补合成层对比度断言，含 V12 的 pill）→ D1 → V1/V2（hero 配方令牌化）→ V7 → V8 → V11 → V13 → V5 → V4。
其余是低风险债务，不阻断 M3 / Expressive 观感。

---

## 18. 反模式（阻断合并）

- 颜色是唯一状态信号；状态没有文字标签；em dash 当状态。
- 控件只有 `outlineVariant` 边界；`outline` 与 `outlineVariant` 混用。
- 组件里出现裸 hex / `Colors.*` / 裸 `Duration` / 硬编码间距圆角（hero 暗色底
  `0xFF0E0D12` 是唯一登记中的例外，见 §17 V1）。
- 混用 `Icons.*` 与 `Symbols.*`；emoji 或 Unicode 字形当图标；两套图标字重。
- 自定义 `BoxShadow` 或 `elevation > 1` 做层级（Config 底栏 elevation 3 是唯一
  允许的“浮起”，因为它是滚动区兄弟节点）；用 `withOpacity` 手搭状态层。
- **v5：** 在 hero 以外铺 aurora/渐变；同一屏出现两次 surfaceGlow；给列表/卡片加 glow。
- **v5：** 把 `EtAccent` 当控件色（按钮、边框、文字、选中态）；装饰色编码状态。
- **v5：** 45px 数字出现在 hero 之外；一屏两个 hero；orb 成为唯一状态指示。
- **v5：** 在 aurora 上直接压文字而不给 scrim/实色容器；文字落在最亮的 blob 上。
- **v5：** `EtCurves.spring` 用在密集数据行、列表重排或文字位移。
- **v5：** 用装饰性无限动画（orb 脉冲除外）；reduced motion 下仍在动。
- 自造 M3 已有的组件（分段控件、下拉、chip、按钮），除非 §17 已登记替换路径。
- 一屏多个 filled 按钮；主操作藏在手势后面。
- Config 出现第二层披露、“推荐预设”、删字段。
- 离线 peer 从列表消失；按用户看不见的字段排序；延迟/IP 用比例字体或非 tabular。
- 动画里改布局属性；无限装饰动画；count-up；状态依赖动效。
- placeholder 当 label；错误只说“invalid”；看起来可点但不可点的行 / 看起来不可点但可点的行。
- 移除 focus ring；依赖平台在深色上不可见的默认高亮。
- 固定高度 + 裁切文字；关键值截断；手机上横向滚动。
- 忽略 `etReducedMotion` 或 `MediaQuery.textScaler`。

---

## 19. 屏幕规格

| Screen | 回答的问题 | 文件 |
|---|---|---|
| Home | 我的 mesh 通吗？多健康？ | [`pages/home.md`](pages/home.md) |
| Devices | 谁在上面？谁慢？ | [`pages/devices.md`](pages/devices.md) |
| Config | 配置成了什么？能安全改吗？ | [`pages/config.md`](pages/config.md) |
| Activity | 发生了什么？什么时候？ | [`pages/activity.md`](pages/activity.md) |
| Settings | App 对我怎么表现？ | [`pages/settings.md`](pages/settings.md) |

令牌 ↔ M3 role / M3 组件映射，以及 v2/v3 遗留物的失效清单：
[`tokens-reference.md`](tokens-reference.md)。
