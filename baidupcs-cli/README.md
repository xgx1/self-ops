# BaiduPCS-Go 使用手册（安装 / 登录 / 下载 / 限速）

> 百度网盘 CLI（qjfoidnh fork）的安装、登录（含 headless 自动化扫码）、下载落盘与限速调优，全部来自实测。

## 什么时候用

- 要装/登录 `BaiduPCS-Go`，或登录态过期（报 `代码: 31045 user not exists`、`loglist` 为空）。
- 查命令、找下载落盘位置、调并发/缓存、用搜索发现网盘里的备份档案。
- 大批量下载 + 按规则处理的编排，另见技能 `baidupcs-batch-pipeline`。

## 安装

```bash
sudo pacman -S baidupcs-go      # Arch extra/baidupcs-go 4.0.2-1（qjfoidnh fork，本机实测在库）
pacman -Ql baidupcs-go | grep bin/   # 装完核对二进制名
```

Windows：`scoop install lemon/baidupcs-go`（shim 名是 `BaiduPCS-Go`，不是 `baidupcs`；dorado 无此包），GUI 可选 `scoop install scoopet/baidunetdisk`。

## 命令速查（两平台二进制同名，通敲）

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

## 自动化扫码登录（headless 浏览器场景，实测成功路径）

1. `browser open https://pan.baidu.com`，点「去登录」出扫码弹窗；二维码元素是 `img.tang-pass-qrcode-img`（285×285），src 为 `passport.baidu.com/v2/api/qrcode?sign=...`，刚点开时是 loading.gif，要等 src 含 `qrcode?sign=`。
2. **全页截图会糊、扫不出**——必须局部截二维码元素或抓原图，再放大 3~4 倍（最近邻插值，别用平滑）。抓图用 run 作用域的 Node `fetch(src)` 写盘；**不要 `page.goto(二维码src)`**，会摧毁登录弹窗状态。

```bash
magick qr.png -filter point -resize 400% qr_big.png   # -filter point = 最近邻
xdg-open qr_big.png                                    # 交给默认图片查看器，用户扫码
```

3. 轮询 `page.cookies()` 等 `BDUSS` 出现（2s/次，超时 170s），扫码确认后拿到 BDUSS+STOKEN。
4. `BaiduPCS-Go login -bduss=.. -stoken=..` 后 `who` 验证。**BDUSS 含 `$` 字符，shell 里必须单引号/字面量传入**。收尾：`browser close`、删临时二维码图。
   Windows 打开图片用 `Start-Process rundll32 -ArgumentList '"C:\Program Files\Windows Photo Viewer\PhotoViewer.dll", ImageView_Fullscreen <图路径>' -PassThru`，1.5s 后查 `HasExited`，已退出再回落 msedge。

## 下载 / 限速（实测）

- 落盘目录是 `savedir\<uid>_<用户名>\`，**不是 savedir 根**。
- `max_parallel` 默认 1；非 SVIP 调高无效（官方帮助原话「非svip不可>1」）。SVIP（quota >2TB 可判）可 `config set -max_parallel=8` + `-max_download_load=2`，实测双文件并发合计 ~40MB/s。
- 被限速（掉到 1-3MB/s）杀掉进程重启即恢复 20-30MB/s，断点续传零损失；下载慢先调 `cache_size`（默认 64KB，可 1KB~256KB）；`pan_ua` 勿乱改（改了可能被风控）。
- `upload_policy` 默认 `skip`（重名跳过），覆盖用 `overwrite`，同步语义用 `rsync`。

## 注意事项 / 已知坑

- **秒传已失效**（`sumfile` 帮助明写「目前秒传功能已失效」），别依赖秒传脚本；原版 iikira/BaiduPCS-Go 已停更，4.x 是 qjfoidnh fork 延续。
- `search` 只匹配文件名（不搜目录名、不搜内容），`-r` 递归，`--path=/` 全盘。
- 下载日志 `Unsolicited response received on idle HTTP channel` 是无害噪音。
- 下载的文本文件可能是 GBK：`cat` 报 stream did not contain valid UTF-8 时用 `iconv -f GBK -t UTF-8` 读。
- `locate` 直链有时效，需配合 `pan_ua` 一致才能 200。
- 找备份档案的高效路径：`ls /根目录` 找 `/Backup`、`/Data`、`/Sync`、`/wechat` → 下最小 Part 用 `tar -tf` 窥内容 → 确认有用再下全部。Linux Chrome 密码用 GNOME Keyring/kwallet 加密，**无原机密钥不可解**。
- `[INFERENCE]`（社区经验，未实测）：第三方 PCS 接口有账号限速/封禁风险，重要操作建议用小号；高频大批量易触发风控。
- 遇到新坑直接更新 SKILL.md 对应章节：实测的放「实测」区，道听途说标 `[INFERENCE]`。
