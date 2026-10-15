---
name: local-git-server-archive
description: 把本地项目归档到本机 Git 服务器（bare 目录）并删除本体的标准流程：bare 建仓、高压缩配置、LFS 对象补全、双推 origin+local、fsck 验证、UE/Unity gitignore、删本体
---

# 本地 Git 服务器归档流程（I:\GitServer）

把项目统一提交到本机 Git 服务器（bare 仓库目录），验证后删除本体释放空间。实测于 2026-08-13。

## 1. 服务器

```powershell
# bare 仓库（I 盘；可改盘符）
git init --bare I:\GitServer\<项目名>.git
git -C I:\GitServer\<项目名>.git config core.compression 9
```

- 全局压缩：`git config --global core.compression 9` + `pack.compression 9` + `core.looseCompression 9`
- push 用本地路径 remote：`git remote add local I:/GitServer/xxx.git`（不走网络协议，快）
- 服务器可用 = 纯 bare 目录，无 HTTP/SSH 服务

## 2. 逐项目提交

```powershell
cd <项目>
git add -A
git commit -m "archive: <描述> (日期)"
git push local master   # 或 main（git init 默认 main，先 git branch 确认）
```

- 已有 origin（阿里云/Codeup）的项目**双推**：先 `git push origin` 再 `git push local`
- 新项目（无 .git）：先写 .gitignore → `git init` → add → commit → push

## 3. LFS 坑（UE 项目必踩）

LFS 仓库推本地 bare 报 `push rejected due to missing or corrupt local objects`。修复顺序：

```powershell
git lfs push origin master   # 先同步远端
git lfs fetch --all          # 拉全对象
git push local master        # 再推本地
```

## 4. gitignore 模板

- UE：`Binaries/ DerivedDataCache/ Intermediate/ Saved/ Build/ .vs/ .vscode/ .idea/ *.sln *.suo`
- Unity：`Library/ Temp/ Logs/ obj/ .vs/ .idea/ UserSettings/`
- 提交前核对生成物未入库（`git status --porcelain | wc -l` 数量合理）

## 5. 验证后删本体

```powershell
git --git-dir=I:\GitServer\xxx.git fsck          # 无报错=通过
cd <项目> && git status --porcelain | wc -l      # 0 = 干净
Remove-Item <项目> -Recurse -Force
```

- 删除前确认：工作区干净 + fsck 通过 + 双推完成（本地+远端双备份）
- 活跃开发项目删本体前询问用户（clone 回来要多一步）
- 多备份项目（同名快照）按用户规则先不动
