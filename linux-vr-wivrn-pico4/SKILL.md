---
name: linux-vr-wivrn-pico4
description: Linux 下做 VR 并把画面串流到 PICO 4 的完整落地栈（WiVRn + Monado + UE5.8 源码引擎 + 纯 OpenXR）。触发词：Linux VR、串流到 PICO/Quest、WiVRn、Monado、UE Linux OpenXR、Pico 无线 adb、VR 开发环境、xrEndFrame LAYER_INVALID、headset 串流。
---

# Linux VR 开发与 PICO 4 串流（WiVRn 路线，2026-10-23 实测通）

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
