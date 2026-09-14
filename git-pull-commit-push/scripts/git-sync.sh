#!/usr/bin/env bash
# git-sync.sh — 「拉取 / 提交 / 推送」的确定性内核。
# 判断与升级策略（什么时候必须停下来问人）见同目录 SKILL.md；本脚本只做机械动作。
#
# 用法：git-sync.sh [-C <repo>] -m <提交信息> [--branch <b>] [--include-untracked]
#                   [--keep-conflict] [--no-push] [--json]
#
# 退出码：
#   0  完成（已同步，或本来无事可做）
#   3  需要人工裁决（整合冲突 / 远端在你工作期间又前进且仍有冲突）
#   4  前置条件不满足（detached HEAD / 有进行中的 merge|rebase / 无 upstream / 远端不可达 / push 被拒）
#   5  安全检查拦截（待提交内容命中敏感文件；子模块还有未推送提交）
#   6  有改动但没给提交信息（-m）
#   2  用法错误
#
# 无论成败，最后一行输出 `GIT_SYNC_RESULT <json>`（status/reason/message + 细节），
# 机器解析这一行即可；上面的人类可读输出不用管。

set -uo pipefail

REPO="."; MSG=""; BRANCH=""; INCLUDE_UNTRACKED=0; KEEP_CONFLICT=0; NO_PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    -C) REPO="$2"; shift 2 ;;
    -m) MSG="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --include-untracked) INCLUDE_UNTRACKED=1; shift ;;
    --keep-conflict) KEEP_CONFLICT=1; shift ;;
    --no-push) NO_PUSH=1; shift ;;
    --json) shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '; }
emit() { # emit <status> <reason> <message> [extra-json-fields]
  printf '\nGIT_SYNC_RESULT {"status":"%s","reason":"%s","message":"%s"%s}\n' \
    "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$3")" "${4:-}"
}
die() { # die <exit-code> <status> <reason> <message> [extra]
  echo "❌ $4" >&2
  emit "$2" "$3" "$4" "${5:-}"
  exit "$1"
}
arr_json() { # stdin 逐行 → JSON 数组
  local out="[" first=1 line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [ $first -eq 0 ] && out="$out,"
    out="$out\"$(jesc "$line")\""; first=0
  done
  printf '%s]' "$out"
}
divergence() { read -r BEHIND AHEAD < <(git rev-list --left-right --count "$UPSTREAM...HEAD" 2>/dev/null || echo "0 0"); }

# ---------- 0. 定位仓库 ----------
command -v git >/dev/null || die 4 blocked no_git "找不到 git"
cd "$REPO" 2>/dev/null || die 4 blocked no_repo "目录不存在：$REPO"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || die 4 blocked no_repo "不是 git 仓库：$REPO"
cd "$REPO"

# ---------- 1. 前置条件 ----------
git symbolic-ref -q HEAD >/dev/null || die 4 blocked detached_head "当前是 detached HEAD，先切回分支"
GITDIR="$(git rev-parse --git-dir)"
for f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  [ -e "$GITDIR/$f" ] && die 4 blocked operation_in_progress "仓库里有进行中的操作（$f）——先手工完成或中止它，再跑本脚本"
done

BRANCH="${BRANCH:-$(git branch --show-current)}"
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
  || die 4 blocked no_upstream "分支 $BRANCH 没有配置 upstream（git push -u origin $BRANCH）"
REMOTE="${UPSTREAM%%/*}"; REMOTE_BRANCH="${UPSTREAM#*/}"
git ls-remote --exit-code "$REMOTE" >/dev/null 2>&1 \
  || die 4 blocked remote_unreachable "远端 $REMOTE 不可达（网络/凭据/地址问题）——先解决连通性，别在本地瞎猜"

# ---------- 2. 先 fetch：本地 origin/* 引用可能过期（"已是最新"会说谎） ----------
git fetch --prune "$REMOTE" >/dev/null 2>&1 || die 4 blocked fetch_failed "git fetch $REMOTE 失败"
REMOTE_SHA="$(git rev-parse "$UPSTREAM")"

# ---------- 3. 子模块检查（必须在 git add -u 之前：暂存会把指针差异抹平） ----------
SUBMOD_BAD=""
while IFS= read -r line; do
  case "$line" in
    +*|U*|'-'*) : ;;   # + 已切换/未同步，- 未初始化，U 冲突；都要查
    *) continue ;;
  esac
  path="$(printf '%s' "$line" | awk '{print $2}')"
  [ -z "$path" ] && continue
  if [ -d "$path/.git" ] || [ -f "$path/.git" ]; then
    cnt="$(git -C "$path" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    [ "${cnt:-0}" -gt 0 ] && SUBMOD_BAD="$SUBMOD_BAD$path（$cnt 个未推送提交）；"
  else
    SUBMOD_BAD="$SUBMOD_BAD$path（未初始化）；"
  fi
done < <(git submodule status --recursive 2>/dev/null)
[ -n "$SUBMOD_BAD" ] && die 5 unsafe submodule_unpushed \
  "子模块还有未推送/未初始化的内容：$SUBMOD_BAD 先在子模块里提交并 push，再回父仓库更新指针" \
  ",\"submodules\":\"$(jesc "$SUBMOD_BAD")\""

# ---------- 4. 工作区：只暂存已跟踪文件的修改；未跟踪文件默认不动 ----------
UNTRACKED_LIST="$(git ls-files --others --exclude-standard)"
UNTRACKED_JSON="$(printf '%s\n' "$UNTRACKED_LIST" | arr_json)"
UNTRACKED_N=$(printf '%s\n' "$UNTRACKED_LIST" | grep -c . || true)

git add -u
if [ "$INCLUDE_UNTRACKED" -eq 1 ] && [ -n "$UNTRACKED_LIST" ]; then
  while IFS= read -r f; do [ -n "$f" ] && git add -- "$f"; done <<< "$UNTRACKED_LIST"
fi

STAGED="$(git diff --cached --name-only)"
STAGED_N=$(printf '%s\n' "$STAGED" | grep -c . || true)

# ---------- 5. 安全检查：敏感文件 ----------
if [ "$STAGED_N" -gt 0 ]; then
  SECRETS="$(printf '%s\n' "$STAGED" | grep -Ei '(^|/)\.env($|\.)|(^|/)\.credentials|\.pfx$|\.p12$|\.key$|\.pem$|(^|/)id_rsa|(^|/)id_ed25519' || true)"
  [ -n "$SECRETS" ] && die 5 unsafe secret_staged "待提交内容命中敏感文件，已中止" \
    ",\"secrets\":$(printf '%s\n' "$SECRETS" | arr_json)"
fi

# ---------- 6. 提交 ----------
COMMITTED=0
if [ "$STAGED_N" -gt 0 ]; then
  [ -z "$MSG" ] && die 6 invalid missing_message "有 $STAGED_N 个文件待提交，但没给提交信息（-m '<信息>'）"
  git commit -q -m "$MSG" || die 4 blocked commit_failed "git commit 失败"
  COMMITTED=1
fi
LOCAL_SHA="$(git rev-parse HEAD)"
divergence   # 提交之后必须重算：否则会把"本地已领先"误判成"可快进"

# ---------- 7. 整合远端 ----------
conflict_report() { # $1=reason-code
  local cf="[" first=1 f code
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    code="$(git status --porcelain -- "$f" | awk '{print $1}' | head -1)"
    [ $first -eq 0 ] && cf="$cf,"; first=0
    cf="$cf{\"path\":\"$(jesc "$f")\",\"code\":\"$(jesc "$code")\"}"
  done < <(git diff --name-only --diff-filter=U | sort -u)
  cf="$cf]"
  local n; n=$(git diff --name-only --diff-filter=U | grep -c . || true)
  local extra=",\"repo\":\"$(jesc "$REPO")\",\"branch\":\"$(jesc "$BRANCH")\""
  extra="$extra,\"local_sha\":\"$(jesc "$LOCAL_SHA")\",\"remote_sha\":\"$(jesc "$REMOTE_SHA")\""
  extra="$extra,\"ahead\":$AHEAD,\"behind\":$BEHIND,\"conflicts\":$cf"
  extra="$extra,\"untracked\":$UNTRACKED_JSON,\"committed\":$COMMITTED"
  if [ "$KEEP_CONFLICT" -eq 0 ]; then
    git rebase --abort >/dev/null 2>&1
    git merge --abort >/dev/null 2>&1
    extra="$extra,\"workspace_restored\":true"
  else
    extra="$extra,\"workspace_restored\":false"
  fi
  die 3 needs_decision "$1" "整合远端时发生冲突（$n 个文件）——按 SKILL.md 停下来问用户，不要自己选边" "$extra"
}

INTEGRATED="none"
if [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -gt 0 ]; then
  git merge --ff-only "$UPSTREAM" >/dev/null 2>&1 || conflict_report "ff_failed"
  INTEGRATED="ff"
elif [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -gt 0 ]; then
  git rebase "$UPSTREAM" >/dev/null 2>&1 || conflict_report "rebase_conflict"
  INTEGRATED="rebase"
fi

# ---------- 8. 推送 ----------
PUSHED="no"
if [ "$NO_PUSH" -eq 0 ]; then
  PENDING="$(git rev-list --count "$UPSTREAM..HEAD")"
  if [ "${PENDING:-0}" -gt 0 ]; then
    if ! git push "$REMOTE" "HEAD:$REMOTE_BRANCH" >/dev/null 2>&1; then
      git fetch --prune "$REMOTE" >/dev/null 2>&1
      REMOTE_SHA="$(git rev-parse "$UPSTREAM")"
      divergence
      if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
        git rebase "$UPSTREAM" >/dev/null 2>&1 || conflict_report "push_rejected_conflict"
        INTEGRATED="rebase_retry"
      fi
      git push "$REMOTE" "HEAD:$REMOTE_BRANCH" >/dev/null 2>&1 \
        || die 4 blocked push_failed "git push 失败（远端拒绝或无权限）"
    fi
    PUSHED="yes"
  fi
fi

FINAL_SHA="$(git rev-parse HEAD)"; FINAL_REMOTE="$(git rev-parse "$UPSTREAM" 2>/dev/null || echo '')"
echo "✅ 同步完成：分支 $BRANCH  $FINAL_SHA"
echo "   整合方式=$INTEGRATED  推送=$PUSHED  未跟踪文件（未入库）=$UNTRACKED_N"
emit done ok "同步完成" \
  ",\"repo\":\"$(jesc "$REPO")\",\"branch\":\"$(jesc "$BRANCH")\",\"sha\":\"$(jesc "$FINAL_SHA")\",\"remote_sha\":\"$(jesc "$FINAL_REMOTE")\",\"integrated\":\"$INTEGRATED\",\"pushed\":\"$PUSHED\",\"committed\":$COMMITTED,\"untracked\":$UNTRACKED_JSON"
exit 0
