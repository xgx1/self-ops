---
name: vr-and-aliyunpan-setup
description: 本机 VR 串流环境与云盘 CLI 的搭建、配置与排障一本通：① Linux 下 VR 串流到 PICO/Quest（WiVRn + Monado + UE5.8 源码引擎 + 纯 OpenXR）；② 本机 ALVR（alvr_launcher）串流配置编辑（session.json、Dashboard 覆盖陷阱、低画质键位）；③ ALVR 无法发现/连接头显的完整排查（mDNS 架构、日志定位、版本匹配、adb 孤儿 socket）；④ 阿里云盘 CLI（tickstep/aliyunpan）安装与登录（scoop 无包手装、ghfast 镜像 + aria2、pty 长驻登录）。触发词：Linux VR、串流到 PICO、串流到 Quest、WiVRn、Monado、UE Linux OpenXR、Pico 无线 adb、VR 开发环境、xrEndFrame LAYER_INVALID、headset 串流、ALVR、session.json、阿里云盘、aliyunpan、阿里云盘登录。
---

# vr-and-aliyunpan-setup

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

## Linux VR 串流到 PICO 4（WiVRn + Monado + UE5.8）

目标：Linux 上跑 VR 应用（UE5.8 源码引擎 / 任意 OpenXR 程序），无线串流到头显，纯 OpenXR，不依赖 SteamVR。

## 一、结论先给

- 选 **WiVRn**（Pico 4 官方支持 ✓，Linux 原生，Monado 内建）；ALVR Linux 仅 experimental。
- UE5.8 **确实支持 Linux OpenXR**，走 Vulkan：证据 `Engine/Plugins/Runtime/OpenXR/Source/OpenXRHMD/OpenXRHMD.Build.cs:89-99`（Linux 平台组加 `OPENXRHMD_HAVE_VULKAN`）、`OpenXRHMDModule.cpp:456-466`（载入 `libopenxr_loader.so`），loader 实存于 `Engine/Binaries/ThirdParty/OpenXR/linux/x86_64-unknown-linux-gnu/`。
- PICO 插件（PICOXR / PICOOpenXR）只有 Android/Windows 实现，Linux 上必须禁用，走纯 OpenXR。

## 二、一次性安装（Arch）

```bash
yay -S --noconfirm --needed wivrn-dashboard   # 拉起 wivrn-server + 内建 monado
sudo pacman -S --noconfirm avahi              # wivrn 依赖 avahi 客户端，daemon 需另装齐
sudo systemctl enable --now avahi-daemon
systemctl --user enable --now wivrn           # 常驻，广播 <hostname>._wivrn._tcp
```

- 防火墙开 5353/udp（Avahi）与 9757/udp+tcp（WiVRn）。本机无 firewalld/ufw，免配。
- 排查 Avahi 装歪：`pacman -Qkk avahi` 报 `/usr/lib/systemd/system/avahi-daemon.service 没有那个文件` 说明包内文件丢失但 DB 仍认——`sudo pacman -Sy --noconfirm avahi` 重装（实测 0.9rc5-1 → 0.9rc5-2 修好）。

## 三、OpenXR runtime 注册（最容易踩的坑）

本机 loader 只认 `~/.config/openxr/1/active_runtime.json`，**不认** `~/.local/share/openxr/1/`。WiVRn 断连时会清掉自己写的 active runtime，于是应用报 `xrEnumerateInstanceExtensionProperties failed, suggests no runtime is installed`。

```bash
mkdir -p ~/.config/openxr/1
cat > ~/.config/openxr/1/active_runtime.json <<'EOF'
{
  "file_format_version": "1.0.0",
  "runtime": {
    "name": "WiVRn",
    "library_path": "/usr/lib/wivrn/libopenxr_wivrn.so",
    "MND_libmonado_path": "/usr/lib/wivrn/libmonado_wivrn.so"
  }
}
EOF
```

更稳的做法：启动应用时直接钉死（不依赖被清理的 active runtime）：

```bash
export XR_RUNTIME_JSON=/usr/share/openxr/1/openxr_wivrn.json
```

验证：`xrgears`（AUR `xrgears-git`）能列出扩展并起 session 即通。

## 四、头显侧

- 客户端 APK 必须与服务端**同版本**：`https://github.com/WiVRn/WiVRn/releases/download/v26.9/WiVRn-release.apk`。
- 安装后包名是 `org.meumeu.wivrn.github`（不是 `org.meumeu.wivrn`），启动 activity `org.meumeu.wivrn.MainActivity`。
- **首启「欢迎使用 WiVRn / 是否启用麦克风？」对话框只能用手柄扳机点**：`adb shell input tap|keyevent` 对 native OpenXR app 完全无效（实测 tap 全分辨率 4320x2160 坐标、keyevent 66/23、pm grant/revoke RECORD_AUDIO 均无效）。必须请人戴头显点一次，之后不再出现。
- 服务器列表页点「连接」同样要手柄；WiVRn 已配对的头显在客户端被杀后会回列表页，需再点一次。
- adb：`adb shell svc power stayon true` 防睡；电量低于 ~15% 会被系统降频甚至关机，长期调试要接电。

## 五、UE5.8（Linux 源码引擎）配置

最小可跑工程（Blueprint-only，无需编译模块）：

```ini
; Config/DefaultEngine.ini
[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Engine/Maps/Templates/VR-Basic

[/Script/LinuxTargetPlatform.LinuxTargetSettings]
DefaultGraphicsRHI=DefaultGraphicsRHI_Vulkan

[ConsoleVariables]
xr.OpenXRAcquireMode=1            ; 换 acquire 顺序，消掉大部分首帧 LAYER_INVALID
xr.OpenXRAllowDepthLayer=0        ; Monado 无 depth layer 支持时别提交
vr.OpenXRSwapchainRetryCount=100  ; 头显挂起时 10s 容限，避免 WaitCurrentImage Fatal
```

启动（`-game` 跑蓝图工程，不必 cook）：

```bash
export WAYLAND_DISPLAY=wayland-1 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000
export XR_RUNTIME_JSON=/usr/share/openxr/1/openxr_wivrn.json
UnrealEditor MyGame.uproject -game -vr -vulkan -windowed -nosplash -stdout -abslog=/tmp/ue-xr.log
```

## 六、坑表（都实测过）

| 现象 | 原因 | 处置 |
|---|---|---|
| `xrEndFrame ... XR_ERROR_LAYER_INVALID`（伴随 `Attempted to release image 0 ... wasn't ready for being written to`） | UE 首帧 release 被跳过（`OpenXRHMD_Swapchain.cpp:97-105` 的 ImageReady=false 分支 return），仍提交该层；Monado 校验严格 | `xr.OpenXRAcquireMode=1` 后多数消失；偶发 1 次不致命（UE 继续出帧）。根治=在 `ImageReady==false` 时按 `layerCount=0` 提交空帧 |
| `Fatal: Failed to wait on acquired swapchain image` | 头显未佩戴被 PICO 挂起 3D 应用，帧停超过 10×100ms | 调大 `vr.OpenXRSwapchainRetryCount`；测试时保持佩戴/供电 |
| `suggests no runtime is installed` | active_runtime.json 位置错或被 WiVRn 清掉 | 见第三节 |
| `XR_ERROR_SESSION_LOST` | 重启 wivrn-server/daemon-reload | 正常，重连即可 |
| 客户端连不上 | APK 与服务端版本不一致 / Avahi 没起 / 不在同网段 | 核对版本 tag、`systemctl is-active avahi-daemon`、同网段 |
| adb 多设备 | USB + TCP 同时在 | 一律 `adb -s <serial|ip:5555>` |
| 拔 USB 后无线 adb 断 | 未开 tcpip | 插一次 USB 跑 `adb tcpip 5555` + `adb connect <ip>:5555`；或头显「开发者选项 → 无线调试」用配对码 `adb pair` |

## 七、验证与观测配方

```bash
adb -s <ip>:5555 exec-out screencap -p > /tmp/vr.png   # 头显画面（未佩戴时只出亚透视，UI 抓不到）
journalctl --user -u wivrn -f                          # 连接/帧流
systemctl --user show wivrn -p Environment             # 确认 XRT_LOG=debug 是否生效
wivrnctl list-paired; wivrnctl pair -d unlimited       # 配对管理
```

- 想要 Monado 校验原文：给单元加 drop-in `Environment=XRT_LOG=debug`，`systemctl --user daemon-reload && systemctl --user restart wivrn`。注意 Monado 跑在**应用进程内**（`libmonado_wivrn.so`），所以它的日志落在应用 stdout/stderr，而不是 wivrn-server 的 journal——找 `XR_ERROR_*` 原文去应用日志。
- GPU 编码：AMD 走 VAAPI（本机 RX 7900 GRE，`vainfo` 见 H264 EncSlice）。

## 七点五、无头跑 UE 自动化测试（本项目实测）

```bash
UnrealEditor-Cmd <proj>.uproject -unattended -NullRHI -nohmd -nosplash \
  -ExecCmds="Automation RunTests <Filter>" \
  -testexit="Automation Test Queue Empty" -log -stdout
```

- **必须加 `-nohmd`**：项目 `bStartInVR=True` 时，NullRHI 下 OpenXR 初始化会吐一串 `LogAutomationTest: Error: Condition failed`，automation 根本不启动。加 `-nohmd` 后测试正常（`Test Completed. Result={Success}`）。
- 用 `UnrealEditor-Cmd`；`-ExecCmds` 里不要带 `Quit`（会先退出、测试没跑），靠 `-testexit` 收尾。
- 那 13 条 `Condition failed` 在 `-nohmd` 后仍可能出现于启动早期，与测试结果无关，看 `LogAutomationController` 的 `Result={Success|Fail}` 为准。

## 八、不要做

- 别装 Monado 独立包（wivrn-server 已内建 monado，另装会版本打架）。
- 别用 `adb input` 试图操作 WiVRn 客户端 UI。
- 别指望重启 wivrn 后 UE 能自动恢复会话——UE 会 `XR_ERROR_SESSION_LOST` 退出，需重跑。

## ALVR 串流配置编辑

## 路径
- 安装目录：`C:\Users\Admin\Apps\alvr_launcher_windows\installations\<版本号>\`（launcher 版，版本目录会变，用 `Get-Process *ALVR* | Select Path` 或 ls installations 定位）
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

## ALVR 连接排查与修复

适用：ALVR 无法发现/连接头显、握手失败、SteamVR 起不来。本机安装路径 `C:\Users\Admin\Apps\alvr_launcher_windows\installations\<版本>\`。

## 连接架构（先懂再查）

- 发现走 **mDNS**：头显客户端广播 `_alvr._tcp.local.`，PC 端 ALVR 核心（**跑在 vrserver 进程内**，不是 Dashboard）浏览并**主动 TCP 外连**头显的 9943（控制）/9944（流）。
- PC 无 9943/9944 入站监听是**正常**的——监听在头显侧。
- Dashboard 通过 127.0.0.1:8082（核心 web server，vrserver 持有）与核心通信；Dashboard 卡死时表现为对 8082 反复 SYN_SENT。
- SteamVR 待机（entering standby）不影响 mDNS 发现。

## 排查顺序

1. **进程**：ALVR Dashboard、steam（已登录）、vrserver 都在跑。
2. **驱动注册**：`SteamVR\bin\win64\vrpathreg.exe show` 应有 `alvr_server → <安装目录>`。
3. **Dashboard↔核心**：`Get-NetTCPConnection -OwningProcess <dashboard_pid>` 应有到 8082 的 ESTABLISHED；只有 SYN_SENT = 卡死，杀 Dashboard 重启。
4. **核心 API**：`fetch http://127.0.0.1:8082/api/version` 带 header `X-ALVR: true`，200 即核心活着。
5. **日志**（安装目录下）：
   - `crash_log.txt`：握手错误。`os error 10053`（主机中止已建立连接）= **客户端/服务端版本不匹配**（nightly 服务端必须配同 tag nightly 客户端 APK；商店稳定版连不上 nightly）。
   - `session_log.txt`：需 session.json 设 `extra.logging.log_to_disk=true`。`Could not initiate connection for xxx.client.local: connection timed out` 每秒重复 = 发现正常但头显不在线（旧 mDNS 幽灵，无害）。
6. **网络**：PC 与头显同网段；ping 头显 IP；直接 TCP 测 `头显IP:9943`（OPEN=客户端在听，REFUSED=设备在线但 app 没开，timeout=设备不在线）。

## 陷阱

- **adb 孤儿 socket**：强杀 vrserver 后，ALVR 拉起的 adb.exe 子进程继承持有 27062/8082/5353 socket → 下次 SteamVR 启动报 `Failed to start server with error 146`（27062 bind 10048）。**重启 SteamVR 前必须先杀 adb.exe**；还卡住就顺藤摸瓜杀持有 27062 的进程。
- 改 session.json 前必须停 Dashboard + vrserver（运行时会被内存配置覆盖）；`openvr_config` 顶层段是驱动快照不要手改。
- `session.json` 不是 Dashboard 单独创建的——核心（vrserver 驱动）启动时才生成。

## 版本不匹配的修复

1. 从同 tag nightly release 下 `alvr_client_android.apk`（`https://api.github.com/repos/alvr-org/ALVR-nightly/releases/tags/<tag>` 取 browser_download_url，ghfast.top 前缀加速，核对 size）。
2. 装到头显：无线 adb（开发者模式开无线调试 → `adb connect <ip>:5555` → `adb install xxx.apk`）/ USB 线 adb / 头显文件管理器直装。adb 在 scoop shim。
3. session.json 开 `connection.client_discovery.content.auto_trust_clients=true` 可免点 Trust 自动连。

## 阿里云盘 CLI 安装与登录

tickstep/aliyunpan —— 阿里云盘官方无 CLI，社区最活跃客户端。Windows 侧本机装于 `~\Apps\aliyunpan\`（v0.4.0，用户 PATH 已加）。

## 安装（两边都没有官方包仓库的现成入口）

### Linux（bash）

Arch 官方仓库（core/extra/multilib/archlinuxcn）**没有** aliyunpan；AUR 有现成包，实测查询结果：`aliyunpan-go-bin 0.4.0-1`（tickstep/aliyunpan 预编译版，provides `aliyunpan-go`）与 `aliyunpan-go 0.4.0-1`（同版本源码构建）——与本机 Windows 侧 pin 的 v0.4.0 同版：

```bash
yay -S aliyunpan-go-bin          # 首选：预编译，快
# 或 yay -S aliyunpan-go         # 源码构建，同版本
aliyunpan -v                     # 装完核对版本
```

要手动装（流程与 Windows 侧同套，只是资产名不同）：

1. 查最新版：`read https://api.github.com/repos/tickstep/aliyunpan/releases/latest`
2. **资产名分平台**：Windows 是 `aliyunpan-vX.Y.Z-windows-x64.zip`，Linux 是 `aliyunpan-vX.Y.Z-linux-amd64.zip`（Linux 侧才是 amd64）—— **Linux 资产名待验证**（本机未实际下过，按上游 Linux 发行命名推断；下 404 就照 release 页面实际文件名改）
3. 下载走 ghfast.top 镜像 + aria2（GitHub 直连慢）：
   ```bash
   aria2c -x16 -s16 -d "$TMPDIR" -o aliyunpan.zip "https://ghfast.top/https://github.com/tickstep/aliyunpan/releases/download/vX.Y.Z/aliyunpan-vX.Y.Z-linux-amd64.zip"
   ```
4. 解压到 `~/Apps/aliyunpan/`，内层目录上移，加 PATH（写进 `~/.bashrc`：`export PATH="$HOME/Apps/aliyunpan:$PATH"`）

### Windows（PowerShell）

scoop 无此包，需手动装：

1. 查最新版：`read https://api.github.com/repos/tickstep/aliyunpan/releases/latest`
2. **资产名是 `aliyunpan-vX.Y.Z-windows-x64.zip`（不是 amd64！）**，写错 404
3. 下载走 ghfast.top 镜像 + aria2（GitHub 直连慢）：
   ```powershell
   aria2c -x16 -s16 -d %TEMP% -o aliyunpan.zip "https://ghfast.top/https://github.com/tickstep/aliyunpan/releases/download/vX.Y.Z/aliyunpan-vX.Y.Z-windows-x64.zip"
   ```
4. 解压到 `~/Apps/aliyunpan/`，内层目录上移，加用户 PATH

## 登录（坑多）

**login 命令在非 TTY（管道 stdin）下会秒退：打印授权链接后 5 秒报"登录失败，请稍后尝试重新登录"** —— 实际是 stdin EOF 导致程序退出，不是网络/服务器问题（api.tickstep.com 可达性正常）。两平台同样踩，必须给 pty。

正确流程：

1. **必须 pty 长驻**：`hub start` 起 login（pty=true），ready 匹配"请在浏览器打开以下链接"
   - Linux：程序名 `aliyunpan` → `aliyunpan login`
   - Windows：程序名 `aliyunpan.exe` → `aliyunpan.exe login`
2. 从 logs 拿授权链接，打开浏览器给用户
   - Linux：`xdg-open "<授权链接>"`
   - Windows：`Start-Process "<授权链接>"`
3. **每次 login 生成新设备码，必须打开本次链接**（授权旧链接无效）
4. 用户在浏览器：登录账号 → 授权 → 再扫码一次（两次登录）
5. 用户完成后 `hub send` 一个空格（按 Enter），logs 应显示 `阿里云盘登录成功: <昵称>`
6. 停进程，之后直接 `aliyunpan ls`（凭据已存 aliyunpan_config.json，无需再登录）

## 常用命令

- `aliyunpan ls` / `upload` / `download`
- 无参数运行进交互 shell（`aliyunpan >` 提示符）
- 配置目录可用环境变量 `ALIYUNPAN_CONFIG_DIR` 改：
  ```bash
  export ALIYUNPAN_CONFIG_DIR=~/Apps/aliyunpan/config     # Linux
  ```
  ```powershell
  $env:ALIYUNPAN_CONFIG_DIR = "$env:USERPROFILE\Apps\aliyunpan\config"   # Windows
  ```
- 单账户最多 10 台设备，超限需在手机端下线

## 其他候选（非 CLI，勿混淆）

- `aliyundrive-webdav`（Windows 在 scoop main/lemon）= WebDAV 挂载。Linux 侧包名**待验证**，先 `yay -Ss aliyundrive-webdav` 查，或从上游 release 取二进制
- `alist`（Windows 在 scoop main）= 网盘聚合服务。Linux 侧**待验证**，先 `yay -Ss alist` 查（Arch 官方仓库无此名，实测搜索无匹配）
- `aliyun`（Windows 在 scoop main）= 阿里云**云计算** CLI（AccessKey 登录），不是网盘。Linux 侧用官方安装脚本/二进制，同样别拿它当网盘客户端
