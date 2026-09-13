---
name: alvr-config-edit
description: 修改本机 ALVR（alvr_launcher 安装版）串流配置：session.json 直接编辑流程、Dashboard 覆盖陷阱、低画质/低带宽关键键位
---

# ALVR session.json 直接编辑流程

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

## 路径

### Linux（bash）

本机 Linux 侧**尚未安装** ALVR（实测 `pacman -Q alvr` 未安装，`~/.local/share/alvr_launcher` 不存在；SteamVR 也没装，机上有 steam 客户端但无 SteamVR），以下路径与二进制名标**待验证**——已核实的是发行渠道：Arch `archlinuxcn/alvr 20.14.1-1`（本机 `/etc/pacman.conf` 已启用 archlinuxcn），AUR 另有 `alvr` / `alvr-bin` / `alvr-launcher-bin` / `alvr-git`。

```bash
sudo pacman -S alvr                    # archlinuxcn 仓库
# 或 yay -S alvr-bin / alvr-launcher-bin（AUR）

# 装完先定位，不要照抄路径：
find ~ -maxdepth 6 -name session.json 2>/dev/null      # 配置（launcher 版一般在 installations/<版本>/ 下，待验证）
pgrep -af -i alvr                                       # 主程序：Linux 版 Dashboard 二进制名待验证（可能叫 alvr_dashboard）
ls ~/.local/share/alvr_launcher/installations/ 2>/dev/null   # launcher 数据目录，路径待验证
```

### Windows（PowerShell）

- 安装目录：`~\Apps\alvr_launcher_windows\installations\<版本号>\`（launcher 版，版本目录会变，用 `Get-Process *ALVR* | Select Path` 或 ls installations 定位）
- 配置：同目录 `session.json`
- 主程序：`ALVR Dashboard.exe`

## 流程（顺序不能乱）

### Linux（bash）

1. **先杀 Dashboard**：先 `pgrep -af -i alvr` 确认进程名，再 `pkill -f -i alvr`
   ——Dashboard 退出/重启时会用内存配置覆盖 session.json，不杀进程改文件会被吞。
2. 用 edit 工具改 session.json（JSON 文本编辑即可）。
3. 校验：
   ```bash
   python3 -m json.tool session.json > /dev/null && echo "JSON OK"    # 或：jq empty session.json && echo "JSON OK"
   ```
   输出 JSON OK 再继续。
4. 重启 Dashboard（launcher 或 `alvr_dashboard`，名字待验证），配置生效。

### Windows（PowerShell）

1. **先杀 Dashboard**：
   ```powershell
   powershell -NoProfile -Command 'Get-Process | Where-Object {$_.Name -like "*ALVR*"} | Stop-Process -Force'
   ```
   ——Dashboard 退出/重启时会用内存配置覆盖 session.json，不杀进程改文件会被吞。
2. 用 edit 工具改 session.json（JSON 文本编辑即可）。
3. 校验：
   ```powershell
   Get-Content <session.json 路径> -Raw | ConvertFrom-Json | Out-Null
   ```
   输出 JSON OK 再继续。
4. `Start-Process` 重启 Dashboard，配置生效。

## 只改 session_settings，别碰 openvr_config
顶层 `openvr_config` 是驱动侧快照，由 Dashboard 从 `session_settings` 重新生成，手改无效。

## 低画质/低带宽关键键（session_settings.video）
|键|低配值|说明|
|---|---|---|
|bitrate.mode.ConstantMbps|15|CBR 恒定码率，带宽/延迟减半；出色块再升 20|
|transcoding_view_resolution.Absolute|width 1280, height.content 896|渲染分辨率；与 emulated_headset_view_resolution 文本相同，两处一起改（edit all:true）|
|emulated_headset_view_resolution.Absolute|同上|报给 SteamVR 的分辨率，决定游戏渲染负载|
|preferred_fps|60.0|VR 舒适下限，不建议再低|
|foveated_encoding.content|center_size 0.5/0.5, edge_ratio 10|注视点编码，中心清晰区越小、边缘压缩比越大越省码率|
|preferred_codec|H264|RX 7900 GRE (AMF) 上开销最低；配 quality_preset Speed + entropy_coding Cavlc|

## 备注
- 游戏内仍卡是 SteamVR 游戏自身渲染开销，ALVR 侧已无能为力，去游戏内画质设置降。
- 本机 GPU：AMD RX 7900 GRE。
- 这套键位来自 Windows + AMF 实测（H264/AMF 的结论绑定那块卡）；Linux 侧走 VAAPI/Vulkan 编码，键位含义相同但「开销最低的 codec」**待验证**，先按 H264 试。
