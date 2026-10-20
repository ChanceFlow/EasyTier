# Settings — “App 对我怎么表现？”

> `design-system/easytier-flutter` 的逐屏规格。它**收紧**
> [`../MASTER.md`](../MASTER.md)，不得引入新的颜色、字体、圆角、时长或图标风格。
> 与 MASTER 冲突时 MASTER 胜。
>
> 视觉方向是 **Google Material 3 + Expressive**（v5）：每组是“tonal icon badge
> 组头 + `titleMedium` 标题 + 一张 calm card”；行 leading 是更小的 icon badge；
> 主题/语言是 `SegmentedButton`，机器数据放 mono pill；About 组用一次
> `EtGradient.surfaceGlow` 作为 Expressive 强调。

| | |
|---|---|
| **问题** | App 对我怎么表现？ |
| **主操作** | 无。设置即时生效，没有 Save 按钮。 |
| **M3 / Expressive 组件** | small `AppBar`、`EtSurface` 卡、`ListTile`、`EtIconBadge`、`SegmentedButton`、`EtTextField`、`DropdownMenu`、`EtBadge`、mono chip、`AlertDialog`、`SnackBar` |
| **目的地** | 5 / 5 |
| **数据来源** | `AppState.themeMode`、`AppState.locale`、`instances` / `activeId`、core 版本、日志级别 |

## 1. 目的

所有 App 级偏好与平台相关项集中在一处，按组可扫读。设置是**即时生效**的（没有
保存栏、没有主按钮）：一个需要 Save 的开关就是 bug。不能立刻生效的能力（尚未接入
的 M2 功能）要显示真实状态与明确动作，不能给假开关。

破坏性/不可逆项放在最后并显著分隔（danger 组：danger 组头 + 卡边 danger 35%）。
整屏不出现 filled 按钮；唯一的 filled 只可能出现在破坏性确认对话框中。

## 2. 布局骨架（手机，上→下）

内容宽度 ≤720 居中；组之间 `EtSpace.x4`。每组 =
`SettingsGroup`：组头（`EtIconBadge` 36 + `titleMedium` w600 + 可选 subtitle）
+ 下方 `EtSurface` 卡（radius 24，垂直 padding 8，行间 `SettingsDivider`）。

1. **Appearance**（`Symbols.contrast`，accent）
   - `SettingsFieldLabel`（`Symbols.palette`，accent）→ 全宽
     `SegmentedButton<ThemeMode>`（Dark / Light / System，最小高 52，
     `expandedInsets: EdgeInsets.zero`）；
   - `SettingsDivider`；
   - `Reduced motion` 行（`Symbols.animation`，info）：只读，trailing `EtBadge`
     “Reduced”（info）/“Full”（neutral），helper “Controlled by your system
     accessibility settings.”；下方 caption “The client always follows the system
     motion preference.”。**不在 App 内复制系统开关。**
2. **Language**（`Symbols.language`，info，subtitle “UI language (coming in M2)”）
   - 全宽 `SegmentedButton<Locale>`（English / 中文，最小高 52）；
   - caption：字符串在 M2 翻译通道完成前只有英文，偏好已保存。
3. **Core**（`Symbols.memory`，tertiary）
   - `Core version`（`Symbols.build`，tertiary）trailing = `SettingsMonoChip`
     （`surfaceContainerHighest` pill，mono；“Loading…” / “Unavailable”）；
   - `Mode`（`Symbols.info`，info）：subtitle 说明进程内运行，footer
     `EtBadge` success “Normal (in-process)”。
4. **Config server**（`Symbols.cloud_sync`，info，subtitle 说明自建服务器）
   - `EtIconBadge(Symbols.dns, info, 32)` + `EtTextField`（outlined，mono，
     “Server URL”，helper “Stored locally. Fetching networks is not wired yet.”）；
   - 禁用 `OutlinedButton.icon(Symbols.sync, “Connect”)`，外包 `Tooltip("M2")`；
   - caption “Fetching networks arrives in M2.”。**不做点了没反应的按钮。**
5. **Logs**（`Symbols.article`，neutral）
   - `EtIconBadge(Symbols.terminal, neutral, 32)` + `DropdownMenu<_LogLevel>`
     （Off/Warn/Info/Debug/Trace，`textStyle` = mono `bodySm`，`expandedInsets` 0）；
   - caption “Local only — the core does not receive this setting yet.”。
6. **About**（`Symbols.info`，tertiary，**`glow: true`** —— 全 App 唯一一次
   surfaceGlow）
   - `App version`（accent）trailing `EtBadge(appVersion, tertiary, verified)`；
   - `Core version`（neutral）trailing mono chip；
   - `Documentation` / `Source repository`：`Symbols.menu_book` / `code`，subtitle
     域名，trailing `EtBadge("M2")`，外包 `Tooltip("Coming in M2")`。
7. **Danger zone**（`Symbols.warning`，danger，subtitle “Destructive actions.
   They cannot be undone.”；卡边 `error` 35%）
   - `Delete this network`：`SettingsRow` 的 destructive 分支（title/icon 用
     `danger`），subtitle 说明会停止隧道并从本设备移除配置；点击弹 `AlertDialog`
     （对象 + 后果 + `Cancel` 默认焦点 + filled danger 确认）；成功后
     `SnackBar` “Network deleted”。

**宽窗（≥840）**：同一列组，宽度 ≤720 居中于 1040 内容区；rail 导航；无 bottom bar。

## 3. 组头 / 行结构

- **组头**：`EtIconBadge` 36（accent/info/tertiary/neutral/danger）+ 标题
  `titleMedium` w600 + 可选 subtitle（`bodySmall`、`onSurfaceVariant`）+ 可选
  `meta`（如状态 badge）。`glow: true` 时组头包一层 `EtGradient.surfaceGlow`
  的 16 圆角带（仅 About）。
- **行**（`SettingsRow` = `ListTile`）：leading `EtIconBadge` 32；title
  `bodyLarge` w500；subtitle `bodySmall`；可选 footer（第二行 badge）；trailing
  是值/控件（`EtBadge`、mono chip、`SegmentedButton`、`DropdownMenu`）。
- 只有开关的行不整行可点（点 label 就切换会意外）；打开新页面的行整行可点且带
  `chevron_right`。值右对齐；机器数据一律 mono。
- 破坏性行 label/icon 用 `danger`，不用 filled 样式。
- 平台不支持的行直接隐藏，不要灰着不解释。

## 4. M3 / Expressive 组件清单

| 区域 | 组件 | role / token | 约束 |
|---|---|---|---|
| 页面 | small `AppBar` | `surface`，`headlineSmall` | 副标题 = 实例名 |
| 组 | `SettingsGroup` | `EtIconBadge` + `titleMedium` | About 唯一 glow |
| 卡 | `EtSurface` | `surfaceContainerLow`、radius 24 | danger 组卡边 danger 35% |
| 行 | `SettingsRow`（`ListTile`） | bodyLarge w500 + icon badge 32 | ≥48 行高 |
| 主题/语言 | `SegmentedButton` | M3 默认、最小高 52 | 全宽 |
| 只读状态 | `EtBadge` / mono chip | `surfaceContainerHighest` pill | 不可聚焦、无 chevron |
| 输入 | `EtTextField`（outlined） | `outline` / focus `primary` | label 可见 |
| 下拉 | `DropdownMenu` | M3 menu | 不用 M2 `DropdownButton` |
| 不可用能力 | 禁用控件 + `EtBadge("M2")` + tooltip | `onSurfaceVariant` | 不做假动作 |
| 破坏性 | `AlertDialog` | M3 默认 + `error` 确认 | 焦点默认 Cancel |
| 反馈 | `SnackBar`（floating） | `inverseSurface` | 一次一个 |

## 5. 状态

| 状态 | 行为 |
|---|---|
| 默认 | 值来自已持久化设置；首帧后不出现骨架 |
| 主题/语言切换 | 立即生效；`EtDuration.slow`（state intent）；reduced motion 即时；不整屏刷新、不跳滚动位置 |
| Reduced motion（系统） | 行 trailing badge 显示 “Reduced”；App 不提供反向开关 |
| Core 版本读取中 | mono chip “Loading…”；失败 “Unavailable”，不留空 |
| Config server | URL 本地保存；Connect 为 M2 禁用状态 |
| Log level 变更 | 即时写入；caption 说明“仅本地生效” |
| 删除确认 | 对话框写明对象/后果；焦点 Cancel；成功 snackbar |
| 删除失败 | 对话框/snackbar 给原因 + 重试；不静默失败 |

## 6. 文案（EN / zh）

| 语境 | EN | zh |
|---|---|---|
| 标题 | Settings | 设置 |
| 组 | Appearance · Language · Core · Config server · Logs · About · Danger zone | 外观 · 语言 · 内核 · 配置服务器 · 日志 · 关于 · 危险操作 |
| Theme | Theme · Dark / Light / System | 主题 · 深色 / 浅色 / 跟随系统 |
| Reduced motion | Reduced motion · Reduced / Full | 减弱动态效果 · 已减弱 / 完整 |
| Motion helper | Controlled by your system accessibility settings. / The client always follows the system motion preference. | 由系统无障碍设置控制。 / 客户端始终跟随系统动效偏好。 |
| Language | Language · English / 中文 | 语言 · English / 中文 |
| Language note | Strings are English-only until the M2 translation pass; the preference is stored now. | M2 翻译通道完成前仅提供英文；偏好已保存。 |
| Core | Core version · Mode · Normal (in-process) | 内核版本 · 模式 · 普通（进程内） |
| Config server | Config server · Server URL · Connect | 配置服务器 · 服务器地址 · 连接 |
| Server helper | Stored locally. Fetching networks is not wired yet. | 仅本地保存；拉取网络尚未接通。 |
| Logs | Logs · Log level · Local only — the core does not receive this setting yet. | 日志 · 日志级别 · 仅本地 —— core 尚未接收该设置。 |
| About | About · App version · Core version · Documentation · Source repository | 关于 · App 版本 · 内核版本 · 文档 · 源码仓库 |
| Danger | Danger zone · Destructive actions. They cannot be undone. | 危险操作 · 破坏性操作，无法撤销。 |
| Delete | Delete this network / Removes “{name}” from this device and stops the tunnel. | 删除这个网络 / 从本设备移除“{name}”并停止隧道。 |
| Delete confirm | Delete this network? | 删除这个网络？ |
| Deleted | Network deleted | 网络已删除 |
| M2 | Coming in M2 / M2 | M2 提供 / M2 |

## 7. 响应式（M3 window size classes）

- compact（<600）：单列，gutter 16；行高 ≥56；Danger zone 通过滚动可达。
- medium（600–839）：rail 导航；内容 ≤720。
- expanded（≥840）：rail + 列 720；行 hover 用 M3 状态层（不手写 opacity）。
- 200% 字号：行变高，trailing 值换到 label 下方；`SegmentedButton` 允许换行/增高，
  switch 不与文字重叠。
- 任何行都不产生横向滚动。

## 8. 无障碍

- 每个 switch/segmented 行：`Semantics(label:, toggled:)` 或 M3 单选组语义；
  可见 label 即可访问名，helper 是 hint。
- `SegmentedButton` 是真实单选组，桌面键盘方向键可切换。
- 只读行（Reduced motion）不可聚焦、无 chevron/switch，不会被误认为控件。
- 外部链接播报“打开浏览器”；M2 行的 tooltip 同时是语义提示。
- 破坏性确认：焦点从 Cancel 开始，后果在正文，确认按钮说清动作。
- Snackbar：一次一个，礼貌播报；关键失败不能只靠 snackbar。
- 图标按钮（返回、chevron）有 label；无 emoji。
- 对比度：行文字用 `onSurface`/`onSurfaceVariant`；danger 文字在
  `surfaceContainerLow` 上 ≥5.86:1（浅色）/ ≥10.12:1（深色）；mono chip 文字
  `onSurfaceVariant` on `surfaceContainerHighest` ≥7.27:1。
- reduced motion：主题切换即时，无 hover 补间、无 chevron 动画；About 的
  surfaceGlow 是静态渐变。

## 9. 本屏不做什么

没有 Save 按钮、没有应用内字号滑块（跟随系统）、没有重复 VPN 开关（连接在 Home）、
没有假开关（未实现的能力标 M2 / 不可用）、没有账号/云同步、没有第 6 个 tab。
