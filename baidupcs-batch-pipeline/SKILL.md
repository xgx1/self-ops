---
name: baidupcs-batch-pipeline
description: 百度网盘 BaiduPCS-Go 分批下载+按规则处理的多盘流水线：递归侦查、空间守卫、hub daemon 三步重启、zstd/格式坑、下载处理串行、询问文档模式
---

# 百度网盘分批下载+处理流水线（多盘 / 多挂载点）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

标题里的 D/E/I 是 **Windows 盘符**；Linux 侧把每个"盘"换成挂载点（如 `/mnt/d`、`/run/media/<user>/<label>`）或独立目录即可，规则本身不变。

适用于 BaiduPCS-Go 大批量下载并按规则处理的批次作业。配套事实教训见长期记忆（baidupcs-cli 相关 learn 条目）。

## 0. 前置：递归侦查（必做，浅层"总"行会撒谎）

`BaiduPCS-Go ls /目录` 的"总： X GB"只算浅层文件。实测：/传输 标 2.79GB 实际 ~80GB、客户项目 标 25.57GB 实际 310GB。**任何下载决策前逐子目录 ls 求和**，脚本循环解析 `总:` 行即可。深目录树（文件多/层深）download 会挂起枚举（实测 /New 挂 30 分钟无输出）——先 ls 看子目录数，深树拆逐子目录下。

## 1. 空间预算

- 每盘留 10GB 底（用户规则），预算 = free - 10GB
- 下载脚本每个文件前插守卫（守卫值 = 底 + 单文件余量）
- 转码类管线同样守卫目标盘（产物 ≈ 源大小，ABR 转码不省空间）
- 应急腾空间：网盘可重下的内容回收站无价值

### Linux（bash）
```bash
# 守卫：可用空间 < 15GB 就退出（$TARGET = 目标挂载点或目录）
avail_gb=$(df -BG --output=avail "$TARGET" | tail -1 | tr -dc '0-9')
[ "$avail_gb" -lt 15 ] && { echo "空间不足: ${avail_gb}GB"; exit 1; }

# 应急腾空间：命令行 rm 即删（Linux 无"回收站"概念）；要清空桌面回收站：
gio trash --empty                     # 或：rm -rf ~/.local/share/Trash/{files,info}/*
```

### Windows（PowerShell）
```powershell
if ((Get-PSDrive E).Free/1GB -lt 15) { exit }
Clear-RecycleBin -DriveLetter X -Force
```

## 2. daemon 生命周期（hub）

- 长下载/转码用 `hub start` 挂后台（pty=false），ready.log 匹配 "=== /"；脚本种类随平台变：Linux 跑 `bash script.sh`，Windows 跑 `pwsh -NoProfile -File script.ps1`
- **重启必须三步**：`hub stop` → **杀掉 BaiduPCS-Go 进程** → `hub start`。hub stop/restart 只杀脚本宿主进程，baidupcs-go 子进程孤儿续跑
- 看到两个 BaiduPCS-Go 进程先查 CommandLine：Windows 上是 scoop shim（`shims\baidupcs-go.exe`）+ 真身（`apps\current\BaiduPCS-Go.exe`）的父子对 = 单下载，勿误判；Linux 侧没有 scoop shim 层，用下面的 `pgrep`/`ps` 看
- 限流（1-2MB/s）恢复 = 完整三步重启（断点续传零损失）；只 hub restart 无效（孤儿占连接）

### Linux（bash）
```bash
pgrep -af BaiduPCS-Go                 # 看进程与命令行（含父子关系）
pkill -x BaiduPCS-Go                  # 杀掉；确认走完再 hub start
```

### Windows（PowerShell）
```powershell
Stop-Process BaiduPCS-Go -Force
```

## 3. 文件格式坑

- `.mp4.zst`/`.mkv.zst` = 纯 zstd 流 → 用 `7z x`。Linux 装 `sudo pacman -S 7zip`（本机已装 `extra/7zip 26.03`）；Windows 是 scoop 装的 7zip。Win11 自带 `tar.exe` 报 "Unrecognized archive format"
- `.tar.zst` 才能 `tar -xf`
- 转码验证阈值别用绝对值：小文件产物 <100MB 合法，用 `>1MB` + exit 0
- 下载失败的 0B 文件会被当"已存在"跳过——重下前删 0B + `*.BaiduPCS-Go-downloading` 残留

### Linux（bash）
```bash
find <下载目录> -type f -size 0 -delete
find <下载目录> -type f -name '*.BaiduPCS-Go-downloading' -delete
```

### Windows（PowerShell）
```powershell
Get-ChildItem -Recurse -File <下载目录> | Where-Object { $_.Length -eq 0 } | Remove-Item -Force
Get-ChildItem -Recurse -File -Filter '*.BaiduPCS-Go-downloading' <下载目录> | Remove-Item -Force
```

## 4. 处理与下载必须串行

baidupcs-go 按本地文件存在性判断完成。**下载中的目录树不要移动/归档任何文件**，否则触发重下（实测快照目录被归档后整目录重下）。先下完整个目录，再处理。

## 5. 询问文档模式

- 有规则的按规则立即处理；无规则/超预算的写「处理询问文档」（编号 C1/C2...，每项给方案选项），等用户逐条回复
  - Windows 路径：`D:\处理询问.md`
  - Linux 路径：`~/处理询问.md`（放用户主目录，别放下载目标盘，避免被空间守卫波及）
- 每批结束更新文档尾部"处理进度"段：完成项、空间现况（各盘 free）、卡点原因
  - Linux 看各盘 free：`df -h <挂载点1> <挂载点2>`
  - Windows：`Get-PSDrive -PSProvider FileSystem | Select-Object Name,@{n='FreeGB';e={[math]::Round($_.Free/1GB,1)}}`
- 数字必须实测核对后再写进文档（不猜）

## 6. 脚本纪律

### Linux（bash）
- 脚本逻辑写 `.sh` 文件用 `bash script.sh` 跑；长内联命令里引号/变量展开容易翻车，同样别内联
- 文件按 UTF-8 存即可，Linux 没有代码页问题

### Windows（PowerShell）
- PowerShell 逻辑一律写 .ps1 文件跑；bash 内联 `$var`/`$_` 会被 bash 展开/历史展开破坏
- 生成脚本内含中文时注意 powershell 5.1 -File 按 ANSI 读无 BOM 文件会炸引号——生成内容尽量 ASCII，或写 BOM
