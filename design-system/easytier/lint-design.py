#!/usr/bin/env python3
"""把 UX 指南里可静态检查的规则变成 CI 断言。

扫描 easytier-gui 与 frontend-lib 的手写源码（跳过 generated/ 与 .d.ts），
按规则报告违规。退出码非零表示存在 Critical/High 违规。

    python3 design-system/easytier/lint-design.py            # 全量报告
    python3 design-system/easytier/lint-design.py --quiet    # 只打印汇总
    python3 design-system/easytier/lint-design.py --rule emoji-icon
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TARGETS = [
    ROOT / "easytier-gui" / "src",
    ROOT / "easytier-web" / "frontend-lib" / "src",
]
SKIP_PARTS = {"generated", "node_modules", "dist", "__pycache__"}
SKIP_SUFFIX = (".d.ts",)
# 令牌文件里允许 !important：全局 reduced-motion 兜底必须用通用选择器 + !important
# 才压得住组件里写死的字面量时长（见 tokens.css 的注释）。
SKIP_NAMES = {"tokens.css", "theme.ts"}

# emoji 与杂项符号：用作结构性图标即违规（字体依赖、无法用令牌控制）
# 只认 pictographic emoji 与杂项符号。箭头（U+2190-21FF）**不算**：
# 端口转发的 "a → b"、流量方向的 "↑1.2MB/s" 是技术排版，不是装饰图标。
EMOJI = re.compile(
    "[\U0001F300-\U0001FAFF\U00002600-\U000027BF\U0001F000-\U0001F2FF\uFE0F]"
)

Rule = tuple[str, str, str, str]  # (id, severity, pattern, message)

RULES: list[Rule] = [
    ("emoji-icon", "High", EMOJI.pattern,
     "用 emoji 当图标 —— 改用 Phosphor（@phosphor-icons/vue），它才能跟主题令牌走"),
    ("word-break-all", "High", r"word-break\s*:\s*break-all",
     "word-break:break-all 会切断正常单词 —— 长 token 用 overflow-wrap:anywhere（.et-token）"),
    ("outline-none", "High", r"outline\s*:\s*(none|0)\b(?!.*focus-visible)",
     "移除了焦点轮廓且无替代 —— 键盘用户会失去位置感（WCAG 2.4.7）"),
    ("viewport-zoom-block", "High", r"user-scalable\s*=\s*no|maximum-scale\s*=\s*1",
     "禁止缩放 —— 低视力用户无法放大，WCAG 1.4.4 失败"),
    ("zindex-literal", "Medium", r"z-index\s*:\s*\d{2,}",
     "裸 z-index 数字 —— 用 --et-z-* 语义层，否则叠放顺序迟早失控"),
    ("vfor-no-key", "High", r"v-for=(?![^>]*:key)",
     "v-for 没有 :key —— 列表更新会错位复用 DOM"),
    ("key-index", "Medium", r":key=\"\s*(index|i|idx)\s*\"",
     "用数组下标当 key —— 动态列表增删时会渲染错内容"),
    ("click-on-div", "High", r"<(div|span|li|section)[^>]*@click(?![^>]*(role=|tabindex))",
     "非交互元素上绑 @click 且无 role/tabindex —— 键盘与读屏都到不了，改用 button"),
    ("transition-all", "Low", r"transition\s*:\s*all\b",
     "transition:all 会监听所有属性 —— 明确列出 transform/opacity，避免布局抖动"),
    ("important", "Low", r"!\s*important",
     "!important —— 说明选择器优先级失控，优先修层级关系"),
    # 见 scan_blocks()：需要"固定高度 + overflow hidden + 裁切文字的证据"三者同时成立

    ("placeholder-only-label", "Medium", r"<input[^>]*placeholder=(?![^>]*(aria-label|id=))",
     "只用 placeholder 当标签 —— 输入后标签消失，且读屏读不到，需配可见 label"),
    # ET Mono 只内嵌 latin 切片。.mono 里出现中文会掉进无 CJK 的 monospace
    # 回退链而整段不可见（实测踩过：hero 的 "2 个节点在线" 只剩 "2"）。
    # 只认"中文落在 .mono 元素自身的文本节点里"。若中文在元素外、只在同一行，
    # 那是正确写法（如 <span class="mono">{{n}}</span> 个节点），不能误报。
    # 已知盲区：文本来自计算属性时静态查不到，靠 tokens.css 的 CJK 回退兜底。
    ("mono-with-cjk", "High",
     r'class="[^"]*\bmono\b[^"]*"[^>]*>(?:(?!</?\w)[\s\S]){0,120}?[\u4e00-\u9fff]',
     "等宽元素里混了中文 —— ET Mono 无 CJK 切片会让中文不可见；只给数字/ID 加 .mono，中文留在 UI 字体"),
    # 迁移进度指标：组件里写死的颜色应当逐个换成 --et-*。不阻断，用来看趋势。
    ("hardcoded-hex", "Low", r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b",
     "组件里写死颜色 —— 换成 --et-* 语义令牌（theme.ts 是唯一例外，它必须给 Vuetify 字面量）"),
]

CATEGORY_OF = {
    "emoji-icon": "图标", "word-break-all": "文本重排", "outline-none": "焦点可见",
    "viewport-zoom-block": "缩放", "zindex-literal": "层级", "vfor-no-key": "列表",
    "key-index": "列表", "click-on-div": "控件语义", "transition-all": "动效",
    "important": "样式卫生", "fixed-text-height": "文本重排",
    "hardcoded-hex": "令牌化进度", "mono-with-cjk": "字体回退",
    "font-stack-cjk": "字体回退", "vuetify-font-override": "字体回退",
    "placeholder-only-label": "表单",
}


BLOCK_RE = re.compile(r"([^{}]+)\{([^{}]*)\}", re.DOTALL)


def scan_blocks(path: Path, text: str, raw: str) -> list[tuple[str, str, int, str, str]]:
    """块级规则：固定高度 + overflow:hidden + 确实在裁文字（有 text-overflow /
    line-clamp / nowrap）。只看单行会误伤进度条和图表容器。"""
    hits = []
    for m in BLOCK_RE.finditer(text):
        body = m.group(2)
        if not re.search(r"(?<!min-)(?<!max-)height\s*:\s*\d+px", body):
            continue
        if not re.search(r"overflow\s*:\s*hidden", body):
            continue
        if not re.search(r"text-overflow|-webkit-line-clamp|white-space\s*:\s*nowrap", body):
            continue
        sel = " ".join(m.group(1).split())[-60:]
        line = text.count("\n", 0, m.start()) + 1
        hits.append(("fixed-text-height", "Medium", line, sel,
                     "固定高度 + overflow:hidden + 文字裁切（WCAG 1.4.12 文本重排）"
                     "—— 改用 min-height 或内容驱动高度"))
    return hits


def check_font_invariants() -> list[tuple[str, str, int, str, str]]:
    """字体相关的两条不变式（都是实测踩过的坑）。

    这是防这一类回归的不变式：ET Mono 无 CJK 切片，栈里若不接 CJK，
    任何混排中文都会掉到 generic monospace 而不可见。
    """
    css = (ROOT / "design-system" / "easytier" / "tokens.css").read_text(encoding="utf-8")
    m = re.search(r"--et-font-data:(.*?);", css, re.DOTALL)
    if not m:
        return [("font-stack-cjk", "High", 1, "--et-font-data", "tokens.css 里找不到 --et-font-data")]
    stack = m.group(1)
    cjk = ("PingFang SC", "Hiragino Sans GB", "Noto Sans SC", "Microsoft YaHei",
           "Noto Sans CJK", "Source Han Sans")
    hits = []
    if not any(f in stack for f in cjk):
        line = css[:m.start()].count("\n") + 1
        hits.append(("font-stack-cjk", "High", line, "--et-font-data",
                     "等宽字体栈里没有 CJK 回退 —— 中英混排时中文会不可见，"
                     "请补 PingFang SC / Noto Sans SC / Microsoft YaHei 之一"))

    # Vuetify 把 font-family: Roboto 硬编码进 80 个排版工具类，且没有可覆盖的
    # CSS 变量。不覆写的话，凡是用 .text-* 的地方中文都会掉进系统字体。
    style_path = ROOT / "easytier-web" / "frontend-lib" / "src" / "style.css"
    # 必须剥注释：文档里就写着 [class*="text-"] 这个反面例子，
    # 不剥的话规则会匹配到自己的说明文字。
    style = strip_comments(style_path.read_text(encoding="utf-8"))
    if not re.search(r":root\s+:is\([^)]*\.text-caption", style, re.DOTALL):
        hits.append(("vuetify-font-override", "High", 1, "style.css",
                     "缺少对 Vuetify 排版工具类的字体覆写 —— .text-* 会退回 Roboto，"
                     "中文在无 CJK 环境显示豆腐块、有 CJK 的机器上中英混排两套字形"))
    # 通配会把自家的 .text-mono 也罩进去，等宽数字会变成 UI 字体
    if re.search(r'\[class\*?\^?=\s*["\']text-', style):
        hits.append(("vuetify-font-override", "High", 1, "style.css",
                     "字体覆写用了 [class*=text-] 通配 —— 会误伤 .text-mono，"
                     "请逐个列出 Vuetify 的排版类"))
    return hits


def sources() -> list[Path]:
    out: list[Path] = []
    for base in TARGETS:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file() or p.suffix not in (".vue", ".ts", ".css", ".html"):
                continue
            if p.name.endswith(SKIP_SUFFIX) or p.name in SKIP_NAMES:
                continue
            if SKIP_PARTS & set(p.parts):
                continue
            out.append(p)
    return sorted(out)


def strip_comments(text: str) -> str:
    """保留行号：把注释内容替换成等长空白。"""
    def blank(m: re.Match[str]) -> str:
        return re.sub(r"[^\n]", " ", m.group(0))
    text = re.sub(r"/\*.*?\*/", blank, text, flags=re.DOTALL)
    text = re.sub(r"<!--.*?-->", blank, text, flags=re.DOTALL)
    # // 行注释（lookbehind 排除 http:// 这类）
    text = re.sub(r"(?<!:)//[^\n]*", lambda m: " " * len(m.group(0)), text)
    return text


def scan(path: Path, only: str | None) -> list[tuple[str, str, int, str, str]]:
    raw = path.read_text(encoding="utf-8", errors="replace")
    text = strip_comments(raw)
    hits: list[tuple[str, str, int, str, str]] = []
    for rid, sev, pat, msg in RULES:
        if only and rid != only:
            continue
        for m in re.finditer(pat, text):
            line = text.count("\n", 0, m.start()) + 1
            snippet = raw.splitlines()[line - 1].strip()[:96]
            hits.append((rid, sev, line, snippet, msg))
    if not only or only == "fixed-text-height":
        hits.extend(scan_blocks(path, text, raw))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--rule")
    args = ap.parse_args()

    files = sources()
    findings: dict[str, list[tuple[Path, int, str, str]]] = defaultdict(list)
    sev_of = {rid: sev for rid, sev, _, _ in RULES}
    # 不变式规则不在 RULES 里（没有正则 pattern），单独登记严重度
    sev_of.setdefault("font-stack-cjk", "High")
    sev_of.setdefault("vuetify-font-override", "High")
    msg_of = {rid: msg for rid, _, _, msg in RULES}

    for f in files:
        for rid, _sev, line, snippet, _msg in scan(f, args.rule):
            findings[rid].append((f, line, snippet, ""))

    for rid, sev, line, snip, msg in check_font_invariants():
        findings[rid].append((ROOT / "design-system/easytier/tokens.css", line, snip, msg))

    total = sum(len(v) for v in findings.values())
    blocking = sum(len(v) for k, v in findings.items() if sev_of[k] in ("Critical", "High"))

    print(f"扫描 {len(files)} 个文件，命中 {total} 处\n")

    for rid in sorted(findings, key=lambda r: ({"Critical": 0, "High": 1, "Medium": 2, "Low": 3}[sev_of[r]], r)):
        items = findings[rid]
        sev = sev_of[rid]
        mark = {"Critical": "🔴", "High": "🟠", "Medium": "🟡", "Low": "⚪"}[sev]
        print(f"{mark} [{sev}] {CATEGORY_OF.get(rid, rid)} · {rid} · {len(items)} 处")
        print(f"   {msg_of[rid]}")
        if not args.quiet:
            by_file: dict[Path, list[tuple[int, str, str]]] = defaultdict(list)
            for f, line, snip, _ in items:
                by_file[f].append((line, snip, ""))
            for f, rows in sorted(by_file.items(), key=lambda kv: -len(kv[1]))[:6]:
                rel = f.relative_to(ROOT)
                print(f"   {rel}  ({len(rows)})")
                for line, snip, _ in rows[:3]:
                    print(f"     {line:>5}  {snip}")
                if len(rows) > 3:
                    print(f"           … 另有 {len(rows) - 3} 处")
        print()

    print("=" * 72)
    print(f"阻断项（Critical/High）: {blocking}    合计: {total}")
    if blocking:
        print("CI 应在此失败。修完或明确豁免后再合并。")
        return 1
    print("✅ 无阻断项")
    return 0


if __name__ == "__main__":
    sys.exit(main())
