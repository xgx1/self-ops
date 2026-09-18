---
name: local-git-archive-server
description: 本机 Git 归档服务器全流程：建 bare 仓库、高压缩配置、LFS 对象补全、双推（origin + local，含阿里云 Codeup 断连处理）、merge unrelated 历史、UE/Unity gitignore、fsck 验证后删本体滚动释放空间。合并自原 local-git-server-archive。
---

# 本地 Git 归档服务器 + 双推 + 删本体

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

场景：磁盘空间紧张，把停开发项目提交 Git 后删除本体释放空间。本地服务器 = **纯 bare 目录集合，无 HTTP/SSH 服务**（本机现用 `~/GitServer`，尚未建时按 §1 的 `mkdir -p` 建；Windows 时代为 `I:\GitServer`，原样保留在 Windows 小节）。双推 = 本地 bare + 原 origin（阿里云 Codeup）。

## 1. 服务器搭建

### Linux（bash）

```bash
mkdir -p ~/GitServer
git init --bare ~/GitServer/<项目>.git
git -C ~/GitServer/<项目>.git config core.compression 9
```

### Windows（PowerShell）

```powershell
New-Item -ItemType Directory -Force I:\GitServer
git init --bare I:\GitServer\<项目>.git
git -C I:\GitServer\<项目>.git config core.compression 9
```

全局压缩（两平台一致，空间紧张时值得设）：

```bash
git config --global core.compression 9
git config --global pack.compression 9
git config --global core.looseCompression 9
git config --global pack.depth 4096  # 会触发 "delta chain depth 4096 is too deep, forcing 4095" 警告，无害
```

- 用**本地路径 remote**（不走网络协议，快）：Linux `git remote add local ~/GitServer/<项目>.git`；Windows `git remote add local I:/GitServer/<项目>.git`

## 2. 逐项目提交与双推

### Linux（bash）

```bash
cd <项目>
git add -A && git commit -m "archive: <描述> (日期)"
git remote add local ~/GitServer/<项目>.git
git push origin master      # 原远程先推（阿里云可能断连，见 §3）
git push local master       # 再推本地 bare
```

### Windows（PowerShell）

```powershell
cd <项目>
git add -A; git commit -m "archive: <描述> (日期)"
git remote add local I:\GitServer\<项目>.git
git push origin master
git push local master
```

- push 用实际分支名（`git branch --show-current`）：新 init 的仓库默认 `main`，老仓库常是 `master`。
- 新项目（无 `.git`）：先写 `.gitignore` → `git init` → add → commit → 双推。

## 3. LFS 坑（UE 项目必踩）

LFS 仓库推本地 bare 报 `push rejected due to missing or corrupt local objects`。以下命令两平台一致（bash 与 PowerShell 写法相同），修复顺序不可换：

```bash
git lfs push origin master   # 先同步远端
git lfs fetch --all          # 拉全对象（实测 4026+ / 19305 个）
git push local master        # 再推本地
```

## 4. 阿里云 Codeup push 断连处理

### 4.1 首选判据：代理吞掉请求体（2026-09 实证根因）

**症状**：push 卡在 `写入对象中: NN%` 长时间不动，或干脆停在 0%；`git pack-objects` 阻塞在 `anon_pipe_write`，`git-remote-https` 空闲（`poll_schedule_timeout`），socket 的 Recv-Q 有数据但**上行字节数几乎不涨**；拖久了报 `send-pack: unexpected disconnect while reading sideband packet` / `远端意外挂断了`。

**误判排除**（这四条都已实测证伪，别再往这儿查）：不是 HTTP/2 与分块传输，不是 `postBuffer` 太小（改成 128 MB 后请求头正常发出 `Content-Length: 17615463`，包体照样不动），不是服务端拒收（裸 `curl` POST 到 receive-pack 地址 0.13 s 返回 401），不是仓库太大（同一提交直连即成）。

**根因**：本机 `http_proxy`/`https_proxy`/`all_proxy` 指向 clash（`127.0.0.1:7897`）时，clash 会**吞掉大体积 POST 请求体**。小请求全部正常——`ls-remote`、ref advertisement、甚至连 LFS 那 76 个对象（2.0 MB）都报 `100% … done`——只有 17.8 MB 的 receive-pack 包体发不出去。**容易被 LFS 成功误导成"网络没问题"**。

**判据**（一条命令验完，Linux）：

```bash
b1=$(ss -tin | awk '/<远端IP>/{f=1} f&&/bytes_sent/{for(i=1;i<=NF;i++) if($i~/bytes_sent:/){gsub("bytes_sent:","",$i); s+=$i}} /^$/{f=0} END{print s+0}')
sleep 8
b2=$(ss -tin | awk '/<远端IP>/{f=1} f&&/bytes_sent/{for(i=1;i<=NF;i++) if($i~/bytes_sent:/){gsub("bytes_sent:","",$i); s+=$i}} /^$/{f=0} END{print s+0}')
echo "$(( (b2-b1)/8/1024 )) KB/s"   # 0 或个位数 = 包体没进 socket
```

**解法**：把 proxy 环境变量全部摘掉走直连（clash 可以继续开着，只是别让 git 走它）：

```bash
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NODE_USE_ENV_PROXY \
  git -c http.lowSpeedLimit=20000 -c http.lowSpeedTime=60 push --progress origin HEAD:master
```

实测：直连后立刻稳定在 **117 KiB/s**，16.80 MiB 包体送达，`59057bc..c8f7306  HEAD -> master`，exit 0。18 MB 量级约 2.5 分钟，**属正常速度，耐心等完**。`--progress` 必须加，否则非 TTY 下看不到进度会误以为又卡死。

**顺带一提**：`-c http.version=HTTP/1.0` 这条路走不通——git-lfs 的 pre-push 钩子会直接报 `Unknown HTTP version "HTTP/1.0"` 并让整条 push 失败，别试。

### 4.2 次选：纯协议层重试

若直连后仍报 `send-pack: unexpected disconnect`（§4.1 判据显示字节在动却中途断），再按老办法：先 `git lfs push aliyun master`（LFS 对象独立传），再重试 refs push（实测第 2 次成功）。大 push HTTP 408：`git config http.postBuffer 536870912` + 重试循环。

## 5. 合并独立历史仓库（网盘快照 → 正式仓库）

### Linux（bash）

```bash
git clone ~/GitServer/X.git work      # bare 无 HEAD 时 checkout 失败
git checkout -b master origin/master  # 手动建本地分支
git remote add snapshot <快照路径>     # 快照是独立仓库时
git fetch snapshot
git merge snapshot/main --allow-unrelated-histories
# 冲突取正式版：git checkout --ours <文件> && git add -A && git commit
```

### Windows（PowerShell）

```powershell
git clone I:\GitServer\X.git work
git checkout -b master origin/master
git remote add snapshot <快照路径>
git fetch snapshot
git merge snapshot/main --allow-unrelated-histories
# 冲突取正式版：git checkout --ours <文件> && git add -A && git commit
```

## 6. gitignore 模板（提交前必查）

- **UE**：`Binaries/ DerivedDataCache/ Intermediate/ Saved/ Build/ .vs/ .vscode/ .idea/ *.sln *.suo`
- **Unity**：`Library/ Temp/ Logs/ obj/ .vs/ .idea/ UserSettings/`

漏掉 UE 的生成物目录 = 几十 GB 进 git（实测有 54GB 的案例）。提交前核对：`git status --porcelain | wc -l` 数量是否合理。

## 7. 验证与删本体

### Linux（bash）

```bash
# 注意：--git-dir= 后面的 ~ 不会被 bash 展开，必须用 $HOME
git --git-dir="$HOME/GitServer/X.git" fsck --strict   # 无输出=通过
git status --porcelain | wc -l                       # 0 = 干净
rm -rf <本体>                                         # 用户确认后
```

### Windows（PowerShell）

```powershell
git --git-dir=I:\GitServer\X.git fsck --strict          # 无输出=通过
(git status --porcelain | Measure-Object -Line).Lines   # 0 = 干净
Remove-Item <本体> -Recurse -Force                       # 用户确认后
```

**删除前三个确认**：工作区干净 + `fsck` 通过 + 双推完成（本地 + 远端两份备份）。活跃开发项目删本体前先问用户（clone 回来要多一步）；多备份项目（同名快照）按用户规则先不动。

## 8. 顺序策略（滚动释放）

先提交停开发项目（bare 小）→ 删本体腾空间 → 再提交活跃大项目。

## 实测数据（2026-08-13）

- XianXia：LFS 4026 对象，bare 3.4GB，本体 65.5GB 删
- HydroVault2：LFS 19305 对象
- YRS：LFS 4681 对象 7.8GB，快照合并后双推成功
