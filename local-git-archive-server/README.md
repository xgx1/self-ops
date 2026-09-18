# 本机 Git 归档服务器 + 双推 + 删本体

> 磁盘紧张时把停开发的项目提交进本机 bare 归档库并双推远端，验证通过后删掉工作副本释放空间。

## 什么时候用

- 磁盘空间紧张，要把停开发/已完结的项目归档后删除本体。
- 需要一套本地 bare 仓库集合（**纯 bare 目录，无 HTTP/SSH 服务**，本机现用 `~/GitServer`）作为第二份备份。
- 要合并「网盘快照」这类独立历史的仓库。

## 1. 搭建服务器

```bash
mkdir -p ~/GitServer
git init --bare ~/GitServer/<项目>.git
git -C ~/GitServer/<项目>.git config core.compression 9
```

空间紧张时值得设全局压缩（两平台一致；`pack.depth` 会触发 `delta chain depth 4096 is too deep, forcing 4095` 警告，无害）：

```bash
git config --global core.compression 9
git config --global pack.compression 9
git config --global core.looseCompression 9
git config --global pack.depth 4096
```

remote 用**本地路径**（不走网络协议，快）：`git remote add local ~/GitServer/<项目>.git`。

## 2. 逐项目提交与双推

```bash
cd <项目>
git add -A && git commit -m "archive: <描述> (日期)"
git remote add local ~/GitServer/<项目>.git
git push origin master      # 原远程先推（阿里云可能断连，见 §4）
git push local master       # 再推本地 bare
```

push 用实际分支名（`git branch --show-current`）：新 init 的仓库默认 `main`，老仓库常是 `master`。新项目先写 `.gitignore` → `git init` → add → commit → 双推。

## 3. LFS（UE 项目必踩，修复顺序不可换）

推本地 bare 报 `push rejected due to missing or corrupt local objects` 时：

```bash
git lfs push origin master   # 先同步远端
git lfs fetch --all          # 拉全对象（实测 4026+ / 19305 个）
git push local master        # 再推本地
```

## 4. 阿里云 Codeup push 断连（2026-09 实证根因）

症状：卡在 `写入对象中: NN%` 长时间不动，socket 的 `Recv-Q` 有数据但**上行字节几乎不涨**，拖久了报 `send-pack: unexpected disconnect while reading sideband packet`。**根因是 clash 代理吞掉大体积 POST 请求体**——小请求、连 LFS 那 76 个对象（2.0MB）都正常，只有 17.8MB 的 receive-pack 包体发不出去。判据（`<远端IP>` 换成实际地址）：

```bash
b1=$(ss -tin | awk '/<远端IP>/{f=1} f&&/bytes_sent/{for(i=1;i<=NF;i++) if($i~/bytes_sent:/){gsub("bytes_sent:","",$i); s+=$i}} /^$/{f=0} END{print s+0}')
sleep 8
b2=$(ss -tin | awk '/<远端IP>/{f=1} f&&/bytes_sent/{for(i=1;i<=NF;i++) if($i~/bytes_sent:/){gsub("bytes_sent:","",$i); s+=$i}} /^$/{f=0} END{print s+0}')
echo "$(( (b2-b1)/8/1024 )) KB/s"   # 0 或个位数 = 包体没进 socket
```

解法：摘掉全部 proxy 变量走直连（clash 可以继续开着，只是别让 git 走它）：

```bash
env -u http_proxy -u https_proxy -u all_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NODE_USE_ENV_PROXY \
  git -c http.lowSpeedLimit=20000 -c http.lowSpeedTime=60 push --progress origin HEAD:master
```

实测直连后稳定 **117 KiB/s**、18MB 级约 2.5 分钟**属正常速度，耐心等完**；`--progress` 必须加，否则非 TTY 下看不到进度。已实测证伪的四条别再查（HTTP/2 分块、`postBuffer` 太小、服务端拒收、仓库太大）。另：`-c http.version=HTTP/1.0` 走不通——git-lfs 的 pre-push 钩子会直接报 Unknown HTTP version 并让整条 push 失败。

## 5. 合并独立历史（网盘快照 → 正式仓库）

```bash
git clone ~/GitServer/X.git work      # bare 无 HEAD 时 checkout 失败
git checkout -b master origin/master  # 手动建本地分支
git remote add snapshot <快照路径>
git fetch snapshot
git merge snapshot/main --allow-unrelated-histories
# 冲突取正式版：git checkout --ours <文件> && git add -A && git commit
```

## 6. gitignore 模板（提交前必查）

- **UE**：`Binaries/ DerivedDataCache/ Intermediate/ Saved/ Build/ .vs/ .vscode/ .idea/ *.sln *.suo`
- **Unity**：`Library/ Temp/ Logs/ obj/ .vs/ .idea/ UserSettings/`

漏掉 UE 生成物目录 = 几十 GB 进 git（实测有 54GB 案例）。提交前核对 `git status --porcelain | wc -l` 数量是否合理。

## 7. 验证与删本体

```bash
# 注意：--git-dir= 后面的 ~ 不会被 bash 展开，必须用 $HOME
git --git-dir="$HOME/GitServer/X.git" fsck --strict   # 无输出=通过
git status --porcelain | wc -l                       # 0 = 干净
rm -rf <本体>                                         # 用户确认后
```

## 注意事项

- **删除前三个确认**：工作区干净 + `fsck` 通过 + 双推完成（本地 + 远端两份备份）。活跃开发项目删本体前先问用户；多备份项目（同名快照）按用户规则先不动。
- `fsck` 那条命令必须用 `$HOME` 而不是 `~`（bash 不展开 `--git-dir=` 后面的 `~`）。
- 顺序策略（滚动释放）：先提交停开发项目（bare 小）→ 删本体腾空间 → 再提交活跃大项目。
- 实测（2026-08-13）：XianXia LFS 4026 对象 / bare 3.4GB / 本体 65.5GB 删；HydroVault2 LFS 19305 对象；YRS LFS 4681 对象 7.8GB。Windows 侧对应写法见 SKILL.md 的 PowerShell 小节（`I:\GitServer`）。
