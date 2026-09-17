#!/usr/bin/env python3
"""把设计令牌同步进 frontend-lib（单一来源，禁止手改副本）。

来源: design-system/easytier/tokens.css
去向: easytier-web/frontend-lib/src/tokens.css

    python3 design-system/easytier/sync-tokens.py           # 写入
    python3 design-system/easytier/sync-tokens.py --check   # 只校验（CI 用）

--check 在不一致时非零退出，防止有人直接改副本造成漂移。
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).with_name("tokens.css")
DST = ROOT / "easytier-web" / "frontend-lib" / "src" / "tokens.css"

BANNER = """/* ！！自动生成，请勿手改 ！！
 * 来源: design-system/easytier/tokens.css
 * 同步: python3 design-system/easytier/sync-tokens.py
 * 校验: python3 design-system/easytier/sync-tokens.py --check
 *
 * 直接改本文件会在下次同步时被覆盖，且 --check 会让 CI 失败。
 */
"""


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def main() -> int:
    check = "--check" in sys.argv[1:]
    source = SRC.read_text(encoding="utf-8")
    generated = BANNER + source

    if check:
        if not DST.exists():
            print(f"❌ 缺少生成文件 {DST.relative_to(ROOT)} —— 跑 sync-tokens.py")
            return 1
        current = DST.read_text(encoding="utf-8")
        if current == generated:
            print(f"✅ 令牌一致 (sha {digest(generated)})")
            return 0
        # 去掉 banner 再比，能区分"只是 banner 旧了"和"内容真漂移了"
        body = current.split("*/", 1)[-1].lstrip("\n")
        if body == source:
            print("⚠️  内容一致但 banner 过期 —— 跑 sync-tokens.py 刷新")
            return 1
        print(f"❌ 令牌漂移！副本被直接改过。")
        print(f"   来源 sha {digest(source)}   副本 sha {digest(body)}")
        print(f"   跑 sync-tokens.py 覆盖，或把改动挪回 design-system/easytier/tokens.css")
        return 1

    DST.write_text(generated, encoding="utf-8")
    print(f"✅ 已同步 → {DST.relative_to(ROOT)}  (sha {digest(generated)})")
    print(f"   来源 {len(source.splitlines())} 行，副本含 banner 共 {len(generated.splitlines())} 行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
