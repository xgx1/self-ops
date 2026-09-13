---
name: alvr-config-edit
description: 修改本机 ALVR（alvr_launcher 安装版）串流配置：session.json 直接编辑流程、Dashboard 覆盖陷阱、低画质/低带宽关键键位
---

# ALVR session.json 直接编辑流程

## 路径
- 安装目录：`~\Apps\alvr_launcher_windows\installations\<版本号>\`（launcher 版，版本目录会变，用 `Get-Process *ALVR* | Select Path` 或 ls installations 定位）
- 配置：同目录 `session.json`
- 主程序：`ALVR Dashboard.exe`

## 流程（顺序不能乱）
1. **先杀 Dashboard**：`powershell -NoProfile -Command 'Get-Process | Where-Object {$_.Name -like "*ALVR*"} | Stop-Process -Force'`
   ——Dashboard 退出/重启时会用内存配置覆盖 session.json，不杀进程改文件会被吞。
2. 用 edit 工具改 session.json（JSON 文本编辑即可）。
3. 校验：`Get-Content ... -Raw | ConvertFrom-Json | Out-Null`，输出 JSON OK 再继续。
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
