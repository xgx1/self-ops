---
name: local-git-archive-server
description: 本机建 Git 归档服务器并双推（本地 bare + 阿里云 Codeup），含 LFS 全量同步、merge unrelated 历史、提交后删本体滚动释放空间的标准流程
---

# 本地 Git 归档服务器 + 双推流程

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

场景：磁盘空间紧张，把停开发项目提交 Git 后删除本体释放空间。本地服务器 = bare 仓库集合（**本机现用 `~/GitServer`**，尚未建时按 §1 的 `mkdir -p` 建；Windows 时代为 `I:\GitServer`，原样保留在下面的 Windows 小节），双推 = 本地 bare + 原 origin（阿里云 Codeup）。

## 1. 服务器搭建

### Linux（bash）

```bash
mkdir -p ~/GitServer
git init --bare ~/GitServer/<项目>.git
# 压缩配置（空间紧张要求）
git config --global core.compression 9
git config --global pack.compression 9
git config --global core.looseCompression 9
git config --global pack.depth 4096  # 注意：pack.depth 4096 会触发 "delta chain depth 4096 is too deep, forcing 4095" 警告，无害
git -C ~/GitServer/<项目>.git config core.compression 9
```

### Windows（PowerShell）

```powershell
New-Item -ItemType Directory -Force I:\GitServer
git init --bare I:\GitServer\<项目>.git
# 压缩配置（用户空间紧张要求）
git config --global core.compression 9
git config --global pack.compression 9
git config --global core.looseCompression 9
git config --global pack.depth 4096  # 注意：pack.depth 4096 会触发 "delta chain depth 4096 is too deep, forcing 4095" 警告，无害
git -C I:\GitServer\<项目>.git config core.compression 9
```

## 2. 项目提交双推（LFS 项目）

### Linux（bash）

```bash
cd <项目>
git add -A && git commit -m "archive: ..."
git remote add local ~/GitServer/<项目>.git
git push origin master      # 原远程先推（阿里云可能断连，见下）
# LFS 关键：本地 LFS 对象常不完整，push local 报 "missing or corrupt local objects"
git lfs push origin master  # 先同步 LFS 到 origin
git lfs fetch --all         # 拉全 4026+ 对象
git push local master       # 再推本地（LFS 对象自动上传到 bare）
```

### Windows（PowerShell）

```powershell
cd <项目>
git add -A && git commit -m "archive: ..."
git remote add local I:\GitServer\<项目>.git
git push origin master      # 原远程先推（阿里云可能断连，见下）
# LFS 关键：本地 LFS 对象常不完整，push local 报 "missing or corrupt local objects"
git lfs push origin master  # 先同步 LFS 到 origin
git lfs fetch --all         # 拉全 4026+ 对象
git push local master       # 再推本地（LFS 对象自动上传到 bare）
```

## 3. 阿里云 Codeup push 断连处理

本节命令两平台一致（bash 与 PowerShell 写法相同）：

refs push 报 `send-pack: unexpected disconnect` 时：先 `git lfs push aliyun master`（LFS 对象独立传），再重试 refs push（实测第 2 次成功）。大 push HTTP 408：`git config http.postBuffer 536870912` + 重试循环。

## 4. 合并独立历史仓库（网盘快照 → 正式仓库）

### Linux（bash）

```bash
git clone ~/GitServer/X.git work   # bare 无 HEAD 时 checkout 失败
git checkout -b master origin/master  # 手动建本地分支
# 快照是独立仓库时：
git remote add snapshot <快照路径>
git fetch snapshot
git merge snapshot/main --allow-unrelated-histories
# 冲突取正式版：git checkout --ours <文件> && git add -A && git commit
```

### Windows（PowerShell）

```powershell
git clone I:\GitServer\X.git work   # bare 无 HEAD 时 checkout 失败
git checkout -b master origin/master  # 手动建本地分支
# 快照是独立仓库时：
git remote add snapshot <快照路径>
git fetch snapshot
git merge snapshot/main --allow-unrelated-histories
# 冲突取正式版：git checkout --ours <文件> && git add -A && git commit
```

## 5. 验证与删本体

### Linux（bash）

```bash
# 注意：--git-dir= 后面的 ~ 不会被 bash 展开，必须用 $HOME
git --git-dir="$HOME/GitServer/X.git" fsck --strict   # 无输出=通过
git status --porcelain | wc -l                       # 0 = 干净
rm -rf <本体>                                         # 用户确认后
```

### Windows（PowerShell）

```powershell
git --git-dir=I:\GitServer\X.git fsck --strict   # 无输出=通过
git status --porcelain | Measure-Object -Line    # 0 = 干净
Remove-Item <本体> -Recurse -Force                # 用户确认后
```

## 6. 顺序策略（滚动释放）

先提交停开发项目（bare 小）→ 删本体腾空间 → 再提交活跃大项目。UE 项目 gitignore 必含 Binaries/Intermediate/Saved/DerivedDataCache/Build（否则 54GB 生成物进 git）。

## 实测数据（2026-08-13）

- XianXia：LFS 4026 对象，bare 3.4GB，本体 65.5GB 删
- HydroVault2：LFS 19305 对象
- YRS：LFS 4681 对象 7.8GB，快照合并后双推成功
- 新 init 仓库默认分支 main（git 2.x），push 用实际分支名（git branch --show-current）
