# 令牌参考 — M3 role ↔ Flutter token ↔ kit 组件

> [`MASTER.md`](MASTER.md) 的配套文件。Flutter 客户端的机器可读令牌在
> `easytier-flutter/lib/core/theme/tokens.dart` 与 `theme.dart`；本文件是
> **映射表 + 差异表**：每个 App 短名对应哪个 Google Material 3 role、每个 kit
> 组件对应哪个 M3 组件、以及 v2/v3 的哪些东西已经**失效**。
>
> 唯一事实来源是 Dart 文件。如果本表与 Dart 文件冲突，Dart 文件胜，并在同一次
> 改动里修正本表。对比度由
> [`tool/check_tokens.dart`](../../easytier-flutter/tool/check_tokens.dart) 实测
> （命令见 [MASTER §16](MASTER.md#16-验证)）。

## 1. 颜色 — 一个 seed，全部 M3 role

`ColorScheme.fromSeed(seedColor: Color(0xFF0B57D0), brightness: light|dark)` 是唯一
颜色来源。`EtPalette` 是 `ThemeExtension`，把 M3 role 映射成 App 里沿用的短名；
它**不持有第二套色板**，`copyWith`/`lerp` 都重新走 `EtPalette.of(scheme)`。

| App 短名（`context.et.*`） | M3 role | Light | Dark | 用途 |
|---|---|---|---|---|
| `bg` | `surface` | `#FAF8FF` | `#121318` | Scaffold / canvas |
| `surface1` | `surfaceContainerLow` | `#F4F3FA` | `#1A1B21` | 卡片（elevated card） |
| `surface2` | `surfaceContainer` | `#EEEDF4` | `#1E1F25` | 输入行、次级块 |
| `surface3` | `surfaceContainerHigh` | `#E8E7EF` | `#282A2F` | 抬升行、tooltip |
| `sunken` | `surfaceContainerLowest` | `#FFFFFF` | `#0D0E13` | 内凹井、TOML 预览、图表底 |
| `neutralQuiet` | `surfaceContainerHighest` | `#E2E2E9` | `#33343A` | 中性 chip 底、选中行 |
| `border` | `outlineVariant` | `#C5C6D0` | `#45464F` | **装饰**分隔线（无对比契约） |
| `borderStrong` | `outline` | `#757780` | `#8F909A` | 强描边（= 控件边界） |
| `controlBorder` | `outline` | `#757780` | `#8F909A` | **交互边界**：input/switch/分段（≥3:1） |
| `scrim` | `scrim` | `#000000` | `#000000` | modal barrier |
| `text` | `onSurface` | `#1A1B21` | `#E2E2E9` | 主文字 |
| `text2` | `onSurfaceVariant` | `#45464F` | `#C5C6D0` | 次级文字/图标 |
| `text3` | `onSurfaceVariant` | `#45464F` | `#C5C6D0` | **与 text2 相同**（M3 只有一个次级文字 role） |
| `textDisabled` | `onSurface` @38% | 半透明 | 半透明 | 禁用态（M3 38% 规则） |
| `accent` | `primary` | `#495D92` | `#B2C5FF` | 主操作 / 选中 / focus / 连接中 |
| `onAccent` | `onPrimary` | `#FFFFFF` | `#172E60` | 主操作上的文字 |
| `accentQuiet` | `primaryContainer` | `#DAE2FF` | `#304578` | accent 徽章 / 导航指示器 |
| `accentOnTint` | `onPrimaryContainer` | `#304578` | `#DAE2FF` | 上述容器上的文字 |
| `info` | `primary` | `#495D92` | `#B2C5FF` | 信息 / 同步中 |
| `onInfo` | `onPrimary` | `#FFFFFF` | `#172E60` | — |
| `infoQuiet` | `secondaryContainer` | `#DCE2F9` | `#404659` | 次级 tonal（info 徽章/横幅） |
| `infoOnTint` | `onSecondaryContainer` | `#404659` | `#DCE2F9` | — |
| `neutral` | `onSurfaceVariant` | `#45464F` | `#C5C6D0` | 未开始 / 未知 / 离线 |
| `focus` | `primary` | `#495D92` | `#B2C5FF` | focus ring（M3 用 primary，不用第三色） |
| `danger` | `error` | `#BA1A1A` | `#FFB4AB` | 失败 / 断开 / 破坏性 |
| `onDanger` | `onError` | `#FFFFFF` | `#690005` | — |
| `dangerQuiet` | `errorContainer` | `#FFDAD6` | `#93000A` | 错误横幅/徽章底 |
| `dangerOnTint` | `onErrorContainer` | `#93000A` | `#FFDAD6` | — |
| `warn` | `warning`（扩展） | `#8F4C00` | `#FFB95C` | 降级 / relay-only / 高延迟 |
| `onWarn` | `onWarning`（扩展） | `#FFFFFF` | `#4A2800` | — |
| `warnQuiet` | `warningContainer`（扩展） | `#FFDDB3` | `#6A3B00` | 降级横幅/徽章底 |
| `warnOnTint` | `onWarningContainer`（扩展） | `#2D1600` | `#FFDDB3` | — |
| —（`EtPalette.success`） | `success`（扩展） | `#137333` | `#81C995` | 已连接 / 健康 |
| —（`EtPalette.onSuccess`） | `onSuccess`（扩展） | `#FFFFFF` | `#00390F` | — |
| —（`EtPalette.successContainer`） | `successContainer`（扩展） | `#C4EED0` | `#005322` | — |
| —（`EtPalette.onSuccessContainer`） | `onSuccessContainer`（扩展） | `#072711` | `#A6F4B6` | — |
| —（`EtPalette.warning`） | `warning`（扩展） | `#8F4C00` | `#FFB95C` | 同 `warn` |
| —（`scheme.inverseSurface`） | `inverseSurface` | `#2F3036` | `#E2E2E9` | snackbar / tooltip 底 |
| —（`scheme.onInverseSurface`） | `onInverseSurface` | `#F1F0F7` | `#2F3036` | 反色底上的文字 |

**未使用的 M3 role：** `secondary`（非 container）、`onTertiary`、`surfaceTint`
（仅交给主题内部 elevation tint 使用）。`tertiary` / `tertiaryContainer` 在 v5 里
用于“路由/补充强调”类信息（routes chip、Advanced section badge、About 徽章、
图表上行线），仍是信息容器，不是操作色。

**扩展语义 role 的由来：** M3 没有 success/warning。产品需要“健康/降级”两个状态，
且不能借用 `primary`（已被操作占用）或 `error`（表示失败），所以成对增加 8 个字段。
它们与 M3 role 同权：必须过同一个对比度门禁、必须成对提供 container。

## 2. 字体

| 字体族 | 来源 | 权重 | 用途 | 禁止 |
|---|---|---|---|---|
| **系统 UI 字体** | 平台（Android Roboto / Apple SF / Windows Segoe UI / Linux system-ui） | 系统提供 | 全部 UI 文案 | 机器数据列 |
| **平台等宽** | `monospace` / `Menlo` / `Consolas`（按 `defaultTargetPlatform`） | 系统提供 | IP/端口/延迟/丢包/速率/MTU/ID/版本/时长/密钥/图表数值 | 中文（可能无 CJK 字形） |
| **系统 CJK fallback** | 平台 CJK 字体（Noto Sans CJK / PingFang / 雅黑 / 文泉驿） | 系统提供 | `EtText.uiFallback` 的回退链 | 作为主字体直接选用；随包内嵌 |

`pubspec.yaml` **不得**声明文本 `fonts:`；文本字体一律来自系统。`test/fixtures/fonts/` 只是 golden 的测试夹具。

### 2.1 字号

| M3 role | 字号/行高 | App 令牌 | `EtText` 用法 |
|---|---|---|---|
| `displayMedium` | 45 / 52 | `EtType.expressive` | **v5：Home hero 延迟**（w700、mono、height 1.05） |
| `displaySmall` | 36 / 44 | `EtType.hero` | 大数字（v5 的 Home 已改用 45） |
| `headlineMedium` | 28 / 36 | `EtType.display` | `EtText.mono` 大数字 |
| `titleLarge` | 22 / 28 | `EtType.headline` | 页面/大标题 |
| `titleMedium` | 16 / 24 | `EtType.title` | 卡片标题 |
| `bodyLarge` | 16 / 24 | `EtType.body` | 正文 |
| `bodyMedium` | 14 / 20 | `EtType.bodySm` | 密排行 |
| `bodySmall` | 12 / 16 | `EtType.caption` | 辅助说明 |
| `labelSmall` | 11 / 16 | `EtType.micro` | 徽章 / 极小标签 |

- `EtText.ui()` / `EtText.mono()` 是唯一的文字构造器；**只有 mono 带
  `FontFeature.tabularFigures()`**（v5 起 UI 文案不再全局 tabular）。
- `EtText.ui` 不指定 family（继承平台 Typography）；行高按 role：≥22 用 1.27、
  正文 1.5，hero 由调用方显式覆盖（1.05 / 1.15）。
- 主题层不指定文本 family（继承平台 Typography）；组件优先读
  `Theme.of(context).textTheme.<role>`，不要到处写 `fontSize`。
- 权重：只使用系统字体实际提供的 400/500/700；M3 正文 400、强调 500、700 只给
  hero 数字 / 极少数强值。

## 3. 形状

| M3 shape | 值 | token | 用于 |
|---|---:|---|---|
| none | 0 | — | app bar / nav bar / rail / 全出血 |
| extra small | 4 | `EtRadius.xs` | outlined text field、snackbar、tooltip |
| small | 8 | `EtRadius.sm` | chip / 徽章、menu |
| medium | 12 | `EtRadius.md` | 内联横幅、旧版卡片（保留 token） |
| large | 16 | `EtRadius.lg` | surfaceGlow 标题带、大容器 |
| **expressive card** | **24** | **`EtRadius.card`** | 卡片 / `EtSurface` / `EtSection`（`theme.cardTheme`） |
| extra large | 28 | `EtRadius.xl` | dialog、modal bottom sheet |
| **expressive hero** | **32** | **`EtRadius.hero`** | 仅 Home hero |
| full | 999 | `EtRadius.pill` | 胶囊按钮、latency pill、summary chip、导航指示器 |

`theme.dart` 的确认值：**card 24**、dialog 28、sheet 28、snackbar 4、outlined input 4。
组件内固定值：stat tile 20、icon badge squircle `size×0.34`、rail 品牌 tile 11。
嵌套规则：子圆角 = 父圆角 − inset。

## 4. 间距

4-based（M3 的基础单位就是 4dp）：

| token | px | 典型用途 |
|---|---:|---|
| `EtSpace.x1` | 4 | 图标-文字间隙 |
| `EtSpace.x2` | 8 | 行内间隙、chip padding、相邻触摸目标最小间距 |
| `EtSpace.x3` | 12 | 密排垂直 padding、stack 间距 |
| `EtSpace.x4` | 16 | 手机 gutter、卡片 padding |
| `EtSpace.x5` | 20 | 按钮横向 padding、区块内间距 |
| `EtSpace.x6` | 24 | 桌面 gutter、区块间距、sheet padding |
| `EtSpace.x8` | 32 | 大块分隔、空状态节奏 |
| `EtSpace.x10` | 40 | hero → 辅助信息 |
| `EtSpace.x12` | 48 | 一个触摸目标；页面上下留白 |
| `EtSpace.x16` | 64 | 最大区块分隔、bottom nav 余量 |

- `EtSpace.gutter(width)`：16（<900）/ 24（≥900）。
- `EtSpace.maxContentWidth = 1040`。
- 相邻触摸目标最小间距 8；不要发明 10/14/18 的间距。

## 5. 动效

| App token | 值 | M3 token | 用途 |
|---|---|---|---|
| `EtDuration.instant` | 100 ms | short2 | 按压 / hover / ripple |
| `EtDuration.fast` | 150 ms | short3 | 退出 / 关闭 |
| `EtDuration.base` | 200 ms | short4 | 进入 / 展开 / 路由 |
| `EtDuration.slow` | 300 ms | medium2 | 状态变化 / 主题切换 |
| `EtCurves.standard` | `Cubic(0.2,0,0,1)` | standard | 默认 |
| `EtCurves.enter` | `Cubic(0.05,0.7,0.1,1)` | emphasized decelerate | 进入 |
| `EtCurves.exit` | `Cubic(0.3,0,0.8,0.15)` | emphasized accelerate | 退出 |
| `EtCurves.hover` | `Cubic(0.2,0,0,1)` | standard | hover |
| **`EtCurves.spring`** | `Cubic(0.34,1.56,0.64,1)` | Expressive spring（近似） | v5：状态/hero 的切换；密集数据行禁用 |

循环：`loopSpin 700`（linear）、`loopSweep 900`（linear）、`loopShimmer 1400`
（linear）、`loopBreathe 1400`、`loopPulse 1400`、`loopRing 2000`。循环只允许表达
进度或语义状态。`context.etReducedMotion` 是减少动效的唯一入口。

## 6. 图标

- 依赖：`material_symbols_icons`（Material Symbols 变量字体，Google 官方 M3 图标集）。
- 使用方式：`import 'package:material_symbols_icons/symbols.dart'` → `Symbols.*`。
- 默认外观：Outlined、weight 400、fill 0。**不要**混用 `Rounded`/`Sharp` 变体，
  也不要混用 Flutter `Icons.*`。
- 选中态导航图标应使用 filled（`FILL 1`）；当前实现未做（MASTER §17 D2）。
- 尺寸：24（导航/动作，M3 默认）、20（内联/leading）、18（按钮内）、16（密排）。
- **v5：图标通常包在 `EtIconBadge` 里**（tonal squircle，32/36/40，半径 size×0.34）；
  颜色来自 `EtTone` 的 container 对，不直接用 accent。装饰性圆点/几何符号仍禁止。
- 颜色：默认 `onSurfaceVariant`；选中/激活用对应 container 的 `on*Container`；
  语义色只在图标本身是信号时使用，且必须有文字伴随。
- 禁止 emoji、`✓`/`⚠`/`●` 等文字字形当图标。

目的地图标：

| 目的地 | `Symbols.*` |
|---|---|
| Home | `shield` |
| Devices | `devices` |
| Config | `tune` |
| Activity | `monitoring` |
| Settings | `settings` |

状态/动作：`check_circle`、`progress_activity`、`warning`、`link_off`、
`radio_button_unchecked`、`monitor_heart`、`report`、`verified_user`、`search`、
`close`、`filter_alt`、`swap_vert`、`refresh`、`power_settings_new`、`cable`、
`code`、`add`、`delete`、`chevron_right`、`expand_more`/`expand_less`、
`arrow_downward`/`arrow_upward`、`menu_book`、`sync_alt`、`gpp_bad`、`history`、
`person_add`/`person_remove`。

## 7. kit 组件 ↔ M3 组件

| kit 组件（`lib/core/ui/`） | M3 对应 | 备注 |
|---|---|---|
| `EtShell` | `NavigationBar` / `NavigationRail` | 5 destinations；`Badge.count`；bar 76 高；rail 从 ≥600 开始（`etUseRail`） |
| `EtPage` | `Scaffold` + small `AppBar` | 标题 `headlineSmall` w600；toolbar 64 |
| `EtScrollBody` | 布局原语 | maxWidth 1040 |
| `EtSurface` | `Card`（elevated）+ `InkWell` | `surfaceContainerLow` / elevation 1 / **24** |
| `EtSection` | `Card` + `ExpansionTile` | **radius 24、`leading` 组件位**；一级披露 |
| `EtTone` / `EtToneColors.resolve` | container role 映射 | accent/info/**tertiary**/warn/danger/neutral/success |
| `EtAvatar` | Expressive 配方（无 M3 组件） | 首字母圆；`EtAccent` 装饰色；文字 `onSurface` |
| `EtIconBadge` | Expressive squircle（无 M3 组件） | 32/36/40，半径 size×0.34 |
| `EtConnectionOrb` | Expressive 配方（无 M3 组件） | 112dp；glow + 三层环；`loopRing`；`ExcludeSemantics` |
| `EtStatTile` | Expressive bento 配方 | icon + mono 值 + label；radius 20 |
| `EtTile` | `ListTile` | 设置行，`chevron_right` |
| `EtSwitchRow` | `SwitchListTile` | dense |
| `EtTextField` | `TextFormField`（outlined） | 浮动 label、`errorText` |
| `EtPrimaryButton` | `FilledButton` / `FilledButton.tonal` | 48 高；disabled = `onSurface` 38% |
| `EtIconButton` | `IconButton` | tooltip + 48 目标 |
| `EtBadge` | 自定义 chip（M3 chip 32 高） | 当前约 20–24 高（偏差 D3，有意密度取舍） |
| `EtBanner` | 自定义内联横幅 | container role；M3 无 banner 组件 |
| `EtSignal` | 状态信号（无 M3 组件） | Symbols + role + 文字；hero 内改用 badge + orb |
| `EtKpi` | 数据展示（无 M3 组件） | caption label + mono 数值 |
| `EtPeerRow` | `ListTile`（两/三行） | **avatar 40 + latency pill + relay path 在 subtitle**；离线 peer 保留 |
| `EtEmptyState` | 自定义空状态 | 图标 + 一句解释 + 一个下一步 |
| `EtSpeedGraph` | 自定义数据可视化 | `CustomPaint`；**glow + 末点**；有文字等价物 |
| `EtTrafficLegend` | 数据展示 | 方向图标 + mono 数值 |
| `showEtSheet` | `showModalBottomSheet` | 28 / drag handle / useSafeArea |
| 对话框 | `AlertDialog` | M3 默认 `surfaceContainerHigh` + 28 |

### 7.1 v5 Expressive tokens（新增）

| token | 值 / 定义 | 作用域 | 约束 |
|---|---|---|---|
| `EtAccent.blue` | `#3D7BFF` | 装饰背景 | 不可用于控件/文字/边框 |
| `EtAccent.violet` | `#8B5CF6` | 装饰背景 | 同上 |
| `EtAccent.mint` | `#25E0B0` | 装饰背景（avatar） | 同上 |
| `EtAccent.cyan` | `#22D3EE` | 装饰背景（hero 第三 blob） | 同上 |
| `EtGradient.hero(p)` | primary 30% + tertiary 22% + success 14% over `surfaceContainerHigh` | 参数化备用定义（**当前未被消费**；Home 用 `_AuroraPainter`，MASTER §17 V13） | 仅 Home 语义 |
| `EtGradient.surfaceGlow(p)` | primary 16% → `surfaceContainerLow` | Settings About 标题 | 每屏最多一次 |
| `EtRadius.card` | 24 | 卡片/`EtSurface`/`EtSection` | `theme.cardTheme` 已同步 |
| `EtRadius.hero` | 32 | Home hero | 不可复用 |
| `EtType.expressive` | 45（displayMedium 45/52） | Home hero 数字 | 全 App 唯一 45px |
| `EtCurves.spring` | `Cubic(0.34,1.56,0.64,1)` | 状态/hero 切换 | 密集数据行禁用 |
| `etUseRail` / `etDesktop` | ≥600 / ≥840 | 导航 / 双栏 | M3 window classes；页面遗留 900 见 MASTER §17 V8 |
| `NavigationBarThemeData.height` | 76 | 导航 | M3 baseline 80（自定义值，MASTER §17 V9） |

## 8. 已失效：不要再从 v2/v3 迁过来的东西

| v2/v3 遗留 | 状态 | 替代 |
|---|---|---|
| `--et-*` CSS 变量、`tokens.css` 对齐 | **失效** | 只存在 M3 role + `EtPalette` |
| `EtPalette.dark` / `EtPalette.light` 两个静态色板 | **删除** | `EtPalette.of(ColorScheme)` |
| ET Sans / ET Sans CJK / ET Mono | **删除** | 系统 UI 字体 / 系统 CJK fallback / 平台等宽 |
| Phosphor 图标、`phosphor-*.ttf` | **删除** | Material Symbols |
| `accent` 语义 = mint/teal `#2DE0B0` | **失效** | `accent` = `primary`（seed 推导） |
| `info` 语义 = 独立蓝 `#5AB0FF` | **失效** | `info` = `primary`；容器 = `secondaryContainer` |
| 手写 amber `warn` / red `danger` hex | **失效** | `warning` / `error`（扩展 role / M3 role） |
| 32 字段 quiet/onTint 不透明色板 | **失效** | M3 container role 对（`*Container` + `on*Container`） |
| “`text3` 不得放在 `surface3`”的禁令 | **失效** | M3 只有一个次级文字 role；层次由 container 表达 |
| “只用明度分层、全场 elevation 0” | **失效** | M3 elevation 0–5 + surface container |
| 自绘信号几何（空心环/方块/三角/横条） | **删除** | Material Symbols + label |
| 自定义 focus 色（cyan，区别于 accent） | **失效** | M3：focus = `primary` |
| `EtRadius.xl = 24`（dialog） | **失效** | 28 |
| 40px hero / 17px title / 20px headline 自定字号 | **失效** | M3 scale 36 / 16 / 22 |
| `check-tokens.py`（解析 32 字段色板） | **删除** | `tool/check_tokens.dart`（真实 M3 scheme） |
| CSS z-index 语义映射 | **失效** | Flutter route / Overlay / Scaffold slot |
| `--et-shadow-*`、`--et-glow-*` | **失效** | M3 elevation；禁止 glow |
| v1 别名（`--et-cyan`、`--font-sans` 等） | **失效** | 无别名层，不要重建 |

### 8.1 被 v5 取代的 v4（flat M3）规则

| v4 规则 | v5 现状 | 原因 |
|---|---|---|
| 卡片统一 12dp 圆角 | 卡片 **24**、hero 32、统计块 20、icon badge squircle | Expressive 形状语言（MASTER §5） |
| Home hero 是 36px（displaySmall） | hero 是 **45px**（displayMedium，`EtType.expressive`） | 表现性排版：一个屏幕一个主角 |
| “禁止 glow / 光晕”绝对化 | 改为**配额制**：hero aurora、orb、图表 glow、hero 内高光四处 | 表现力需要，但必须有边界（MASTER §v5.3） |
| 所有平面都是纯 M3 tonal，不加渐变 | hero 用 `_AuroraPainter` 自绘 aurora；`surfaceGlow` 用于 Settings About；`EtGradient.hero` 是未消费的备用定义 | 装饰层不算「角色」，但必须被约束 |
| KPI 用 `EtKpi` 的灰底 caption + 数字 | Home 改用 `EtStatTile`（tonal bento） | 统计块参与色彩编码；`EtKpi` 仍用于 Network 卡 |
| 导航使用 M3 默认 80dp bar | bar **76dp** + stadium indicator | Expressive 自定义尺寸（MASTER §17 V9） |
| 选中导航图标未做 filled | 仍未做；靠 indicator pill 承担 | 见 MASTER §17 D2 |
| 无 shape morph | 仍无；只有静态圆角 | M3 Expressive 的 35-shape/morph 是未来项（MASTER §17 V5） |

## 9. 更新令牌的流程

1. 只改 `easytier-flutter/lib/core/theme/tokens.dart` / `theme.dart`（唯一合法位置）。
2. 跑门禁：

   ```bash
   bash /home/chance/Projects/.flutter-run.sh \
        /home/chance/Projects/easytier/easytier-flutter test tool/check_tokens.dart
   ```

   失败会打印具体 role 对与实测比值；退出码非 0 即阻断。
3. 若是有意改变语义/阈值，同一次提交里更新 MASTER §3.5 / §17 与本文件的映射表。
4. 只有**映射关系**变化（新增/删除 token 或组件）才需要改本文件；单纯 hex 变化由
   脚本输出体现，不要手抄进文档。

## 10. 常见坑

1. **`text2` 与 `text3` 是同一个 role。** 不要再造第三个文字层级。
2. **`border` 不是控件边界。** 控件用 `controlBorder`（= `outline`）；`border`
   是装饰性 `outlineVariant`，没有对比契约。
3. **不要手搭状态层。** Material 组件已经实现 M3 的 8%/10%/16%；`withOpacity`
   只在 `textDisabled`（38%）这一处允许。
4. **禁用色不是 4.5:1。** M3 的 38% 在浅色下只有 2.35:1，WCAG 豁免；不要为它
   调色，改用形状/文字提示禁用。
5. **浅色 success 必须够深。** `#1E8E3E` 只有 4.21:1；当前用 `#137333`（5.95:1）。
   要换亮绿就必须同时把状态标签改成 `onSurface`。
6. **平台 mono 没有 CJK。** 中文标签用 `EtText.ui`，数值用 `EtText.mono`，
   用 `Text.rich` 拆 span，不要拼一个字符串。
7. **自造组件是债务。** 新增自造组件前先注册到 MASTER §17；M3 能覆盖的一律用
   M3 组件（分段控件、下拉、chip、搜索都是现成的）。
8. **`EtPalette` 不插值。** 主题切换在 `lerp` 中点硬切，M3 颜色 role 是离散的。
9. **45px 只属于 Home hero。** `EtType.expressive` 出现第二次就是缺陷；卡片/列表
   用 baseline 字号。
10. **`EtAccent` 不是控件色。** 它只做 aurora/orb/avatar 底色；按钮、边框、文字、
    选中态仍然只用 `ColorScheme` role。
11. **渐变只有两张、glow 只有四处。** 新增渐变/发光前先改 MASTER §v5.3 的配额，
    否则就是“霓虹 VPN”俗套。
12. **hero 文字必须落在 scrim/实色容器上。** 装饰层不参与对比度计算；`check_tokens.dart`
    目前只测 role 对，hero 合成层是 MASTER §17 V3 的待补断言。
13. **`compact` density 目前没有调用点。** `buildEtTheme(compact:)` 存在但
    `app.dart` 未传 `true`（MASTER §17 V7）；不要以为宽窗已经 compact。
