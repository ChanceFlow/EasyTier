#!/usr/bin/env bash
# 一次跑完全部门禁 + 构建 + 测试。合并前跑这个，任何一步失败即中止。
#
#   bash design-system/easytier/verify-all.sh            # 全量
#   bash design-system/easytier/verify-all.sh --gates    # 只跑静态门禁（秒级）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

GATES_ONLY=0
[ "${1:-}" = "--gates" ] && GATES_ONLY=1

FAILED=()
step() {
  local name="$1"; shift
  printf '\n\033[1m▶ %s\033[0m\n' "$name"
  if "$@"; then
    printf '  \033[32m✅ %s\033[0m\n' "$name"
  else
    printf '  \033[31m❌ %s\033[0m\n' "$name"
    FAILED+=("$name")
  fi
}

# ---- 静态门禁（零依赖，秒级）------------------------------------------------
step "令牌副本未漂移" python3 design-system/easytier/sync-tokens.py --check
step "对比度 60 项断言" python3 design-system/easytier/check-contrast.py
step "设计规则 lint" python3 design-system/easytier/lint-design.py --quiet

if [ "$GATES_ONLY" -eq 1 ]; then
  printf '\n'
  [ ${#FAILED[@]} -eq 0 ] && { printf '\033[32m全部门禁通过\033[0m\n'; exit 0; }
  printf '\033[31m失败: %s\033[0m\n' "${FAILED[*]}"; exit 1
fi

# ---- 构建与测试 -------------------------------------------------------------
step "frontend-lib 构建" pnpm --dir easytier-web/frontend-lib build
step "frontend-lib 单测" pnpm --dir easytier-web/frontend-lib exec vitest run
step "easytier-gui 构建" pnpm --dir easytier-gui build
step "mobile-vpn 单测" pnpm --dir easytier-gui test:mobile-vpn

printf '\n%s\n' "────────────────────────────────────────"
if [ ${#FAILED[@]} -eq 0 ]; then
  printf '\033[32m全部通过\033[0m\n'; exit 0
fi
printf '\033[31m失败项 (%d):\033[0m\n' "${#FAILED[@]}"
printf '  - %s\n' "${FAILED[@]}"
exit 1
