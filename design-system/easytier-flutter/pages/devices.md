# Devices — “谁在上面？谁慢？”

> `design-system/easytier-flutter` 的逐屏规格。它**收紧**
> [`../MASTER.md`](../MASTER.md)，不得引入新的颜色、字体、圆角、时长或图标风格。
> 与 MASTER 冲突时 MASTER 胜。
>
> 视觉方向是 **Google Material 3 + Expressive**（v5）：每个 peer 是一个
> `EtAvatar` + 两行 `ListTile` + stadium `LatencyPill`；顶部用 tonal summary chips
> 做状态概览；搜索是 M3 `SearchBar`，排序是 M3 menu，宽窗是 M3 `DataTable`。

| | |
|---|---|
| **问题** | 谁在我的 mesh 上？谁慢？ |
| **主操作** | 无（导航屏）；peer 详情是 `showEtSheet` |
| **M3 / Expressive 组件** | small `AppBar`、`SearchBar`、`PopupMenuButton` + `CheckedPopupMenuItem`、`Card`、`ListTile`、`EtAvatar`、`LatencyPill`、summary chip、`DataTable`、`EtBadge`、`EtBanner`、`EtEmptyState` |
| **目的地** | 2 / 5 |
| **数据来源** | `InstanceStatus.peers`（`hostname`、`ipv4`、`online`、`latencyMs`、`path`、`lastSeen`、`id`）、`routeCount`、`ConnectionPhase` |

## 1. 目的

Devices 回答“谁在上面、谁慢”。它是**全量 peer 列表**，不是摘要：Home 只显示
3 个在线 peer + 离线 peer，Devices 显示全部。排序、搜索、路径（direct / relay）
都在这里。

**离线 peer 永远不隐藏** —— 它们排在列表最后并标注离开时长。用户排查“谁掉了”时，
消失的节点比灰掉的节点更有害。

## 2. 布局骨架（手机，上→下）

1. **Small top app bar**：标题 `Devices`（`headlineSmall` w600），副标题：
   `{online} of {total} online · {routes} routes` / “Connecting…” /
   “Connection failed” / “Not connected”。actions 最多两个：
   - 排序 `PopupMenuButton`（`Symbols.sort`，tooltip “Sort devices”，
     `CheckedPopupMenuItem`：Latency / Name / Status）；
   - 搜索开关 `IconButton`（`Symbols.search` / `close`，48×48）。
2. **搜索栏**（仅打开时）：M3 `SearchBar`，底色是 **primary tint 的
   `surfaceContainerHigh`**（暗色 16% / 亮色 8%，Expressive 处理），全圆角、
   leading `Symbols.search`、有输入时 trailing 清除按钮，hint
   “Filter by hostname or IP”。打开时自动 focus，关闭时清空。
3. **状态横幅**（`EtBanner`，条件渲染）：全部中继 → warn；连接失败 → danger。
4. **Summary chips**（已连接且有 peer 时）：`Wrap` 里的三枚 stadium chip：
   - `{n} online`（`Symbols.check_circle`，`EtTone.success`）
   - `{n} offline`（`Symbols.radio_button_unchecked`，`EtTone.neutral`）
   - `{n} routes`（`Symbols.alt_route`，**`EtTone.tertiary`**）
   `spacing/runSpacing` 8；窄屏自动换行，不横向滚动。
5. **Peer 列表**（`EtSurface`，radius 24，行内左右各缩进 8，让 avatar/pill
   “浮”在卡里）：
   - **分组头**：`labelLarge`、`onSurfaceVariant`、16 inset，“Online · {n}” /
     “Offline · {n}”。
   - **`EtPeerRow`**（`ListTile`）：
     - leading：`EtAvatar(name, 40)`（首字母 + 装饰色圆底）；
     - title：hostname（`bodyMedium` w500；离线时附 `EtBadge` “offline 12m”）；
     - subtitle：虚拟 IP（mono caption）+ **relay path**（` · Relay via X`，
       仅在线且非 direct 时显示，relay 用 `warn` 色文字）；
     - trailing：**latency pill**——列表里是 `EtPeerRow` 内联的“语义色 14% 叠在
       `surfaceContainerHigh` 上”的 stadium pill；宽窗表格/详情用 `LatencyPill`
       （真正的 M3 container role）。两者视觉一致，但实现不同，见 MASTER §17 V12。
   - 行间 `Divider`（`outlineVariant`）。整行可点 → peer 详情 sheet。
6. **Peer 详情**（`showEtSheet`）：header `ListTile`（`EtAvatar` 48 + hostname
   `titleLarge` + IP mono + 状态 `EtBadge`），`Divider`，然后 Path / Latency
   （`LatencyPill`）/ Last seen / Peer ID 四行，底部一个 filled “Copy IP”。
   不提供“踢人”：客户端没有这个能力。

**宽窗（≥840，`etDesktop`）**：M3 `DataTable`（`EtSurface` 内，radius 24），
四列：**Status | Device | Path | Latency**。表头 `labelLarge` + `onSurfaceVariant`
+ 排序指示器；`headingRowHeight 48`，`dataRowMinHeight 56 / max 72`；
Status 是 `EtBadge`（icon + label，tone 来自 latency ladder）；Device 是
`EtAvatar` 32 + hostname/IP 两行；Path 是 relay badge 或直连文本；
Latency 是右对齐 `LatencyPill`。

## 3. Latency tone ladder（v5）

| 条件 | tone | 载体 |
|---|---|---|
| 离线 / 无延迟 | neutral | pill / badge |
| `path == relay` | warning | pill（即使延迟数字低） |
| 延迟 > 90ms | danger | pill |
| 其余在线 | success | pill |

**v4 的 40/90 双阈值在 v5 收敛为 90ms 单阈值 + relay 优先。** 颜色永远是辅助：
pill 里有数字、subtitle 里有 “Relay”，颜色不是唯一线索。

## 4. M3 / Expressive 组件清单

| 区域 | 组件 | role / token | 约束 |
|---|---|---|---|
| 页面 | small `AppBar` | `surface`，标题 `headlineSmall` | 副标题表达连接状态 |
| 排序 | `PopupMenuButton` | M3 menu | 选中项 check |
| 搜索 | `SearchBar` | primary tint + `surfaceContainerHigh` | 打开 focus，关闭清空 |
| 摘要 | stadium chips | success / neutral / **tertiary** container | `Wrap`，不横滚 |
| 列表 | `EtSurface` + `ListTile` | radius 24 | 行高 ≥56 |
| 头像 | `EtAvatar` | `EtAccent` 装饰色 + `onSurface` 首字母 | `ExcludeSemantics` |
| 延迟 | `LatencyPill` / 内联 pill | 容器底 + mono 数字 | stadium；颜色辅助；合成层的对比度待断言（MASTER §17 V12） |
| 宽窗表 | `DataTable` | M3 默认 + `EtSurface` | 行点击打开 sheet |
| 空态 | `EtEmptyState` | — | 图标 + 一句解释 + 一个下一步 |

## 5. 状态

| 状态 | 内容 | 下一步 |
|---|---|---|
| 未连接 | `EtEmptyState`（`Symbols.devices`，“Connect to see peers / The full device list appears here once the network is up.”） | `FilledButton` “Connect” |
| 连接中 | `EtEmptyState`（`Symbols.monitor_heart`，“Connecting…”）；peer 可先流入 | 无 |
| 连接失败 | `EtEmptyState`（`Symbols.report`，“Could not connect” + 原因） | `FilledButton` “Try again” |
| 已连接但无 peer | `EtEmptyState`（`Symbols.devices`，“No peers yet / This device is alone on the network. Peers show up here as they join.”） | 无 |
| 已连接、有 peer | summary chips + 在线/离线分组；降级时顶部 warn 横幅 | 点行看详情 |
| 搜索无结果 | `EtEmptyState`（`Symbols.search`，“No devices match / Nothing matches “{query}”. Try a hostname or a virtual IP.”） | `OutlinedButton` “Clear search” |

排序默认延迟升序（离线最后）；排序选择只在本次会话保留。

## 6. 文案（EN / zh）

| 语境 | EN | zh |
|---|---|---|
| 标题 | Devices | 设备 |
| 副标题（已连接） | {online} of {total} online · {routes} routes | {online}/{total} 在线 · {routes} 条路由 |
| 副标题（其它） | Connecting… / Connection failed / Not connected | 正在连接… / 连接失败 / 未连接 |
| 搜索 | Filter by hostname or IP / Search devices / Clear search | 按主机名或 IP 过滤 / 搜索设备 / 清除搜索 |
| 排序 | Sort devices · Latency / Name / Status | 排序设备 · 延迟 / 名称 / 状态 |
| Summary chips | {n} online / {n} offline / {n} routes | {n} 在线 / {n} 离线 / {n} 条路由 |
| 分组 | Online · {n} / Offline · {n} | 在线 · {n} / 离线 · {n} |
| Path | Direct / Relay | 直连 / 中继 |
| 延迟 | {n} ms / — | {n} ms / — |
| 离线徽章 | offline 12m | 离线 12m |
| 表中列 | Status · Device · Path · Latency | 状态 · 设备 · 路径 · 延迟 |
| 搜索无结果 | Nothing matches “{query}”. Try a hostname or a virtual IP. | 没有匹配 “{query}” 的结果。试试主机名或虚拟 IP。 |
| 全部中继 | All peers are relayed / No direct path is available right now; latency includes relay hops. | 所有节点都走中继 / 当前没有直连路径；延迟包含中继跳数。 |
| Copy IP | Copy IP / Copied {ip} | 复制 IP / 已复制 {ip} |

规则：`Online` / `Offline` 是状态词，不是动词；延迟单位 `ms` 只在数值槽位；
离线显示 `—` 而不是 “0 ms”；peer 名字与 IP 是用户数据，不翻译、不缩写。

## 7. 响应式（M3 window size classes）

- compact（<600）：单列；summary chips `Wrap`；行高 ≥56；gutter 16。
- medium（600–839）：rail 导航；仍是列表；gutter 16。
- expanded（≥840）：`DataTable`（Status/Device/Path/Latency）；gutter 24；
  内容 ≤1040。
- 200% 字号：表格单元格优先换行；延迟列（pill）不裁切；hostname 省略时详情页
  给完整值；不出现整页横向滚动。
- 排序/滚动位置跨旋转与 tab 保留。

## 8. 无障碍

- 行语义合并：“{hostname}, {status}, {latency}, {path}”；avatar/图标
  `ExcludeSemantics`；离线行播报 “offline, last seen 12m ago”。
- 状态不只靠颜色：online/offline 有图标 + 文字；relay 有 subtitle 文本 + badge。
- 排序、搜索、清除都有 tooltip / semantic label，且 48×48。
- 表头是真实语义（`Semantics(header: true)`）；排序变化播报
  “Sorted by latency, ascending”。
- 延迟 pill 朗读为 “18 milliseconds”，不是 “18 ms” 字母。
- reduced motion：搜索展开/列表重排不做位移动画。
- 触摸目标 ≥48；peer 行整行可点。

## 9. 本屏不做什么

没有连接/断开（Home）、没有配置编辑（Config）、没有“踢出 peer”、没有流量历史图、
没有自绘 peer 类型图标。搜索只过滤当前 peer 列表，不做全库搜索。
