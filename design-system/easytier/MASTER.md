# EasyTier 设计系统 v2 — MASTER

> 全局唯一事实来源。实现任何界面前先读这份；页面级例外写进 `pages/<name>.md`，有则覆盖本文件。
> 令牌的机器可读定义在 `tokens.css`，不要在本文件里抄 hex。
>
> 本文件的规则来自 ui-ux-pro-max 数据集（119 条 UX 指南 / 32 条 App 界面指南 / 17 条动效 /
> 25 条图表 / 105 条图标 / Vue 栈规则），**已全量采纳**。可静态检查的部分落在
> `lint-design.py`，对比度部分落在 `check-contrast.py`。

## 0. 这次是推翻重做

v1 的问题不是"不好看"，是**每块界面同时承担多个职责**：状态卡里嵌连接开关、配置页一次平铺 64 个字段、
IP 与延迟用比例字体导致列永远对不齐、输入框边界只有 1.6:1 在暗色下等于没有。

v2 的判据只有一条：**这个屏幕在回答哪一个问题？** 答不出来的元素就删掉或移走。

## 1. 四条原则

1. **一屏一个问题。** 首页=通不通；节点页=谁慢；设置页=怎么改。一个屏幕不承接两个问题。
2. **机器数据用机器字体。** IP / 端口 / 延迟 / 丢包 / 时长 / 版本 / ID 一律 `--et-font-data` + `--et-numeric`。
3. **状态三重编码。** 颜色 + 形状 + 文字，三者同时表达。灰度截图与色盲视角下必须仍可区分。
4. **配置分三层。** 基础 / 高级 / 专家，默认只展开基础。字段一个不删，只是不同时出现。

## 2. 令牌

全部定义见 `tokens.css`。**组件里禁止出现 hex、rgb()、裸 px 数值**，只能引用 `--et-*`。

**字体用内嵌族，不要引 Google Fonts。** `--et-font-ui` = `ET Sans`（MiSans 子集）、
`--et-font-data` = `ET Mono`（JetBrains Mono 子集），随包内嵌在
`frontend-lib/src/assets/fonts/`，按 unicode-range 切成 latin / CJK 两片，授权文件同目录。
原因：Android 端必须离线可用；联网取字体会闪字、失败掉系统字，还多一个第三方运行时依赖。
只内嵌 400/500/600 三档，配合 `font-synthesis: none`，700 级文本解析到 600——不要写 700。

- 表面 4 级：`--et-surface-sunken/1/2/3`，靠明度分层，不靠阴影。
- 文本 4 级：`--et-text/-2/-3/-disabled`。
- 语义 5 组：`accent`(活着/主操作) `info`(同步) `warn`(降级) `danger`(断开/破坏性) `neutral`(未知)，每组含 `-quiet` 底色与 `on-*` 前景。
- **控件边界必须用 `--et-control-border`（≥3:1）**，不要用 `--et-border`（装饰性，无对比度保证）。
- 密度：`<html data-density="comfort|compact">`，手机 comfort / 控制台 compact，同一套令牌两档。
- z-index 只用 `--et-z-*` 语义层，禁止裸数字。
- 安全区：固定头尾栏必须用 `--et-safe-top/bottom`；滚动锚点靠 `html { scroll-padding-* }`。

## 3. 平台差异（别把三个数字混成一个）

| 平台 | 触达下限 | 令牌 |
|---|---|---|
| iOS | 44pt | `--et-touch-min` |
| Android | 48dp | `--et-touch` |
| Web (WCAG 2.5.8) | 24 CSS px（有间距/行内例外） | `--et-touch-web` |

相邻触达目标间距 ≥ `--et-touch-gap`。**44pt / 48dp / 24px 是三套独立标准，不可互相替代。**
手机正文下限 16px（`--et-font-body`）——低于此 iOS 会强制缩放、Android 可读性差。

## 4. 组件契约

| 组件 | 规则 |
|---|---|
| **状态信号 Signal** | 五态：已连接(圆·accent) 连接中(方·info·呼吸) 降级(三角·warn) 已断开(横条·danger) 未启动(空环·neutral)。必须带文字，不得只给图标。呼吸动画仅"连接中"用，reduced-motion 下停。 |
| **主操作按钮** | 一屏至多一个。整宽 ≥48px（`--et-touch`）。按下用 `transform: scale(.985)`，不得位移推开周围内容。**异步时必须 disable + 显示 loading**，不得允许重复点击。 |
| **节点行 PeerRow** | 4 列：状态点 / 虚拟 IP / 路径(直连·中继 via X·丢失) / 延迟右对齐等宽。行高 `--et-row-h`。**离线节点不隐藏**，显示为 neutral + "离线 Nh"。列表 >50 项必须虚拟化。 |
| **输入框** | `--et-control-border` 描边；聚焦 `--et-focus` 2px 外环；错误态红边 + **说明具体哪一段错了**（"最后一段 999 超出 0–255"，不是"格式错误"）。禁止只用 placeholder 当标签。 |
| **表单错误** | 字段级错误紧贴输入框并用 `aria-describedby` 关联；多错时在表单顶部放**可聚焦的错误摘要**（`role="alert"`），提交失败后把焦点移到摘要，且保留字段级错误。 |
| **配置分层 Tier** | 三个 pill 切换，各带字段计数。切换不跳页、不重载，只显隐。 |
| **KPI 卡** | 数值用 `--et-font-display` 等宽；下方一行趋势用 micro 号 + 语义色。 |
| **表格** | 表头 micro 号 `--et-text-3`；数值列右对齐等宽；行 hover 提亮到 `--et-surface-2`。窄屏换卡片布局，不横向溢出。 |
| **图表** | 实时数据用流式面积图；**必须同时显示当前值与状态文字**，并用线型/标记区分序列——不能只靠颜色。提供暂停/继续（`Auto-Rotating Content Controls`）。 |
| **徽标 Badge** | 静态值与可交互 pill 用不同元素（`span` vs `button`）。数字徽标只留**一个** live region，播报完整语义（"3 个节点离线"），不播报裸数字。 |
| **图标** | 一律 Phosphor（Vue 用 `@phosphor-icons/vue`），Outline 风格，同层不混填充/线性。装饰性图标 `aria-hidden`；纯图标控件必须有 `aria-label`。**禁止 emoji 当图标。** |

## 5. 动效

- 一屏最多动 1–2 个关键元素；其余静止。
- 悬停位移 **< 2px**，只动 `transform` / `opacity`，绝不动 `width/height/margin`。
- 时长：悬停 150–200ms；进出场 `--et-dur-base`；**退出快于进入**。
- 缓动：悬停 `--et-ease-hover`（≈power1.out）。
- **状态正确性不得依赖 `animationend` / `transitionend`**：取消时直接把最终语义状态写死，并做清理。
- `prefers-reduced-motion` 下所有时长归零、平滑滚动关闭（已在 `tokens.css` 兜底）。

## 6. 信息架构

```
移动端
  状态   ← 唯一主数字（延迟）+ 唯一主操作（连接/断开）+ 流量 + 节点摘要
  节点   ← 完整节点表，可竖扫，按延迟排序
  设置   ← 配置三层 + 导入导出 + 语言 + 关于

桌面 / Web 控制台
  左固定导航（总览/节点/配置/日志）＋ 顶部 KPI 行 ＋ 数据表，data-density="compact"
```

导航：返回必须可预期且保留屏幕状态；模态必须有明确关闭按钮 + 下滑手势（不满足于只有手势）；
底部标签 3–5 个；**核心操作不得只靠手势**，必须同时有可见按钮。

## 7. 文本与内容

- 行高用无单位值（`--et-leading-*`）。
- 长 token（IPv6 / base64 密钥 / URL）用 `.et-token`（`overflow-wrap: anywhere`），**禁止 `word-break: break-all`**。
- 截断只允许用于**不可预测的值**，且必须保留看到全文的路径（展开、详情页、`title`）。
  **禁止把关键信息裁掉只为让卡片等高。**
- 窄容器里的标签用 `.et-nowrap`（`nowrap` + 可收缩标签），不得换行到第二行，不得用 hover-only tooltip 藏全文。
- 数字与日期用 `--et-font-data` + `--et-numeric`；时间一律带时区或相对描述（"3 分钟前"）。
- 空状态必须给出**下一步动作**，不能只是一句"暂无数据"。

## 8. 反馈

- 任何 >300ms 的网络操作都要有可见反馈（骨架屏或 loading）；按钮进入 loading 后 disable。
- 失败必须就近说明原因并提供恢复路径，不允许静默失败。
- 破坏性/不可逆操作必须二次确认。
- 本地网络状态变化要能被读屏播报，但同一时刻只保留一个 live region。

## 9. 落地映射

| 文件 | 改什么 |
|---|---|
| `easytier-web/frontend-lib/src/theme.ts` | Vuetify 主题色映射到 `--et-*` 等价色；密度分档 |
| `easytier-web/frontend-lib/src/style.css` | 引入 tokens；清理 27 处 `!important` |
| `easytier-gui/src/styles.css` | 同上；裸 `z-index:100` 换 `--et-z-*` |
| `frontend-lib/components/Status.vue` (1476) | 拆掉内嵌开关 → 纯状态；`:key="i"` 换稳定 id；sheet-grabber 加 role |
| `frontend-lib/components/Config.vue` (1359) | 配置三层；端口转发 `:key="index"` 换稳定 id；`z-index:10` 语义化 |
| `frontend-lib/components/RemoteManagement.vue` (1278) | 节点表按 PeerRow 契约重排；4 处可点 div → button |
| `frontend-lib/components/NetworkChart.vue` (531) | 色板读令牌；加暂停；补当前值与状态文字 |
| `frontend-lib/components/UrlListInput.vue` / `acl/AclChainEditor.vue` | `:key="index"` 换稳定 id；可点 div → button |
| `easytier-gui/pages/index.vue` (1104) | 首页 = 一主数字 + 一主操作 + 摘要；5 处可点 div → button |
| `easytier-gui/components/MeshHero.vue` (841) | 改造成 Signal + Orb |
| `easytier-gui/components/OnboardingDialog.vue` | 去掉 ⚙ emoji，换 Phosphor `Gear` |

## 10. 反模式（`lint-design.py` 会拦）

- 用 emoji 当结构性图标。
- 状态只用颜色表达。
- 输入框用装饰性边框（`--et-border`）。
- 一屏两个整宽主按钮。
- 离线节点从列表消失。
- 数值用比例字体或非 tabular-nums。
- 用位移/尺寸变化做按下反馈。
- 组件里写死颜色；裸 z-index 数字。
- `word-break: break-all`；固定高度 + 裁切文字。
- 非交互元素（div/span）绑 `@click` 而无 `role`/`tabindex`。
- `v-for` 缺 `:key`；用下标当 key。
- `outline: none` 无替代；禁止缩放（`user-scalable=no`）。

## 11. 令牌的分发与迁移

**单一来源**：`design-system/easytier/tokens.css`。它会被同步成
`easytier-web/frontend-lib/src/tokens.css`（带「自动生成请勿手改」banner）：

```bash
python3 design-system/easytier/sync-tokens.py           # 写入副本
python3 design-system/easytier/sync-tokens.py --check   # CI 校验漂移
```

副本在 `easytier-frontend-lib.ts` 里 **import 在 `./style.css` 之后**——这一点不能改：
v1 的令牌也在 `:root` / `.v-theme--m3Light` 里定义，同优先级只能靠源码顺序决胜。

**迁移桥**：tokens.css 在两个主题块内提供了 v1 名字的兼容别名
（`--et-surface` → `--et-surface-1`、`--et-text-secondary` → `--et-text-2`、
`--font-sans` → `--et-font-ui` 等）。所以 v1 代码不改编也能立刻吃到 v2 的值。
别名必须写在**主题块内**而不是 `:root`：v1 的 `.v-theme--m3Light` 优先级更高，放 `:root` 会被压过去。

迁移策略：**每改完一个组件，就删掉它用到的那几行别名**。别名清空 = 迁移完成。
不要在别名还在时又加新的 v1 名字用法。

## 12. 自动化门禁

```bash
python3 design-system/easytier/sync-tokens.py --check   # 令牌副本未漂移
python3 design-system/easytier/check-contrast.py        # 60 项对比度断言
python3 design-system/easytier/lint-design.py           # 静态规则，Critical/High 非零
```

三个脚本零依赖、纯标准库，可直接进 CI。

**当前基线（迁移开始时）**：对比度 60/60 通过；lint 79 处命中 / **14 处阻断**
（12 个可点 div + 2 个 emoji 图标）。这 14 处由 v2 迁移的第一批模块负责清零，
清完后 `.github/workflows/design-gate.yml` 才转为硬门禁。

## 13. 验证清单（合并前逐条过）

- [ ] `check-contrast.py` 全绿
- [ ] `lint-design.py` 无 Critical/High
- [ ] 明暗两套主题都实际打开看过，不是从一套推断
- [ ] 375px / 平板 / 横屏各过一遍；触达 ≥48dp（Android）/ ≥44pt（iOS）/ ≥24px（Web）
- [ ] 键盘走一遍：焦点可见、顺序与视觉一致、浮层不遮焦点、错误摘要可聚焦
- [ ] 读屏走一遍：图标按钮有名字、状态变化有播报、图表有文字等价物
- [ ] reduced-motion 下无动画残留
- [ ] 灰度截图下状态仍可区分
- [ ] 系统字号放到最大不崩版（Dynamic Type）
- [ ] 长 IPv6 / base64 密钥不撑破容器
- [ ] 无 emoji 图标；无硬编码颜色
