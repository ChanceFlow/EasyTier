# Home — “我的 mesh 通吗？多健康？”

> `design-system/easytier-flutter` 的逐屏规格。它**收紧**
> [`../MASTER.md`](../MASTER.md)，不得引入新的颜色、字体、圆角、时长或图标风格。
> 若本文件与 MASTER 冲突，MASTER 胜，并在这里修正。
>
> 视觉方向是 **Google Material 3 + Expressive**（v5）：本页是**唯一 hero 屏**——
> 一个 32dp 圆角的渐变 hero 主宰首屏，其余是支撑块。所有控件必须是 M3 组件或
> MASTER §9 登记过的 kit 组件；禁止自绘新的控件形态。

| | |
|---|---|
| **问题** | 我的 mesh 通吗？多健康？ |
| **主操作** | hero 内唯一的 `FilledButton`：Connect / Reconnect / Disconnect（v5 三者都 filled） |
| **唯一 hero 数字** | 到最近 peer 的延迟（45px，`EtType.expressive`） |
| **目的地** | 1 / 5，落地屏 |
| **M3 / Expressive 组件** | hero 容器（`EtRadius.hero` + aurora）、`EtConnectionOrb`、`EtBadge`、`EtStatTile`、`EtSurface`、`EtSpeedGraph`、`EtPeerRow`、`FilledButton`、`ListTile` |
| **数据来源** | `AppState.active`、`AppState.status`（`ConnectionPhase`）、`InstanceStatus`（`latencyMs`、`peerCount`、`onlinePeers`、`routeCount`、`rxBps`、`txBps`、`uptime`、`history`、`error`） |

## 1. 目的

Home 只回答一个问题、只提供一个决定。它不是 dashboard：没有配置字段、没有日志
尾巴、没有 per-peer 表格。打开 App 三秒的人，应当按“hero 的 orb/badge → 状态句 →
45px 延迟 → 主操作”的顺序判断“通没通”。

v5 的 hero-first 是刻意的：第一版 flat M3 的“五张等价卡片”被用户否决；现在
Home 有且只有一个视觉主角，其余块都退到支撑位置。

## 2. 布局骨架（手机，上→下）

在 `SafeArea` 内，`surface` canvas，一列 `EtScrollBody`（maxWidth 1040，块间距 16）：

1. **Small top app bar**：标题 `Home`（`headlineSmall` w600），副标题 = 网络名
   （`bodySmall`、`onSurfaceVariant`，单行省略）。无 overflow、无第二操作；
   实例管理在 Config。
2. **状态横幅**（`EtBanner`，仅降级/失败时出现，位于 hero 之上）：
   降级 = `warningContainer`/`onWarningContainer`；失败 = `errorContainer`/
   `onErrorContainer`。可带一个 `TextButton`，但不是主操作。
3. **Hero**（`Container`，`EtRadius.hero` = 32，`primary` 22% 1px 描边，
   `clipBehavior: antiAlias`）—— **全屏唯一主角**：
   - **背景 aurora**：`_AuroraPainter` 的 5 个 radial blob（`EtAccent.blue/violet/
     cyan`）+ 顶部 1px 内高光 + **下半部 scrim**（`surfaceContainerHigh` 0.12→0.48），
     保证状态句/数字/按钮落在稳定 tonal 层上。
   - **强度随状态变化**：connected 1.0 / connecting 0.85 / degraded 0.7 /
     idle·error 0.40（暗色 screen blend；亮色降低 alpha 约 0.55×）。
   - **第一行**：`EtBadge`（tone = 状态，icon = Symbols）+ 右侧 uptime
     （mono caption：“up 2h 14m”，未连接 `—`）。
   - **orb**：`EtConnectionOrb`（112dp，glow + 三层环 + 中心图标）；connecting/
     connected 时环脉冲（`loopRing`），reduced motion 静止。
   - **状态句**（`titleMedium`、`onSurface`，最多 2 行，居中）。
   - **Latency 块**：`Latency` label（`labelLarge`、`onSurfaceVariant`）+
     **45px** 数字（`EtType.expressive`，mono `w700`，height 1.05，`onSurface`；
     未连接 `—` 用 `onSurfaceVariant`）+ `ms`（`titleMedium`）+
     “to nearest peer”（`bodySmall`）。数字切换用 `EtCurves.spring` + 200ms；
     **不做 count-up**。
   - **主操作**（整宽、48 高，在 hero 内）：Connect/Reconnect/Disconnect 都是
     filled；connecting 时 disabled + inline spinner + 文案不变。
4. **Bento 统计**（`HomeStatsRow`，三枚 `EtStatTile`，间距 12）：
   - **Peers**：`Symbols.devices`，值 `{online} / {total}`，tone = accent；
   - **Routes**：`Symbols.alt_route`，值 `{routeCount}`，tone = warn；
   - **Downlink**：`Symbols.arrow_downward`，值 `formatRate(rxBps)`，tone = success。
   - 未连接时三枚都降为 `EtTone.neutral` 且值显示 `—`（不做假数据）。
5. **Traffic 卡**（`EtSurface`）：标题 `Traffic` + `last 60 s`；live 时
   `EtSpeedGraph`（phone 140 / wide 180 高；v5 有 line glow + 末点圆点）+
   `EtTrafficLegend`；未连接时是静态空态（`Symbols.monitoring` + 一句话），
   **绝不画假曲线**。
6. **Peers 卡**（`EtSurface`）：标题 `Peers` + “{n} of {m} online”；内容为延迟
   最低的 3 个在线 peer + 全部离线 peer 的 `EtPeerRow`（avatar 40 + hostname/IP +
   latency pill），行间 `Divider`。离线 peer 永不隐藏。
7. **Network 卡**（`EtSurface`）：标题 `Network`；`ListTile` 数据行：Virtual IP
   （mono）、Instance（mono）、Network；`Divider` 后是两个 `EtKpi`
   （Peers online / Routes）。

**宽窗（≥900，代码值；M3 expanded 是 840，见 MASTER §17 V8）**：左栏 flex 5
（hero、bento、network 卡），右栏 flex 5（traffic、peers）。rail 从 600 起提供
导航，不出现 bottom bar。

## 3. Hero 的硬规则

- **全 App 唯一的 45px 数字。** `EtType.expressive` 出现在别的屏幕/别的块上就是缺陷。
- **aurora 只在 hero。** 其他卡片/列表不允许渐变或 glow；`EtGradient` 只服务
  hero 与 Settings About 标题。
- **文字必须落在 scrim/实色上。** hero 上半部只放 badge/uptime（小字在 badge 容器
  里），状态句/数字/按钮都在下半部 scrim 区；不允许把 16px 文字直接压在亮 blob 上。
- **orb 是装饰。** `ExcludeSemantics`；状态语义由 badge + 状态句 + 延迟承担。
- **idle 要“安静但好看”。** 未连接时 aurora 降到 0.40，hero 仍完整，但不与
  “已连接”抢注意力。
- **动作只有一个。** hero 内只能出现一个主操作；不给第二个 filled 按钮留位置。

## 4. M3 / Expressive 组件清单

| 区域 | 组件 | role / token | 约束 |
|---|---|---|---|
| 页面 | small `AppBar` | `surface`，标题 `headlineSmall` | 无 overflow |
| Hero | 自定义容器 + `_AuroraPainter` | `EtRadius.hero`(32)、`EtAccent`、scrim `surfaceContainerHigh` | 仅 Home；文字在 scrim 上 |
| 连接 orb | `EtConnectionOrb` | 状态色（success/primary/warning/error/neutral） | `ExcludeSemantics`；reduced motion 静止 |
| 状态 badge | `EtBadge` | 语义 container 对 | 文字即状态句 |
| Hero 数字 | `EtText.mono` + `EtType.expressive` | `onSurface`（large text 3:1 也满足） | w700、h1.05、全 App 唯一 |
| 主操作 | `FilledButton`（`EtPrimaryButton`） | `primary`/`onPrimary` | 48 高；busy 保留 label + spinner |
| Bento | `EtStatTile` ×3 | accent (`primaryContainer`) / warn (`warningContainer`) / success (`successContainer`) | 未连接统一 neutral |
| 卡片 | `EtSurface` | `surfaceContainerLow`、elevation 1、radius 24 | 卡内不再套卡 |
| 图表 | `EtSpeedGraph` | `primary` + `tertiary`，加 glow | 有 Semantics 文本等价物 |
| peer 行 | `EtPeerRow` | avatar + latency pill + mono IP | 离线行保留 |

## 5. 状态

| 状态 | Hero badge / orb | aurora | 45px 数字 | 主操作 | 内容 |
|---|---|---|---|---|---|
| 无网络 | 不渲染 hero | — | — | `FilledButton` “Add network”（去 Config） | 整屏空状态 |
| 已停止 | badge neutral / orb `shield` neutral | 0.40 | `—` | filled “Connect” | 流量空态；Peers 空态；bento `—` |
| 连接中 | badge info / orb `sync` primary，环脉冲 | 0.85 | `—` | disabled “Connecting…” + spinner | 流量 “Waiting for the tunnel…” |
| 已连接 | badge success / orb `shield` success | 1.0 | 延迟数字 | filled “Disconnect” | 实时曲线；bento 有值 |
| 降级 | badge warning / orb `warning` | 0.7 | 延迟数字（仍 `onSurface`） | filled “Disconnect” | 顶部 warn 横幅；relay path |
| 失败 | badge danger / orb `link_off` | 0.40 | `—` | filled “Reconnect” | 顶部 error 横幅；流量 “Traffic stopped.” |
| bootstrap | shell splash | — | — | — | 不出现只有 spinner 的空屏 |

## 6. 文案（EN / zh）

| 语境 | EN | zh |
|---|---|---|
| badge（未运行/连接中/已连接/降级/断开） | Not running / Connecting / Connected / Degraded — relay only / Disconnected | 未运行 / 连接中 / 已连接 / 降级 — 仅中继 / 已断开 |
| 状态句 | Not connected · Connecting to {network}… · Connected to {network} · Connected to {network} · relay path · Connection failed | 未连接 · 正在连接 {network}… · 已连接 {network} · 已连接 {network} · 中继路径 · 连接失败 |
| 主操作 | Connect / Disconnect / Reconnect / Connecting… / Disconnecting… | 连接 / 断开 / 重新连接 / 正在连接… / 正在断开… |
| Hero 标签 | Latency / to nearest peer / ms | 延迟 / 到最近节点 / ms |
| 无延迟语义 | Latency unavailable | 延迟不可用 |
| Bento | Peers · Routes · Downlink | 节点 · 路由 · 下行 |
| Traffic | Traffic · last 60 s / Traffic starts when you connect. / Waiting for the tunnel… / Traffic stopped. | 流量 · 最近 60 秒 / 连接后开始统计流量。 / 等待通道建立… / 流量已停止。 |
| Peers | Peers · {n} of {m} online / Connected, but no peers yet. Share the network name to invite a device. | 节点 · {n}/{m} 在线 / 已连接，但还没有节点。分享网络名称即可邀请设备。 |
| 横幅 | Relay-only path / Network degraded / Connection failed | 仅中继路径 / 网络降级 / 连接失败 |
| 无网络 | No networks yet / Add a network to start routing peers. | 还没有网络 / 先新建网络才能开始组网。 |

规则：无感叹号；“Connecting…” 用省略号字符；延迟单位是 `ms`（中文标签在 label，
数字槽位不放“毫秒”）；错误句以失败对象开头。

## 7. 响应式（M3 window size classes）

| Class | 宽度 | 布局 |
|---|---|---|
| compact | <600 | 单列；hero 全宽；图表 140；45px 数字 |
| medium | 600–839 | 单列；rail 导航；图表 160 |
| expanded | 840–1199 | 双栏（5/5）；图表 180；代码在 **900** 切双栏（MASTER §17 V8） |
| large / x-large | ≥1200 | 同上，内容 ≤1040；rail 显示文字标签 |

- hero 在 360dp 下：45px 数字 + `ms` 允许换行到下一行但不裁切；200% 字号时
  hero 高度自然增长，orb 仍居中。
- 横屏手机：图表 120；hero 仍完整显示（页面滚动，不压缩 hero）。
- 只有 `etUseRail`（600）与页面双栏阈值（900）两个切换点，不另造断点。

## 8. 无障碍

- Hero 的可访问顺序：badge（状态句）→ orb（被 `ExcludeSemantics` 跳过）→
  状态句 → 延迟数字（`Semantics(label: "Latency 23 milliseconds")`）→ 主操作。
- badge/状态句是唯一 live region 候选：阶段变化播报一次（不是每次轮询）。
- 主操作 label + hint（starts/stops the tunnel）；busy 只播报一次。
- Bento：每枚 tile 的语义是 “{label}: {value}”（数字带单位），图标
  `ExcludeSemantics`。
- 图表：`Semantics` 文本等价物（“Download … upload … over the last 60 seconds”）。
- 触摸目标 ≥48；copy IP、任何 icon button 都是 48×48 + tooltip。
- reduced motion：orb 静止、数字不 spring 跳、aurora 不动；状态文字/图标完整。
- 对比度：45px 数字（large text）≥3:1；状态句/按钮在 scrim 上满足 4.5:1；
  hero 合成层的自动断言待补（MASTER §17 V3）。

## 9. 本屏不做什么

没有配置字段、没有 peer 全表、没有日志查看器、没有“测速”、没有 onboarding
轮播、没有第二个 filled 按钮、没有 aurora 之外的渐变、没有卡片套卡片。
