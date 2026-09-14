#!/usr/bin/env bash
# selftest.sh — git-sync.sh 的场景自测：每个场景独立建临时仓库对，断言退出码与最终状态。
# 改了 git-sync.sh 或 SKILL.md 的判断规则后必须重跑。
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/git-sync.sh"
LAB="$(mktemp -d /tmp/git-sync-selftest.XXXXXX)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
check(){ # check <描述> <期望> <实际>
  if [ "$2" = "$3" ]; then ok "$1（=$3）"; else bad "$1：期望 [$2] 实际 [$3]"; fi
}
json_ok(){ # json_ok <场景> <完整输出> —— 结果行必须是合法 JSON（拼装错误靠这条抓）
  local line; line="$(printf '%s' "$2" | grep -o 'GIT_SYNC_RESULT .*' | head -1 | sed 's/^GIT_SYNC_RESULT //')"
  if [ -z "$line" ]; then bad "$1 输出里没有 GIT_SYNC_RESULT 行"; return; fi
  if printf '%s' "$line" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
    ok "$1 结果行是合法 JSON"
  else
    bad "$1 结果行不是合法 JSON：$line"
  fi
}

# new_pair <名字> → $LAB/<名字>/{origin.git,work,peer}
new_pair() {
  local d="$LAB/$1"; mkdir -p "$d"; cd "$d"
  git init -q --bare --initial-branch=main origin.git
  git clone -q origin.git work 2>/dev/null; git clone -q origin.git peer 2>/dev/null
  cd "$d/work"; mkdir -p src; printf 'line1\nline2\nline3\n' > src/app.txt; printf 'readme\n' > README.md
  git add -A; git commit -q -m "init: base"; git push -q -u origin main
  cd "$d/peer"; git fetch -q origin; git checkout -q main
}
peer_commit() { # peer_commit <名字> <文件> <内容> <信息>
  cd "$LAB/$1/peer"; printf '%s' "$3" > "$2"; git add -A; git commit -q -m "$4"; git push -q origin main
}
remote_sha() { git --git-dir="$LAB/$1/origin.git" rev-parse main; }
work()  { cd "$LAB/$1/work"; }

echo "测试场：$LAB"
echo

# ---------- S1 干净、无改动、无落后 → 0 ----------
new_pair s1; work s1
out=$(bash "$SCRIPT" -C "$LAB/s1/work" -m "noop" 2>&1); rc=$?
json_ok S1 "$out"
check "S1 退出码 0（无事可做）" 0 "$rc"
check "S1 未推送" "no" "$(printf '%s' "$out" | sed -n 's/.*"pushed":"\([a-z]*\)".*/\1/p')"

# ---------- S2 本地领先（已提交未推）→ 0 且推到远端 ----------
new_pair s2; work s2
printf 'line1\nlocal-only\nline3\n' > src/app.txt; git add -u; git commit -q -m "local: 领先一个提交"
out=$(bash "$SCRIPT" -C "$LAB/s2/work" -m "unused" 2>&1); rc=$?
json_ok S2 "$out"
check "S2 退出码 0" 0 "$rc"
check "S2 远端已收到本地提交" "$(git rev-parse HEAD)" "$(remote_sha s2)"

# ---------- S3 远端领先、本地干净 → 0 快进 ----------
new_pair s3; peer_commit s3 src/other.txt "peer\n" "peer: 新增文件"
out=$(bash "$SCRIPT" -C "$LAB/s3/work" -m "unused" 2>&1); rc=$?
json_ok S3 "$out"
work s3
check "S3 退出码 0" 0 "$rc"
check "S3 已快进到远端" "$(remote_sha s3)" "$(git rev-parse HEAD)"

# ---------- S4 分叉但无冲突（不同文件）→ 0 自动整合并推送 ----------
new_pair s4; peer_commit s4 src/peer.txt "peer\n" "peer: 加 peer 文件"
work s4; printf 'line1\nlocal\nline3\n' > src/app.txt
out=$(bash "$SCRIPT" -C "$LAB/s4/work" -m "local: 改 app.txt" 2>&1); rc=$?
json_ok S4 "$out"
check "S4 退出码 0" 0 "$rc"
check "S4 已推送（本地=远端）" "$(git rev-parse HEAD)" "$(remote_sha s4)"
check "S4 是 rebase 整合" "rebase" "$(printf '%s' "$out" | sed -n 's/.*"integrated":"\([a-z_]*\)".*/\1/p')"

# ---------- S5 分叉且同一行冲突（本地未提交）→ 3，不推送、工作区干净、本地提交保留 ----------
new_pair s5; peer_commit s5 src/app.txt "line1\nREMOTE-change\nline3\n" "remote: 改 line2"
work s5; printf 'line1\nLOCAL-change\nline3\n' > src/app.txt; printf 'scratch\n' > notes-untracked.txt
before_remote=$(remote_sha s5)
out=$(bash "$SCRIPT" -C "$LAB/s5/work" -m "local: 改 line2" 2>&1); rc=$?
json_ok S5 "$out"
check "S5 退出码 3（升级给人）" 3 "$rc"
check "S5 未推送（远端保持原样）" "$before_remote" "$(remote_sha s5)"
check "S5 工作区干净（无冲突残留）" "" "$(git status --porcelain | grep -E '^(UU|AA|DD|AU|UA|DU|UD)' | tr '\n' ' ' | sed 's/ $//')"
check "S5 无半完成 rebase" "no" "$([ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] && echo yes || echo no)"
check "S5 本地提交已保留" "local: 改 line2" "$(git log -1 --pretty=%s)"
check "S5 未跟踪文件仍未入库" "" "$(git ls-files notes-untracked.txt)"
check "S5 报告含冲突文件" "src/app.txt" "$(printf '%s' "$out" | sed -n 's/.*"conflicts":\[{"path":"\([^"]*\)".*/\1/p')"

# ---------- S6 未跟踪文件不得被提交 ----------
new_pair s6; work s6
printf 'line1\ntracked-change\nline3\n' > src/app.txt; printf 'scratch\n' > notes-untracked.txt
out=$(bash "$SCRIPT" -C "$LAB/s6/work" -m "local: 只提交已跟踪改动" 2>&1); rc=$?
json_ok S6 "$out"
check "S6 退出码 0" 0 "$rc"
check "S6 已跟踪改动进了提交" "src/app.txt" "$(git show --pretty=format: --name-only HEAD | tr -d '\n')"
check "S6 未跟踪文件不在提交里" "" "$(git ls-files notes-untracked.txt)"
check "S6 未跟踪文件仍在磁盘" "yes" "$([ -f notes-untracked.txt ] && echo yes || echo no)"

# ---------- S7 有进行中的 rebase → 4 ----------
new_pair s7; work s7; mkdir -p .git/rebase-merge
out=$(bash "$SCRIPT" -C "$LAB/s7/work" -m "x" 2>&1); rc=$?
json_ok S7 "$out"
check "S7 退出码 4（前置条件不满足）" 4 "$rc"
check "S7 原因 operation_in_progress" "operation_in_progress" "$(printf '%s' "$out" | sed -n 's/.*"reason":"\([a-z_]*\)".*/\1/p')"

# ---------- S8 待提交内容命中敏感文件 → 5 ----------
new_pair s8; work s8
printf 'TOKEN=old\n' > .env; git add -f .env; git commit -q -m "chore: 假装历史上就有 .env"; git push -q origin main
printf 'TOKEN=new\n' > .env
out=$(bash "$SCRIPT" -C "$LAB/s8/work" -m "chore: 改 env" 2>&1); rc=$?
json_ok S8 "$out"
check "S8 退出码 5（安全拦截）" 5 "$rc"
check "S8 未推送" "yes" "$([ "$(remote_sha s8)" = "$(work s8; git rev-parse HEAD)" ] && echo yes || echo no)"

# ---------- S9 子模块有未推送提交 → 5 ----------
new_pair s9
cd "$LAB/s9"; git init -q --bare --initial-branch=main sub.git
git clone -q sub.git subcls 2>/dev/null; cd subcls; printf 'sub\n' > f.txt; git add -A; git commit -q -m "sub: init"; git push -q origin main
cd "$LAB/s9/work"; git -c protocol.file.allow=always submodule add -q "$LAB/s9/sub.git" vendor/sub >/dev/null 2>&1
git add -A; git commit -q -m "chore: 加子模块"; git push -q origin main
cd vendor/sub; printf 'sub2\n' >> f.txt; git add -A; git commit -q -m "sub: 本地提交未推送"
cd "$LAB/s9/work"; printf 'line1\nx\nline3\n' > src/app.txt
out=$(bash "$SCRIPT" -C "$LAB/s9/work" -m "feat: x" 2>&1); rc=$?
json_ok S9 "$out"
check "S9 退出码 5（子模块未推送）" 5 "$rc"
check "S9 原因 submodule_unpushed" "submodule_unpushed" "$(printf '%s' "$out" | sed -n 's/.*"reason":"\([a-z_]*\)".*/\1/p')"

# ---------- S10 --include-untracked 必须能收进非 ASCII 文件名的文件 ----------
# （实测回归：git 默认把含非 ASCII 的路径输出成 C 风格转义 "Docs/\345..."，
#   拿它去 git add 匹配不到，文件被静默漏掉而脚本仍报成功）
new_pair s10; work s10
printf 'line1\ntracked-change\nline3\n' > src/app.txt
printf '内容\n' > "闸门控制配置手册.md"
out=$(bash "$SCRIPT" -C "$LAB/s10/work" -m "docs: 纳入中文名文件" --include-untracked 2>&1); rc=$?
json_ok S10 "$out"
check "S10 退出码 0" 0 "$rc"
check "S10 中文名文件已入库" "闸门控制配置手册.md" "$(git -c core.quotePath=false ls-files '闸门控制配置手册.md')"
check "S10 已推送到远端" "yes" "$([ "$(remote_sha s10)" = "$(work s10; git rev-parse HEAD)" ] && echo yes || echo no)"
check "S10 无 add 失败记录" "" "$(printf '%s' "$out" | sed -n 's/.*"untracked_add_failed":"\([^"]*\)".*/\1/p')"

# ---------- 汇总 ----------
echo
echo "===================="
printf '通过 %d / 失败 %d\n' "$PASS" "$FAIL"
echo "测试场保留在：$LAB（不需要就删掉）"
[ "$FAIL" -eq 0 ] || exit 1
