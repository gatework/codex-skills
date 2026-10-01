#!/usr/bin/env bash
# 只读探测：收集 Motor 仓库的事实源索引，不修改任何文件、分支或 git 状态。
# 用法：probe-project.sh [repo-root]
# 输出是索引，不是结论；仍需阅读相关源码、schema、测试后再下判断。
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# 让 git 不为刷新 index 而写锁文件，确保探测对用户工作树零副作用
export GIT_OPTIONAL_LOCKS=0

printf 'motor_admin_probe=3\n'
printf 'root=%s\n' "$(pwd)"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'git_head=%s\n' "$(git rev-parse HEAD 2>/dev/null || echo unborn)"
  branch="$(git branch --show-current || true)"
  printf 'git_branch=%s\n' "$branch"
  if [ -z "$branch" ]; then printf 'git_detached_head=true\n'; fi
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  printf 'git_upstream=%s\n' "$upstream"
  if [ -n "$upstream" ]; then
    printf 'git_ahead_behind=%s\n' "$(git rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null | tr '\t' '/' || true)"
  fi
  printf 'git_latest_tag=%s\n' "$(git describe --tags --abbrev=0 2>/dev/null || true)"
  printf 'git_shallow=%s\n' "$(git rev-parse --is-shallow-repository 2>/dev/null || echo unknown)"
  printf 'git_stash_count=%s\n' "$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\n' 'git_worktrees_begin'
  git worktree list 2>/dev/null || true
  printf '%s\n' 'git_worktrees_end'
  printf '%s\n' 'git_status_begin'
  git status --short --branch -uall
  printf '%s\n' 'git_status_end'
else
  printf 'git=unavailable\n'
fi

printf '%s\n' 'fact_sources_begin'
for path in \
  backend/db/schema.rb \
  backend/config/routes.rb \
  backend/Gemfile \
  backend/Gemfile.lock \
  frontend/pnpm-lock.yaml \
  frontend/package.json \
  frontend/tsconfig.json \
  backend/Dockerfile \
  frontend/Dockerfile \
  docker-compose.dev.yml \
  Makefile \
  docs/DEVELOPMENT_STANDARDS.md \
  docs/CODE_STYLE.md \
  docs/BACKEND_GUIDE.md \
  docs/FRONTEND_GUIDE.md \
  docs/API_CONVENTIONS.md \
  docs/NOTIFICATIONS.md \
  docs/DEPLOYMENT_GUIDE.md \
  docs/REVIEW_PROGRESS.md; do
  if [ -e "$path" ]; then
    printf 'present=%s\n' "$path"
  else
    printf 'missing=%s\n' "$path"
  fi
done
printf '%s\n' 'fact_sources_end'

# 运行时版本与工具链声明（只报告存在与首行内容，不推断兼容性）
printf '%s\n' 'toolchain_begin'
for path in .ruby-version backend/.ruby-version .node-version .nvmrc frontend/.node-version frontend/.nvmrc .tool-versions; do
  if [ -f "$path" ]; then
    printf '%s=%s\n' "$path" "$(head -n 1 "$path" | tr -d '\r')"
  fi
done
for path in backend/.rubocop.yml .rubocop.yml frontend/.eslintrc.cjs frontend/eslint.config.js frontend/eslint.config.mjs frontend/.prettierrc frontend/.stylelintrc.json .editorconfig .github/dependabot.yml; do
  if [ -e "$path" ]; then printf 'present=%s\n' "$path"; fi
done
printf '%s\n' 'toolchain_end'

printf '%s\n' 'workflow_inventory_begin'
if [ -d .github/workflows ]; then
  find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | LC_ALL=C sort
else
  printf 'missing=.github/workflows\n'
fi
printf '%s\n' 'workflow_inventory_end'

printf '%s\n' 'deploy_inventory_begin'
if [ -d deploy ]; then
  find deploy -maxdepth 2 -type f -print | LC_ALL=C sort
else
  printf 'missing=deploy\n'
fi
printf '%s\n' 'deploy_inventory_end'

if [ -f frontend/package.json ]; then
  printf '%s\n' 'frontend_scripts_begin'
  if command -v node >/dev/null 2>&1; then
    node -e '
      const p = require("./frontend/package.json");
      for (const [k, v] of Object.entries(p.scripts || {})) console.log(`${k}=${v}`);
    '
  else
    grep -n '"scripts"' frontend/package.json || true
    printf 'node=unavailable; inspect frontend/package.json directly\n'
  fi
  printf '%s\n' 'frontend_scripts_end'
fi

if [ -f Makefile ]; then
  printf '%s\n' 'make_targets_begin'
  awk -F: '/^[A-Za-z0-9_.-]+:[^=]*$/ { print $1 }' Makefile | LC_ALL=C sort -u
  printf '%s\n' 'make_targets_end'
fi

printf '%s\n' 'docker_stages_begin'
for path in backend/Dockerfile frontend/Dockerfile; do
  if [ -f "$path" ]; then
    awk -v file="$path" 'toupper($1)=="FROM" { print file ":" $0 }' "$path"
  fi
done
printf '%s\n' 'docker_stages_end'
