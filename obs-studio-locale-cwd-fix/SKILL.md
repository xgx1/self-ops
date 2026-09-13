---
name: obs-studio-locale-cwd-fix
description: "Windows 上 OBS Studio 启动报 \"Failed to find locale/en-US.ini\"、便携模式失效、或 scoop 版清配置后无法启动时的根因与修复流程。触发词：OBS 报错、locale 找不到、便携模式、obs64 启动失败。"
---

# OBS Studio locale / 便携模式排障

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

本技能的坑位全部来自 **Windows + scoop 便携布局**；Linux 侧发行版包没有便携/ persist 机制，对应小节给出 Arch 的做法。

本机 Linux 实测（写本文时核对）：`extra/obs-studio 32.2.2-1`，可执行文件 `/usr/bin/obs`，locale 在 `/usr/share/obs/obs-studio/locale/en-US.ini`，配置在 `~/.config/obs-studio/`。

## 根因（官方缺陷，obsproject/obs-studio#2966）

OBS 32.x（含 scoop extras 版）在 **Windows 便携布局下**用**相对当前工作目录**解析资源路径：
- locale 加载：`locale/en-US.ini`（相对 cwd）
- 便携检测（`frontend/obs-main.cpp` 1066 行）：`BASE_PATH = "../.."`（Windows，相对 cwd），检测 `portable_mode.txt` / `obs_portable_mode.txt` 等

从非 exe 目录启动（bash 直接敲路径、脚本 Start-Process 不带 WorkingDirectory）→ 报 "Failed to find locale/en-US.ini" → 点掉后 "Failed to load locale" → 退出码 -1。

官方明确"不支持从任意工作目录启动"。**必须从 `bin/64bit/` 作为工作目录启动**。快捷方式把 "Start in" 设为 exe 目录即可（scoop 建的快捷方式默认正确）。

### Linux（bash）

Linux 发行版包由打包者固定资源路径，**启动不依赖 cwd**（locale 在 `/usr/share/obs/obs-studio/locale/`，见下），本技能的"相对 cwd 解析"坑不适用。

```bash
sudo pacman -S obs-studio          # 本机已装：extra/obs-studio 32.2.2-1
obs                                # 直接启动，无需关心 cwd
pacman -Ql obs-studio | grep 'locale/en-US.ini$'   # 核对 locale 文件归属与路径
```

Linux 上仍报 locale 找不到时的排查方向（**待验证**，本机未复现该错误）：先用上面那条 `pacman -Ql` 确认 locale 文件在位；再查是否被自定义启动脚本/包装器覆写了 `OBS_DATA_PATH` 类的环境变量。本机**没有装 flatpak**；若走 flatpak（沙箱自带资源，同样不依赖 cwd），先 `sudo pacman -S flatpak` 再 `flatpak install flathub com.obsproject.Studio`，其配置在 `~/.var/app/com.obsproject.Studio/config/obs-studio/`。

## scoop 便携版布局（persist）

Windows 专属布局；Linux 无对应（发行版包把 `data/`、`obs-plugins/` 装在 `/usr/share/obs/`，配置写 `~/.config/obs-studio/`，没有 persist，也没有 junction）。

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

只删 config 下的 `obs-studio/`（或整个 config 内容），OBS 下次启动自动重建默认配置。

#### Linux（bash）

Linux 上对应的是用户配置目录（发行版包与 flatpak 都叫 `obs-studio/`）：

```bash
rm -rf ~/.config/obs-studio          # 重置"所有设置"；下次启动自动重建
# flatpak 版在沙箱内：rm -rf ~/.var/app/com.obsproject.Studio/config/obs-studio
```

保留：locale 与插件是**包文件**（`/usr/share/obs/`），不要手工删——删了用 `sudo pacman -S --force obs-studio` 恢复（见下节）。

#### Windows（PowerShell）

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\scoop\persist\obs-studio\config\obs-studio"
```

保留：`data/`（locale 在里面，删了必报 "Failed to find locale/en-US.ini"）、`obs-plugins/`（插件）、`portable_mode.txt`（删了 OBS 转 APPDATA 模式）。

### 误删 data/ 后的修复（重装）

locale 在 persist 的 data 里，删掉后启动必报 locale 错。

#### Linux（bash）

Linux 上 locale 是**包文件**、不是用户数据，没有"连 persist 一起重装"这回事；误删用包管理器重放：

```bash
sudo pacman -Qkk obs-studio          # 先校验哪些文件缺失/被改
sudo pacman -S --force obs-studio    # 重放全部包文件（不动用户配置）
```

#### Windows（PowerShell）

必须连 persist 一起重装：

```powershell
scoop uninstall obs-studio -p   # -p 连 persist 一起删，否则旧 persist 残留仍缺 locale
scoop install obs-studio        # 自动重建 config/data/obs-plugins/portable_mode.txt
```

**`scoop reinstall` 不行**——persist 已存在时不重建，locale 仍然缺失，必须先 uninstall -p。

### 定位与验证

#### Linux（bash）

1. cwd 无关性自测：`cd /tmp && obs` 应正常启动（发行版包不依赖 cwd）—— **待验证**（本机未复现 locale 错，未实测）
2. 看实际进程与它的 cwd：`pgrep -x obs` 拿到 PID 后 `ls -l /proc/<pid>/cwd`
3. 验证成功：`pgrep -x obs` 进程存活 >10s，且配置目录有写入 —— `ls -l --time-style=full-iso ~/.config/obs-studio/`
4. 坑：Linux 上别去找 `%APPDATA%\obs-studio`——配置在 `~/.config/obs-studio/`（flatpak 在 `~/.var/app/...`）

#### Windows（PowerShell）

1. locale 报错但文件在 → 查启动方式 cwd，用 `Start-Process obs64.exe -WorkingDirectory "…\bin\64bit"`（Git Bash 直接执行 exe 报 command not found，用 Start-Process 或 `cmd //c start`）
2. 便携检测失败 → 确认 cwd 正确（便携检测也是相对 cwd），应用根 portable_mode.txt 存在即可，**不要**往 bin/64bit 复制标记（多余）
3. 验证：进程存活 >10s + `persist/config/obs-studio` 新建（便携）即为成功：`Start-Process …\bin\64bit\obs64.exe` 后 `tasklist | findstr obs64`
4. 坑：别用 `%APPDATA%\obs-studio` 找配置——便携模式它不存在

## MSYS/Git Bash 假象坑（Windows 专属）

scoop 的 junction/symlink 链（current→版本目录→persist）在 Git Bash 下解析不稳定：
- `ls`/`rm` 报 "No such file or directory" 但文件真实存在（`cd` 进目录后正常）
- 判断文件存在性、删除文件**必须用 PowerShell**：`Test-Path` / `Remove-Item`
- 排查时优先 `pwsh -NoProfile -Command` 而非 bash 内建

Linux 上无对应方案：本坑的成因是 **scoop junction + MSYS 路径翻译**；Arch 上的 OBS 是普通包文件加 `~/.config` 目录，没有 junction 链，`ls`/`rm` 与文件系统行为一致。可替代做法：在 Linux 上不要用 Windows 那套路径，直接按上面的 bash 小节操作。
