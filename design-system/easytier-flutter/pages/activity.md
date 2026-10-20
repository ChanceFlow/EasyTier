# Activity — “发生了什么？什么时候？”

> `design-system/easytier-flutter` 的逐屏规格。它**收紧**
> [`../MASTER.md`](../MASTER.md)，不得引入新的颜色、字体、圆角、时长或图标风格。
> 与 MASTER 冲突时 MASTER 胜。
>
> 视觉方向是 **Google Material 3 + Expressive**（v5）：每条事件前是一个 40dp 的
> `EtIconBadge`（tonal squircle，tone 编码 kind），标题/可选 detail + 右对齐 mono
> `HH:mm`；过滤是 `MenuAnchor` 的复选菜单，清空是破坏性 `AlertDialog`。

| | |
|---|---|
| **问题** | 发生了什么？什么时候？ |
| **主操作** | 无（只读时间线）；“Clear activity” 是破坏性次操作 |
| **M3 / Expressive 组件** | small `AppBar`、`MenuAnchor` + `CheckboxMenuButton`、`EtIconBadge`、`EtSurface`、`ListTile`、`EtEmptyState`、`AlertDialog`、`SnackBar` |
| **目的地** | 4 / 5 |
| **数据来源** | `AppState.events`（`NetworkEvent`：`at`、`kind` ∈ connected / disconnected / peerJoined / peerLeft / warning / error / info、`title`、`detail`） |

## 1. 目的

一条事实性、可扫读的记录，用于排查：什么时候连上、哪个 peer 加入/离开、出现过
什么 warning/error、先后顺序如何。它不替代日志（原始日志在 Settings → Logs），
也**不假装拥有它没有的历史**。

**诚实规则：**

- 事件列表是**本次会话内**的（`AppState.events`，不持久化）。空状态说明这一点，
  界面不编造时间戳。
- “Clear” 只把**点击时已存在**的事件从本页隐藏（本地 identity set），
  `AppState.events` 不动，所以新的仍会出现、导航 badge 也不受影响；清空对话框
  必须如实说明“只影响本机时间线”。

## 2. 布局骨架（手机，上→下）

1. **Small top app bar**：标题 `Activity`（`headlineSmall` w600），副标题 = 计数
   摘要：`{filtered} events` / `{filtered} of {visible} events` / `No events yet`。
   actions：
   - 过滤 `MenuAnchor`：`EtIconButton(Symbols.filter_list)` 打开菜单，四个
     `CheckboxMenuButton`（All / Connection / Peers / Warnings），每项 trailing 是
     mono 计数；
   - 清空 `EtIconButton(Symbols.delete_outline)`，没有可见事件时 disabled。
2. **时间线**（`EtSurface`，radius 24，padding 0；≤12 条时 shrinkWrap 由内容撑高，
   长列表虚拟化）：
   - **日期分组头**：`Today` / `Yesterday` / `{Mon} {d}`（`labelLarge`、
     `onSurfaceVariant`、16 inset，下面一条 `Divider`）；不吸顶、不可聚焦。
   - **事件行**（`ListTile`，padding 水平 16）：
     - leading：`EtIconBadge` 40 + `ExcludeSemantics`，tone 按 kind：
       - `connected` → `success`（`Symbols.check_circle`）
       - `disconnected` → `danger`（`Symbols.link_off`）
       - `peerJoined` → `info`（`Symbols.person_add`）
       - `peerLeft` → `neutral`（`Symbols.person_remove`）
       - `warning` → `warn`（`Symbols.warning`）
       - `error` → `danger`（`Symbols.error`）
       - `info` → `accent`（`Symbols.info`）
     - title：`bodyMedium` w500；detail（可选）：`bodySmall`、`onSurfaceVariant`，
       最多 2 行省略；
     - trailing：**mono `HH:mm`**（caption、`onSurfaceVariant`），不是相对时间。
   - 最新在前；新事件插入顶部不做位移动画（reduced motion 下完全不闪）。
3. **空状态**：
   - 无事件 / 已清空：`EtEmptyState`（`Symbols.history` 或 `Symbols.monitor_heart`，
     “No activity yet / Activity cleared” + 一句解释）；
   - 过滤后为空：按过滤器给专门标题（No connection events / No peer events /
     No warnings）+ “Nothing in {n} events matches this filter.” +
     `EtPrimaryButton`（tonal，`Symbols.restart_alt`，“Show all”）。
4. **清空确认**：`AlertDialog`（“Clear activity?” + 只清本机的后果说明），
   `Cancel` 是 `TextButton`，确认是 filled **danger** “Clear”；成功后
   `SnackBar` “Activity cleared”。

**宽窗（≥840）**：同一时间线放在 1040 内容列里（卡片居中、可读宽度足够）；
过滤/清空在 app bar；无 bottom bar。

## 3. 过滤语义

| 过滤 | 命中 kind |
|---|---|
| All | 全部 |
| Connection | connected / disconnected / info |
| Peers | peerJoined / peerLeft |
| Warnings | warning / error |

过滤是**视图状态**，不改变数据；计数是“当前可见集合里该过滤的条数”，菜单项里
实时显示。

## 4. M3 / Expressive 组件清单

| 区域 | 组件 | role / token | 约束 |
|---|---|---|---|
| 页面 | small `AppBar` | `surface`，`headlineSmall` | 副标题给计数 |
| 过滤 | `MenuAnchor` + `CheckboxMenuButton` | M3 menu | 每项带 mono 计数 |
| 清空 | `IconButton` + `AlertDialog` | `error` 文字、默认焦点 Cancel | 破坏性确认写明范围 |
| 时间线 | `EtSurface`（radius 24） | `surfaceContainerLow` | 一张卡包整段；≤12 条 shrink |
| 事件行 | `ListTile` + `EtIconBadge` 40 | kind → EtTone | 图标 `ExcludeSemantics`，语义靠 title |
| 时间 | mono `HH:mm` | `onSurfaceVariant` | 不是相对时间；绝对时间不丢 |
| 空态 | `EtEmptyState` | — | 过滤空态带 “Show all” |

## 5. 连接阶段行为

| 阶段 | Activity 行为 |
|---|---|
| 已停止 | 显示本次会话的事件；不产生新行 |
| 连接中 | “Connecting…” 事件只出现一次；live tail |
| 已连接 | `connected` 事件 + peer 出现时 `peerJoined` |
| 降级 | `warning` 事件；与页面横幅无耦合 |
| 失败 | 带原因的 `error` 事件 |
| 空 | 空状态，不是空白列表 |

## 6. 状态

| 状态 | 时间线 | 控件 |
|---|---|---|
| Live、空 | 空状态 | 过滤可用；清空 disabled |
| Live、有数据 | 最新在前 | 过滤/清空可用 |
| 过滤后为空 | 过滤空态 + “Show all” | 过滤可用 |
| 已清空（本页） | “Activity cleared” 空态 | 新事件到达后恢复列表 |
| 读取失败 | inline danger 行 + “Retry” | — |
| reduced motion | 内容相同，无插入/展开动画 | — |

## 7. 文案（EN / zh）

| 语境 | EN | zh |
|---|---|---|
| 标题 | Activity | 动态 |
| 计数摘要 | {n} events / {filtered} of {visible} events / No events yet | {n} 条事件 / {filtered}/{visible} 条 / 暂无事件 |
| 过滤 | Filter activity | 过滤动态 |
| 过滤项 | All / Connection / Peers / Warnings | 全部 / 连接 / 节点 / 警告 |
| 过滤空态 | No {filter} events / Nothing in {n} events matches this filter. | 没有{filter}事件 / {n} 条事件中没有匹配项。 |
| 显示全部 | Show all | 显示全部 |
| 清空 | Clear activity | 清空动态 |
| 清空确认 | Clear activity? / This clears the local event timeline on this device only. The core keeps its own logs, and nothing on the network changes. | 清空动态？ / 仅清除本机的事件时间线。原始日志由 core 保留，网络不会发生任何变化。 |
| 已清空 | Activity cleared | 动态已清空 |
| 空状态 | No activity yet / Connect a network and the local timeline starts here. Events stay on this device. | 暂无动态 / 连接网络后本地时间线从这里开始。事件只保存在本机。 |
| 日期头 | Today / Yesterday / {Mon} {d} | 今天 / 昨天 / {月} {日} |
| 时间 | HH:mm（mono） | HH:mm（mono） |

行内不出现裸 ISO 时间戳；绝对时间就是 `HH:mm`（当天），跨天由日期头承担。

## 8. 响应式（M3 window size classes）

- compact（<600）：单列；时间线卡片；`HH:mm` 不换行；gutter 16。
- medium（600–839）：rail 导航；同布局。
- expanded（≥840）：1040 内容列；卡片居中；无 bottom bar。
- 200% 字号：行变高，标题/detail 换行，`HH:mm` 仍在右侧（列宽足够时）或落到
  下一行；不裁切。
- 横屏：同一布局；长 detail 换行不横向滚动。

## 9. 无障碍

- 时间线阅读顺序 = 视觉顺序（最新在前）；日期头不可聚焦。
- 行语义：“{kind}: {title}, HH:mm”，detail 作为补充；事件行不是按钮（不可展开）。
- 清空是破坏性操作：对话框写明范围与后果，焦点默认 Cancel，确认按钮说清动作。
- 过滤菜单项是复选项，`Semantics(checked:)`；计数朗读为 “{n} events”。
- 新增事件的播报要节流：只对 warning/error 做 live region（如将来加），
  info 事件不刷屏；清空后不播报旧事件。
- 对比度：事件颜色总伴随 title 文本；时间只用 `onSurfaceVariant`。
- reduced motion：无插入动画；菜单展开即时。

## 10. 本屏不做什么

没有原始日志（Settings → Logs）、没有搜索、没有分页 / “load more”（无持久化）、
没有自动滚动、没有把事件做成聊天气泡。清空只影响本机本页的可见性。
