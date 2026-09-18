# 拉取 · 提交 · 推送（冲突交给人裁决）

> 把「拉取 → 提交 → 推送」做成一条可重复的机械流程：机器只做没有歧义的事，唯一需要判断力的冲突取舍留给用户。

## 什么时候用

- 需要把本地改动同步到远端（拉取/提交/push、远端不一致、本地落后或分叉）。
- 整合时遇到冲突、必须决定取舍时——按「升级协议」问用户，不要自己动手。

## 怎么用

确定性内核是 `scripts/git-sync.sh`（脚本只执行 SKILL.md 里那些规则）：

```bash
# 正常同步（提交信息必填；有改动却没给 -m 会以退出码 6 拒绝）
bash scripts/git-sync.sh -C /path/to/repo -m "feat: 说明这次改了什么"

# 看清会发生什么、不真推
bash scripts/git-sync.sh -C /path/to/repo -m "..." --no-push

# 显式把未跟踪文件也纳入提交（先问过用户）
bash scripts/git-sync.sh -C /path/to/repo -m "..." --include-untracked

# 冲突时就地保留现场（默认是 abort 回干净态）
bash scripts/git-sync.sh -C /path/to/repo -m "..." --keep-conflict
```

最后一行固定输出 `GIT_SYNC_RESULT <json>`，**直接解析它**，别去 grep 人类可读输出。

| 退出码 | 含义 | 该做什么 |
|---|---|---|
| 0 | 已同步或本来无事可做 | 报告 sha 即可 |
| 3 | **需要人工裁决**（整合冲突） | 按「升级协议」问用户，不要自己动手 |
| 4 | 前置条件不满足（detached HEAD / 有进行中的 merge·rebase / 无 upstream / 远端不可达 / push 被拒） | 先修前置条件，别硬来 |
| 5 | 安全检查拦截（敏感文件待提交 / 子模块有未推送提交） | 把清单给用户，按他的决定处理 |
| 6 | 有改动但没给提交信息 | 先写清楚这次改了什么，再跑一次 |

## 升级协议（退出码 3 时问什么）

一次问清，别挤牙膏，**不要贴整篇 diff**：① 一句话结论（哪个仓库、哪个分支、几个文件冲突、本地/远端各领先几个提交）；② 每个冲突文件一行（路径 + 冲突类型 both modified / both added / delete-modify / rename + 双方各自意图，取各自 commit message 与几行关键 hunk）；③ 给 2–3 个可执行选项（保留本地改动并 rebase / 放弃本地取远端（需明确同意）/ 用户手工合并后重跑 / 多人共享分支改用 merge）；④ **等用户选**，选完再动手、动完再推。

## 注意事项（铁律与实测教训）

- **冲突不裁决**：报 `status=needs_decision`（退出码 3）就停下来问用户；不允许 `--ours/--theirs` 一把梭、不允许手工拼「都能过」的版本、不允许 `--skip`（git 自己解掉的 rerere/非重叠合并不算冲突）。
- **未跟踪文件默认不入库**：只 `git add -u`，未跟踪文件只在报告里列出；要收进版本库必须显式 `--include-untracked` 且先确认（实测发生过把 `notes-untracked.txt` 当本地改动提交）。
- **永不 force push、永不 `reset --hard`、永不 `clean`**：远端已有别人的提交时，覆盖或丢弃都不是「同步」。
- **先 fetch 再判断**：本地 `origin/*` 引用可能过期，`git status` 会谎报「已是最新」。
- **冲突后不留半成品**：脚本发现冲突会 `git rebase --abort` 回到干净态再退出；要就地手工解决才用 `--keep-conflict`。
- `git ls-files --others` 默认把含非 ASCII 的路径输出成 C 风格转义（`"Docs/\345\212\237..."`），直接 `git add` 会匹配不到 → 文件被**静默漏掉**（脚本已加 `-c core.quotePath=false`，失败项记进 `untracked_add_failed`）。
- 子模块改了要连子模块一起推，只推父仓库会让指针指向子模块里不存在的提交。

## 自测

```bash
bash scripts/selftest.sh          # 建临时测试场，跑 7 个场景（含"冲突必须升级、未跟踪文件不得入库"）
```

改了脚本或本技能后必须重跑；新增场景就加进 `selftest.sh`，不要靠嘴保证。
