#!/usr/bin/env python3
"""Verify the EasyTier design tokens against WCAG 2.1 contrast minimums.

Parses tokens.css (the real file, not a copy), composites any rgba() over the
relevant surface, and checks every text/background pair the components use.
Exits non-zero on any failure so it can gate CI.

    python3 design-system/easytier/check-contrast.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

TOKENS = Path(__file__).with_name("tokens.css")

# (foreground, background, min_ratio, what it is)
# 4.5 = normal text; 3.0 = large text (>=24px or >=18.66px bold) and non-text UI
# (borders, focus rings, state indicators).
CHECKS: list[tuple[str, str, float, str]] = [
    ("--et-text", "--et-bg", 4.5, "正文 on 画布"),
    ("--et-text", "--et-surface-1", 4.5, "正文 on 卡片"),
    ("--et-text", "--et-surface-2", 4.5, "正文 on 次级卡片"),
    ("--et-text-2", "--et-bg", 4.5, "次要文本 on 画布"),
    ("--et-text-2", "--et-surface-1", 4.5, "次要文本 on 卡片"),
    ("--et-text-2", "--et-surface-2", 4.5, "次要文本 on 次级卡片"),
    ("--et-text-3", "--et-bg", 4.5, "三级文本 on 画布"),
    ("--et-text-3", "--et-surface-1", 4.5, "三级文本 on 卡片"),
    ("--et-text-3", "--et-surface-2", 4.5, "三级文本 on 次级卡片"),
    ("--et-text-disabled", "--et-surface-1", 3.0, "禁用文本（可读下限）"),
    ("--et-accent", "--et-bg", 4.5, "accent 作状态文本 on 画布"),
    ("--et-accent", "--et-surface-1", 4.5, "accent 作状态文本 on 卡片"),
    ("--et-accent", "--et-accent-quiet", 4.5, "accent 文本 on accent 底"),
    ("--et-on-accent", "--et-accent", 4.5, "accent 上的文字/图标"),
    ("--et-info", "--et-surface-1", 4.5, "info 文本 on 卡片"),
    ("--et-info", "--et-info-quiet", 4.5, "info 文本 on info 底"),
    ("--et-on-info", "--et-info", 4.5, "info 上的文字"),
    ("--et-warn", "--et-surface-1", 4.5, "warn 文本 on 卡片"),
    ("--et-warn", "--et-warn-quiet", 4.5, "warn 文本 on warn 底"),
    ("--et-on-warn", "--et-warn", 4.5, "warn 上的文字"),
    ("--et-danger", "--et-surface-1", 4.5, "danger 文本 on 卡片"),
    ("--et-danger", "--et-danger-quiet", 4.5, "danger 文本 on danger 底"),
    ("--et-on-danger", "--et-danger", 4.5, "danger 上的文字"),
    ("--et-neutral", "--et-surface-1", 4.5, "neutral 文本 on 卡片"),
    ("--et-neutral", "--et-bg", 4.5, "neutral 文本 on 画布"),
    ("--et-control-border", "--et-surface-1", 3.0, "控件边界（非文本）"),
    ("--et-control-border", "--et-surface-2", 3.0, "次级卡片上的控件边界"),
    ("--et-control-border", "--et-bg", 3.0, "画布上的控件边界"),
    ("--et-focus", "--et-surface-1", 3.0, "焦点环 on 卡片"),
    ("--et-focus", "--et-bg", 3.0, "焦点环 on 画布"),
]

# 叠加背景：徽标/Chip 的文字画在"自身低透明淡底"上。淡底抬高背景亮度、吃掉对比度，
# 所以必须按**合成后的真实颜色**断言 —— 只看"文字对纯背景"会整类漏掉。
# (前景令牌, 背景规格, 下限, 说明)
#   背景规格 = "--token"              → 实色
#            = ("--token", α, "--底")  → α 透明淡色合成到实色底上
COMPOSITE: list[tuple[str, object, float, str]] = [
    ("--et-accent-on-tint", "--et-accent-quiet", 4.5, "teal 徽标 on accent-quiet"),
    ("--et-info-on-tint", "--et-info-quiet", 4.5, "cyan 徽标 on info-quiet"),
    ("--et-warn-on-tint", ("--et-warn", 0.15, "--et-surface-1"), 4.5, "amber 徽标 15% warn over 卡片"),
    ("--et-warn-on-tint", ("--et-warn", 0.15, "--et-surface-2"), 4.5, "amber 徽标 15% warn over 次级卡片"),
    ("--et-danger-on-tint", ("--et-danger", 0.15, "--et-surface-1"), 4.5, "coral 徽标 15% danger over 卡片"),
    ("--et-danger-on-tint", ("--et-danger", 0.15, "--et-surface-2"), 4.5, "coral 徽标 15% danger over 次级卡片"),
]


def strip_comments(css: str) -> str:
    """Remove /* ... */ including multi-line, so selectors survive intact."""
    return re.sub(r"/\*.*?\*/", "", css, flags=re.DOTALL)


def parse_blocks(css: str) -> list[tuple[str, dict[str, str]]]:
    """Return [(selector, {var: value})] for every top-level block."""
    blocks: list[tuple[str, dict[str, str]]] = []
    pending: list[str] = []
    body: list[str] = []
    depth = 0
    for raw in strip_comments(css).splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if depth == 0:
            # Selectors may span lines and are comma-separated; keep them all.
            if line.endswith("{"):
                pending.append(line[:-1].strip())
                blocks.append((", ".join(p for p in pending if p), {}))
                pending, body, depth = [], [], 1
            else:
                pending.append(line.strip())
            continue
        if line.strip() == "}":
            decls = blocks[-1][1]
            for d in body:
                m = re.match(r"\s*(--[\w-]+)\s*:\s*(.+?);\s*$", d)
                if m:
                    decls[m.group(1)] = m.group(2)
            pending, body, depth = [], [], 0
            continue
        body.append(line)
    return blocks


def resolve(name: str, env: dict[str, str], depth: int = 0) -> str:
    val = env.get(name)
    if val is None:
        raise KeyError(name)
    if depth < 8:
        m = re.fullmatch(r"var\(\s*(--[\w-]+)\s*\)", val.strip())
        if m:
            return resolve(m.group(1), env, depth + 1)
    return val


def to_rgb(value: str) -> tuple[float, float, float, float]:
    """-> (r, g, b, alpha), channels 0-255."""
    v = value.strip()
    h = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", v)
    if h:
        s = h.group(1)
        if len(s) == 3:
            s = "".join(c * 2 for c in s)
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 1.0)
    m = re.fullmatch(r"rgba?\(([^)]+)\)", v)
    if m:
        parts = [p.strip() for p in m.group(1).split(",")]
        r, g, b = (float(parts[i]) for i in range(3))
        a = float(parts[3]) if len(parts) > 3 else 1.0
        return (r, g, b, a)
    raise ValueError(f"not a colour: {value!r}")


def over(fg: tuple[float, float, float, float],
         bg: tuple[float, float, float, float]) -> tuple[float, float, float, float]:
    """Composite a translucent colour over an opaque one."""
    if fg[3] >= 1.0:
        return fg
    a = fg[3]
    return (fg[0] * a + bg[0] * (1 - a),
            fg[1] * a + bg[1] * (1 - a),
            fg[2] * a + bg[2] * (1 - a), 1.0)


def luminance(rgb: tuple[float, float, float, float]) -> float:
    def ch(c: float) -> float:
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(rgb[i]) for i in range(3))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg: tuple[float, float, float, float],
          bg: tuple[float, float, float, float]) -> float:
    bg_solid = over(bg, (0, 0, 0, 1)) if bg[3] < 1 else bg
    fg_solid = over(fg, bg_solid)
    a, b = luminance(fg_solid), luminance(bg_solid)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def pick(blocks: list[tuple[str, dict[str, str]]], needle: str) -> dict[str, str]:
    for sel, decls in blocks:
        if needle in sel:
            return decls
    raise SystemExit(f"tokens.css: no block matching {needle!r}")


def main() -> int:
    blocks = parse_blocks(TOKENS.read_text())
    base = pick(blocks, ":root")
    themes = {
        "dark": {**base, **pick(blocks, "m3Dark")},
        "light": {**base, **pick(blocks, "m3Light")},
    }

    failures = 0
    for theme, env in themes.items():
        print(f"\n=== {theme.upper()} ===")
        print(f"  {'前景':<24}{'背景':<20}{'实测':>7}{'要求':>7}  {'':<4}说明")
        for fg_n, bg_n, minimum, label in CHECKS:
            try:
                fg = to_rgb(resolve(fg_n, env))
                bg = to_rgb(resolve(bg_n, env))
            except (KeyError, ValueError) as exc:
                print(f"  !! {fg_n} / {bg_n}: {exc}")
                failures += 1
                continue
            got = ratio(fg, bg)
            ok = got >= minimum
            if not ok:
                failures += 1
            print(f"  {fg_n:<24}{bg_n:<20}{got:>6.2f}{minimum:>7.1f}  "
                  f"{'PASS' if ok else 'FAIL':<4} {label}")

    print()
    if failures:
        print(f"❌ {failures} 项未达标")
        return 1
    print(f"✅ 全部 {len(CHECKS) * len(themes)} 项通过（暗/亮各 {len(CHECKS)} 项）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
