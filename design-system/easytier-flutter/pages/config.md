# Config — “这个网络被配置成什么？我能安全地改吗？”

> `design-system/easytier-flutter` 的逐屏规格。它**收紧**
> [`../MASTER.md`](../MASTER.md)，不得引入新的颜色、字体、圆角、时长或图标风格。
> 与 MASTER 冲突时 MASTER 胜。
>
> 视觉方向是 **Google Material 3 + Expressive**（v5）：顶部实例卡横条 → 四个带
> icon badge 的披露 section → 底部一个 filled `Save` 的 action bar。字段仍是
> outlined `TextFormField` / `SwitchListTile` / `SegmentedButton`，预览与确认仍是
> sheet / `AlertDialog`。

| | |
|---|---|
| **问题** | 这个网络被配置成什么？我能安全地改吗？ |
| **主操作** | 底部 action bar 唯一的 filled **`Save`**（只在 dirty 且 valid 时可用） |
| **次操作** | **`Run with these settings`**（`TextButton`，安静）/ `Reset` / `Discard` |
| **M3 / Expressive 组件** | small `AppBar`、实例卡（`EtSurface` + `EtAvatar` + `EtBadge`）、`EtSection` + `EtIconBadge` leading、outlined `TextFormField`、`SwitchListTile`、`SegmentedButton`、`Badge.count`、底部 `Material(elevation 3)` action bar、`AlertDialog`、`SnackBar` |
| **目的地** | 3 / 5 |
| **数据来源** | `NetworkConfig`（四个 section）、`AppState.validateConfig`、`AppState.saveConfig`、`NetworkConfig.debugToml()` |

## 1. 目的

配置是自建网络用户的一等目的地，不是 1% 的“高级界面”。页面只有一个工作：显示
网络将如何运行、让用户修改、并让“我的修改生效了吗”没有歧义。

两条结构规则撑起整页：

1. **恰好一层披露、四个 section。** Basic（默认展开）、Advanced、Port forward、
   ACL。字段不为“简化”而删除；禁止第二层手风琴。
2. **没有预设、没有“推荐值”。** 预设等于替用户断言什么是对的，App 没有这个权威。

v5 加的只有表达层：实例卡横条、section 头的 tonal icon badge、更明确的底部
action bar；结构与字段一个没变。

## 2. 布局骨架（手机，上→下）

1. **Small top app bar**：标题 `Config`（`headlineSmall` w600），副标题 = 网络名。
   actions：`Symbols.code`（Preview TOML）、`Symbols.add`（Add network），
   48×48 `IconButton` + tooltip。
2. **横幅区**（`ConfigStack`，gap 8，条件渲染）：
   - 保存失败 → `EtBanner` danger（`Symbols.error`，“Could not save” + 原因 +
     `IconButton` Dismiss）；
   - 校验失败 → `EtBanner` danger，标题 `{n} fields need attention`，
     包在 `Semantics(container, liveRegion, label)` + `Focus` 里（可聚焦错误摘要）；
   - 未保存 → `EtBanner` warn（`Symbols.edit`，“Unsaved changes” +
     `TextButton` “Reset”）。
3. **实例卡横条**（`ConfigInstanceCards`）：
   - 单实例：左对齐、最大宽 480 的一张卡；
   - 多实例：横向列表（高 92，卡宽 280），`InkWell` 切换编辑目标；
   - 卡片：`EtSurface`（radius 24），选中 = `primary` 10–18% tint + 32% 描边；
     `EtAvatar(instanceName, 44)` + `titleMedium` w600 + `Wrap`：
     `EtBadge(networkName, accent, lan icon)` + `Active`（success）或
     `source`（neutral）；可切换时右侧 `chevron_right`。
4. **四个 `EtSection`**（`Card` + `ExpansionTile`，radius 24，leading =
   `EtIconBadge` 40）：
   - **Basic**（默认展开，`Symbols.devices`，**accent**）：identity / network /
     地址；DHCP 关闭时 inline 出现 Virtual IPv4 + prefix；peer/listener URL 列表
     编辑器（mono + 删除 `IconButton`）。
   - **Advanced**（折叠，`Symbols.tune`，**tertiary**）：datapath / routing /
     privacy，全是 `SwitchListTile` 或带 label 的 `TextFormField`；分组用 caption
     小标题，不是第二层折叠。
   - **Port forward**（折叠，`Symbols.alt_route`，**info**）：proxy CIDR + 规则行
     （proto `SegmentedButton`、local/remote mono、删除）；“Add port forward”
     用 outlined/text，不用 filled。
   - **ACL**（折叠，`Symbols.shield`，**success**）：有序规则（action
     allow/deny `EtBadge`、chain、CIDR、ports、comment）；规则顺序有意义。
   - **错误计数**：某个 section 有字段错误时，`Badge.count` 骑在 icon badge 上，
     tooltip “{n} fields need attention”；错误不能藏在折叠区里。
5. **底部 action bar**（`Material`，elevation 3，`surfaceContainer`，SafeArea；
   作为滚动区**兄弟节点**，永不复盖字段）：
   - 状态行：图标 + 文本——`Applying settings…`（`progress_activity` primary）/
     `Saving…`（`progress_activity`）/ `Draft not saved`（`edit`
     onSurfaceVariant）/ `All changes saved`（`check_circle` success）；
   - helper（窄窗一行/宽窗第二行）：“Save stores the draft. Run restarts the
     running tunnel with it.”（未连接时 “Run starts the network with it.”）；
   - 右侧：`TextButton` “Run with these settings” + **filled `Save`**（48 高，
     loading = saving；宽窗固定 220 宽，窄窗弹性；见 MASTER §17 D5）。
6. **Sheet / Dialog**：TOML 预览（`showEtSheet`，mono、`surfaceContainerLowest`、
   copy、secret 永远 `***`）；Port forward / ACL 规则编辑 sheet；
   “Discard unsaved changes?” `AlertDialog`。

**宽窗（≥840，`etDesktop`）**：表单列 ≤720（`ConfigTwoColumn` 在 ≥1280 时加右侧
实时 TOML 预览列）；action bar 横排（状态/helper + Run + Save）；无 bottom bar。

## 3. 披露与保存规则

- 一级披露；`ExpansionTile` header 整行 ≥48：title `titleMedium` w600 + subtitle
  `bodySmall` + trailing `expand_more/less`；`EtSection` 的 radius 是 24。
- 折叠区仍参与校验；保存失败时自动展开第一个出错 section 并滚动到它。
- **保存是显式动作**：修改只进草稿；Save 写草稿，Run 用草稿启动/重启。两者
  的差别必须写在 helper 里，不能靠猜。
- dirty 时离开（切 tab/返回/切实例）弹确认；绝不静默丢弃。
- 折叠展开/收起用 `EtDuration.slow`（state intent）；reduced motion 即时切换。

## 4. M3 / Expressive 组件清单

| 区域 | 组件 | role / token | 约束 |
|---|---|---|---|
| 页面 | small `AppBar` | `surface`，`headlineSmall` | actions ≤2 |
| 实例卡 | `EtSurface` + `EtAvatar` + `EtBadge` | primary tint + 32% 描边（选中） | 单卡/横条两种形态 |
| section | `Card` + `ExpansionTile` | `surfaceContainerLow`、radius 24 | leading icon badge；不嵌套 |
| section 头 | `EtIconBadge` + `Badge.count` | accent/tertiary/info/success | 错误计数 tooltip |
| 字段 | `TextFormField`（outlined） | `outline` 边界、focus `primary` 2dp、radius 4 | label 永远可见；error 绑定 |
| 开关 | `SwitchListTile` | 主题默认 | 行高 ≥48 |
| 单选 | `SegmentedButton` | M3 默认 | 不自绘分段 |
| 列表编辑器 | `ListTile` + `IconButton` | mono 值 | 删除 48×48 + label |
| 主操作 | `FilledButton` | `primary`/`onPrimary` | action bar 内唯一 filled |
| 次操作 | `TextButton` | M3 默认 | Run / Reset / Discard |
| action bar | `Material(elevation 3)` | `surfaceContainer` | 滚动区兄弟节点 |
| 确认 | `AlertDialog` | M3 默认 | 焦点默认 Cancel |
| 反馈 | `SnackBar`（floating） | `inverseSurface` | 一次一个 |

## 5. 连接阶段行为

| 阶段 | 配置页行为 |
|---|---|
| 已停止 | 完全可编辑；Save 写配置；Run 启动网络 |
| 连接中 | 字段可编辑；Save/Run 禁用并提示等连接结束 |
| 已连接 | 可编辑；Save 允许（提示 Run 会重启隧道）；Run 重启 |
| 降级 | 同已连接；warn 徽章 + helper |
| 失败 | 可编辑；Save 允许（修配置就是恢复路径）；错误横幅可打开日志 |
| 无网络 | 空状态，“Create network” 是唯一 primary |

## 6. 状态

| 状态 | action bar | 行为 |
|---|---|---|
| Loading | 隐藏 / 状态行“Loading…” | 加载完成前不出现可编辑控件 |
| 无实例 | 不渲染 | `EtEmptyState`：“No network configured” + filled “Create network” |
| Clean | “All changes saved” + check | Save disabled；Run 可用 |
| Dirty | “Draft not saved” + edit | Save 启用（无校验错误时）；Reset 回滚 |
| Validating | “Saving…”/spinner | 过期校验结果不得启用按钮 |
| Invalid | “Draft not saved” + 错误摘要横幅 | 展开第一个出错 section；Save 禁用 |
| Saving | “Saving…” + spinner | 输入锁定；禁止重复提交；Run disabled |
| Saved | “All changes saved” | snackbar “Configuration saved.”；dirty 清除 |
| Save error | “Draft not saved” + danger 横幅 | 草稿保留；可 Dismiss/重试 |
| Deleted | 空状态 | snackbar “Network deleted”（不可恢复则不给 Undo） |

## 7. 文案（EN / zh）

| 语境 | EN | zh |
|---|---|---|
| 标题 / section | Config · Basic · Advanced · Port forward · ACL | 配置 · 基础 · 高级 · 端口转发 · ACL |
| 主/次操作 | Save · Run with these settings · Reset · Discard | 保存 · 用这些设置运行 · 重置 · 放弃 |
| 保存状态 | All changes saved / Draft not saved / Saving… / Applying settings… | 所有更改已保存 / 草稿未保存 / 正在保存… / 正在应用设置… |
| 保存说明 | Save stores the draft. Run restarts the running tunnel with it. | 保存写入草稿；运行会用草稿重启隧道。 |
| 未保存横幅 | Unsaved changes / The draft differs from the saved configuration. | 有未保存的更改 / 草稿与已保存配置不同。 |
| 校验摘要 | {n} fields need attention | {n} 个字段需要处理 |
| section 错误 tooltip | {n} fields need attention | {n} 个字段需要处理 |
| 实例卡 | Active / {source} | 当前 / {source} |
| 预览 | Preview TOML · Effective configuration | 预览 TOML · 生效配置 |
| 删除确认 | Delete this network? | 删除这个网络？ |
| 删除后果 | The tunnel will stop and this configuration will be removed from this device. | 隧道将停止，此配置将从本设备移除。 |
| 未保存确认 | Discard unsaved changes? | 放弃未保存的更改？ |
| 字段错误 | Last octet 999 is outside 0–255. | 最后一段 999 超出 0–255。 |
| 地址错误 | “{value}” is not a valid IPv4 address. | “{value}” 不是有效的 IPv4 地址。 |

字段级错误点名具体片段或值，绝不只写 “Invalid input”。

## 8. 响应式（M3 window size classes）

- compact（<600）：单列；实例卡横条可横向滚动（只在横条内部）；action bar 贴底、
  避开 safe area；长 URL/IPv6 换行不裁切；数字字段 `TextInputType.number` + mono。
- medium（600–839）：rail 导航；表单宽 ≤720。
- expanded（≥840）：rail + 表单列 720；≥1280 右侧实时 TOML 预览。
- 横屏手机：仍单列；键盘不能遮住聚焦字段（`resizeToAvoidBottomInset` + 滚动）。
- 200% 字号：Save 宽度改为弹性（避免 220 固定宽，MASTER §17 D5）。

## 9. 无障碍

- 每个输入有可见 label（绝不 placeholder-only），helper/error 通过
  `InputDecoration` 语义关联。
- 开关行整行是 hit area（≥48），`Semantics(toggled:, label:)`。
- 保存失败：焦点移到错误摘要 + 一次 `liveRegion` 播报；摘要项是按钮，点击聚焦
  对应字段；折叠 section 的错误徽章进入 header 可访问名。
- 键盘：披露 header 可 Enter/Space 展开；删除按钮有 label；ACL 拖拽排序必须有
  键盘/按钮替代路径。
- 破坏性操作：对话框写明对象与后果，焦点默认 Cancel，确认按钮说清动作。
- 200% 字号：label 换行、action bar 增高、错误文字不被裁切。
- reduced motion：展开/折叠即时，不做 chevron 补间；action bar 状态切换不跳。
- 实例卡横条：每张卡语义为“编辑 {instanceName}”，选中项 `Semantics(selected:)`。

## 10. 本屏不做什么

没有第二层披露、没有“推荐预设”、没有删字段、没有把 Save 做成浮动 FAB、
没有自绘分段控件/下拉控件（M3 组件可用）、action bar 不覆盖内容。
