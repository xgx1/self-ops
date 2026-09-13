---
name: obs-studio-locale-cwd-fix
description: "Windows 上 OBS Studio 启动报 \"Failed to find locale/en-US.ini\"、便携模式失效、或 scoop 版清配置后无法启动时的根因与修复流程。触发词：OBS 报错、locale 找不到、便携模式、obs64 启动失败。"
---

# OBS Studio locale / 便携模式排障

## 根因（官方缺陷，obsproject/obs-studio#2966）

OBS 32.x（含 scoop extras 版）用**相对当前工作目录**解析资源路径：
- locale 加载：`locale/en-US.ini`（相对 cwd）
- 便携检测（`frontend/obs-main.cpp` 1066 行）：`BASE_PATH = "../.."`（Windows，相对 cwd），检测 `portable_mode.txt` / `obs_portable_mode.txt` 等

从非 exe 目录启动（bash 直接敲路径、脚本 Start-Process 不带 WorkingDirectory）→ 报 "Failed to find locale/en-US.ini" → 点掉后 "Failed to load locale" → 退出码 -1。

官方明确"不支持从任意工作目录启动"。**必须从 `bin/64bit/` 作为工作目录启动**。快捷方式把 "Start in" 设为 exe 目录即可（scoop 建的快捷方式默认正确）。

## scoop 便携版布局（persist）

```
persist/obs-studio/
├── config/            # 全部设置（global.ini、basic/ 场景、logs/…）
├── data/              # 程序数据，含 data/obs-studio/locale/en-US.ini ← 删了必报 locale 错
├── obs-plugins/       # 插件
└── portable_mode.txt  # 便携标记（0B，scoop persist 复制到应用根）
```

- 应用目录 `apps/obs-studio/32.x.x/` 下 config/data/obs-plugins 是 **JUNCTION** 指向 persist
- 便携检测命中条件：cwd = bin/64bit 时 `../../portable_mode.txt` = 应用根标记 → 便携生效，配置写 persist；否则非便携，配置写 `%APPDATA%\obs-studio`
- 判断实际模式：启动后看 `persist/config/obs-studio` 是否新建（便携）vs `%APPDATA%\obs-studio` 时间戳更新（非便携）

## 修复流程

### 安全清除范围（重置"所有设置"）

只删 `persist/obs-studio/config/obs-studio/`（或整个 config 内容），OBS 下次启动自动重建默认配置：

```bash
rm -rf /c/Users/<user>/scoop/persist/obs-studio/config/obs-studio
```

保留：`data/`（locale 在里面，删了必报 "Failed to find locale/en-US.ini"）、`obs-plugins/`（插件）、`portable_mode.txt`（删了 OBS 转 APPDATA 模式）。

### 误删 data/ 后的修复（重装）

locale 在 persist 的 data 里，删掉后启动必报 locale 错。必须连 persist 一起重装：

```powershell
scoop uninstall obs-studio -p   # -p 连 persist 一起删，否则旧 persist 残留仍缺 locale
scoop install obs-studio        # 自动重建 config/data/obs-plugins/portable_mode.txt
```

**`scoop reinstall` 不行**——persist 已存在时不重建，locale 仍然缺失，必须先 uninstall -p。

### 定位与验证

1. locale 报错但文件在 → 查启动方式 cwd，用 `Start-Process obs64.exe -WorkingDirectory "…\bin\64bit"`（Git Bash 直接执行 exe 报 command not found，用 Start-Process 或 `cmd //c start`）
2. 便携检测失败 → 确认 cwd 正确（便携检测也是相对 cwd），应用根 portable_mode.txt 存在即可，**不要**往 bin/64bit 复制标记（多余）
3. 验证：进程存活 >10s + `persist/config/obs-studio` 新建（便携）即为成功：`Start-Process …\bin\64bit\obs64.exe` 后 `tasklist | findstr obs64`
4. 坑：别用 `%APPDATA%\obs-studio` 找配置——便携模式它不存在

## MSYS/Git Bash 假象坑

scoop 的 junction/symlink 链（current→版本目录→persist）在 Git Bash 下解析不稳定：
- `ls`/`rm` 报 "No such file or directory" 但文件真实存在（`cd` 进目录后正常）
- 判断文件存在性、删除文件**必须用 PowerShell**：`Test-Path` / `Remove-Item`
- 排查时优先 `pwsh -NoProfile -Command` 而非 bash 内建
