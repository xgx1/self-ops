---
name: baidupcs-cli
description: 使用百度网盘 CLI（BaiduPCS-Go）时查阅：安装（Linux pacman / Windows scoop）、BDUSS 与 Cookie 登录、自动化扫码登录（含弹窗/抓图陷阱）、下载落盘结构、GBK 编码坑、命令速查、非 SVIP 并发限制、秒传已失效、备份档案窥探等实测教训
---

# BaiduPCS-Go CLI 使用教训

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

百度网盘命令行客户端（qjfoidnh fork，Windows 侧 scoop 装的是 v4.0.1）。以下教训区分「实测确认」与「[INFERENCE] 社区经验」；命令速查与下载/限速结论两平台通用，安装、登录态位置与扫码出图分平台。

## 安装（实测）

### Linux（bash）

Arch 官方仓库**自带**该包，不需要 scoop（本机无 scoop）：

```bash
sudo pacman -S baidupcs-go      # extra/baidupcs-go 4.0.2-1（qjfoidnh fork，本机实测在库）
pacman -Ql baidupcs-go | grep bin/   # 装完核对二进制名
```

二进制名**待验证**：上游 Go 项目产物叫 `BaiduPCS-Go`（连字符），Arch 包名是 `baidupcs-go`，装完用上面那条 `pacman -Ql` 看实际落地的可执行文件名再敲命令。

备选：`go install github.com/qjfoidnh/BaiduPCS-Go@latest`（本机未装 go），或从 release 下 `BaiduPCS-Go-v4.0.1-linux-amd64.zip` 解压。

### Windows（PowerShell）

- CLI：`scoop install lemon/baidupcs-go`（dorado 无此包；lemon、scoopet 均有 4.0.1）
- GUI 客户端：`scoop install scoopet/baidunetdisk`（8.6.8.102；post_install 报 `$TEMP` 删不掉是已知无害噪音）
- shim 名是 `BaiduPCS-Go`（连字符；不是 `baidupcs`）
- scoop persist 持久化了 `config`（登录态/配置）和 `Downloads`（默认下载目录 savedir），重装不丢登录
- Linux 侧没有 scoop、没有 shim 层，也没有 `scoopet/baidunetdisk` 那种 GUI 包（Linux 版百度网盘 GUI **待验证**；CLI 侧不受影响）

## 命令速查（实测）

两平台二进制同名，下列命令 Linux/Windows 通敲：

```bash
BaiduPCS-Go -v                    # 查版本。version 子命令不存在，报“未找到命令”
BaiduPCS-Go login                 # 交互式登录
BaiduPCS-Go login -bduss=xx -stoken=yy   # BDUSS+STOKEN 登录
BaiduPCS-Go login -cookies="BDUSS=..; BAIDUID=..; STOKEN=.."  # 整串 Cookie
BaiduPCS-Go who / loglist / su    # 当前账号 / 账号列表 / 切换账号
BaiduPCS-Go ls / cd / pwd / tree
BaiduPCS-Go download, d [--test 测试不落盘] [--ow 覆盖]
BaiduPCS-Go upload, u <本地> <网盘目录>
BaiduPCS-Go locate, lt            # 下载直链
BaiduPCS-Go share / transfer      # 分享 / 转存
BaiduPCS-Go offlinedl, od         # 离线下载
BaiduPCS-Go quota / search / rm / mv / cp / mkdir / meta / recycle
BaiduPCS-Go config / config set -名=值
```

## 登录（实测）

- 三种方式：交互式（按提示）、`-bduss`+`-stoken`、`-cookies` 整串
- BDUSS 获取：Chrome 登录 pan.baidu.com → F12 → Network → 刷新 → 复制 Cookie 里的 BDUSS/STOKEN；或直接 Application → Cookies
- 登录态存配置目录：Windows 在 scoop persist 的 `config`；Linux 跟 XDG 走（**待验证**具体路径，先跑 `BaiduPCS-Go config` 看它打印的"配置保存目录"）
- 多账号用 `loglist`/`su` 管理
- **登录态会过期**：报 `代码: 31045 user not exists` / `loglist` 为空就是要重登，走下方扫码流程

### 自动化扫码登录（实测成功路径）

OMP browser 工具是 headless 隐藏浏览器，用户看不到窗口无法直接扫码。可用流程：

1. `browser open https://pan.baidu.com`，点「去登录」出扫码弹窗（aria 快照里 button "去登录"）
2. 二维码元素是 `img.tang-pass-qrcode-img`（285×285），src 是 `passport.baidu.com/v2/api/qrcode?sign=...`；刚点开时 src 是 loading.gif，要 `page.waitForFunction` 等 src 含 `qrcode?sign=`
3. 全页截图发给用户会糊、扫不出——**必须局部截二维码元素或抓原图**，再放大 3~4 倍（NearestNeighbor，别用平滑插值）给用户扫：
   - 抓图用 run 作用域的 Node `fetch(src)` 写盘；**不要 `page.goto(二维码src)`**——会摧毁登录弹窗状态（导航回去后 QR img 元素没了，得重新点登录）

   #### Linux（bash）
   ```bash
   magick qr.png -filter point -resize 400% qr_big.png   # 本机 imagemagick 7.1，-filter point = 最近邻
   xdg-open qr_big.png                                    # 交给默认图片查看器，用户扫码
   ```

   #### Windows（PowerShell）
   ```powershell
   # 原实现：PowerShell System.Drawing，以 NearestNeighbor 插值放大 3~4 倍（脚本未存留，按此要点写即可）
   # 打开图片给用户：Start-Process 走默认图片关联可能无弹窗（Win11 照片应用关联异常，实测踩过）。稳妥用法：
   Start-Process rundll32 -ArgumentList '"C:\Program Files\Windows Photo Viewer\PhotoViewer.dll", ImageView_Fullscreen <图路径>' -PassThru
   # 1.5s 后查 HasExited，已退出再回落 msedge.exe <图路径>
   ```

4. run 里循环 `page.cookies()` 轮询 `BDUSS` 出现（2s/次，超时 170s），扫码确认后拿到 BDUSS+STOKEN
5. `BaiduPCS-Go login -bduss=.. -stoken=..` → `who` 验证。**BDUSS 含 `$` 字符，bash 里必须单引号包裹**（两平台同样：单引号/字面量传入，别让 shell 展开）
6. 收尾：`browser close`、删临时二维码图（Linux `rm qr.png qr_big.png`）

注意：`STOKEN` 在 pan.baidu.com 域的 cookie 里也能拿到；二维码有效期几分钟。

## 下载/搜索行为（实测）

- **落盘目录是 `savedir\<uid>_<用户名>\`**，不是 savedir 根。例：Windows savedir 设 `D:\Downloads`，实际落在 `D:\Downloads\1712471085_xxx\`；Linux 同理，savedir 设 `~/Downloads` 则落在 `~/Downloads/1712471085_xxx/`
- `search` 只匹配文件名（不搜目录名、不搜内容），`-r` 递归，`--path=/` 全盘；`-l` 详细模式列为：序号/FS ID/APP ID/大小/创建时间/修改时间/MD5/路径
- 下载日志里 `Unsolicited response received on idle HTTP channel` 是无害噪音，不影响结果
- SVIP 账号实测单文件 ~13MB/s（max_parallel=1 默认值下）
- **SVIP 双文件并发实测（2026-08-03）**：`max_parallel=8` + `max_download_load=2`，两分卷并行合计 ~40MB/s（单流 27+13），117.6GB 约 50 分钟
- 长时间下载用 `hub start` 挂后台 + `ready.log` 匹配「下载」确认启动，比 bash 前台等稳
- **下载的文本文件可能是 GBK 编码**，`cat` 报 “stream did not contain valid UTF-8”，用 `iconv -f GBK -t UTF-8` 读（bash 直接可用）
- 大文件下载 SB 线程后速度会从 ~13MB/s 降到 ~3MB/s（百度限速），重启下载可临时恢复
- **抗限速实测（SVIP，117.6GB/10 分卷）**：`max_parallel=8` + `max_download_load=2` 双车道，每连接传 ~2GB 后被限到 1-2MB/s；杀掉进程重启即可恢复 20-30MB/s，断点续传零损失（部分分卷从 .BaiduPCS-Go-downloading 续传）。全程重启 1 次，46 分钟下完，平均 ~45MB/s

### 搜索/发现浏览器/用户数据（实测）

`search` 对找浏览器密码数据不高效——Login Data、Cookies 等关键词不匹配文件名。有效方法：
1. `ls /根目录` 找可疑备份目录（`/Backup`、`/Data`、`/Sync`、`/wechat` 等）
2. 下最小 Part（如 Part1.tar.zst，1.5GB），用 `tar -tf` 窥内容探头
3. 看顶层目录：`.ssh/`、`.bash_history`、`AppData/`、`.config/` 是 Linux 用户目录；`Windows/`、`用户/` 是 Windows 备份
4. Chrome Login Data 存于 `AppData/Local/Google/Chrome/User Data/Default/Login Data`（SQLite），**但 Linux Chrome 密码用 GNOME Keyring/kwallet 加密，无原机密钥不可解**
5. 确认有用再下全部（如 /Backup 10 parts 共 26.9GB）

## 限速与并发（实测 config 建议值）

- `max_parallel` 默认 1，官方帮助原话“非svip不可>1”——非 SVIP 账号调高并发无效/被限；SVIP 账号（quota >2TB 可判）可 `config set -max_parallel=8` + `-max_download_load=2`
- 下载慢先调 `cache_size`（默认 64KB，可 1KB~256KB）
- `pan_ua` 默认伪装安卓官方客户端 11.12.3，勿乱改，改了可能被风控
- `upload_policy` 默认 `skip`（重名跳过），要覆盖用 `overwrite`，同步语义用 `rsync`

## 已失效/坑（实测）

- **秒传已失效**：`sumfile` 帮助明写“目前秒传功能已失效”，不要依赖秒传脚本
- 原版 iikira/BaiduPCS-Go 已停更，4.x 是 qjfoidnh fork 延续，issue 提到 fork 仓库

## [INFERENCE] 社区经验（未实测，使用时留意）

- 第三方 PCS 接口有账号限速/封禁风险，重要数据操作建议用小号
- 高频/大批量操作易触发风控，必要时 `config set -proxy=` 或降速
- `locate` 直链有时效，需配合 pan_ua 一致才能 200

## 新教训追加

遇到新坑直接更新本文件对应章节；实测过的放「实测」区，道听途说标 [INFERENCE]。
