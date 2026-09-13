---
name: alvr-connection-troubleshoot
description: ALVR 无法发现/连接 VR 头显（PICO/Quest）时的完整排查与修复流程：mDNS 发现架构、日志定位、版本匹配、adb 孤儿 socket 处理
---

# ALVR 连接故障排查（服务端 Windows/Linux + PICO/Quest 客户端）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

适用：ALVR 无法发现/连接头显、握手失败、SteamVR 起不来。原排查全在 Windows 侧（本机安装路径 `~\Apps\alvr_launcher_windows\installations\<版本>\`）；Linux 侧见各步的「Linux（bash）」子节——**本机 Linux 侧尚未装 ALVR/SteamVR**（实测：`pacman -Q alvr` 未安装、无 SteamVR，只有 steam 客户端），所以 Linux 命令标「待验证」的条目是按发行渠道与平台惯例给出的，需实测确认；已核实的发行渠道是 `archlinuxcn/alvr 20.14.1-1`（本机已启用 archlinuxcn）与 AUR `alvr`/`alvr-bin`/`alvr-launcher-bin`/`alvr-git`。

## 连接架构（先懂再查）

- 发现走 **mDNS**：头显客户端广播 `_alvr._tcp.local.`，PC 端 ALVR 核心（**跑在 vrserver 进程内**，不是 Dashboard）浏览并**主动 TCP 外连**头显的 9943（控制）/9944（流）。
- PC 无 9943/9944 入站监听是**正常**的——监听在头显侧。
- Dashboard 通过 127.0.0.1:8082（核心 web server，vrserver 持有）与核心通信；Dashboard 卡死时表现为对 8082 反复 SYN_SENT。
- SteamVR 待机（entering standby）不影响 mDNS 发现。
- Linux 上 mDNS 由 **avahi** 提供：本机 avahi **已装但 inactive + disabled**（实测），要用先 `sudo systemctl enable --now avahi-daemon`。ALVR Linux 版是否依赖系统 avahi 还是自带 mDNS 实现——**待验证**。

## 排查顺序

1. **进程**：ALVR Dashboard、steam（已登录）、vrserver 都在跑。
2. **驱动注册**：`vrpathreg show` 应有 `alvr_server → <安装目录>`。
3. **Dashboard↔核心**：查 Dashboard 进程到 8082 的连接，应有 ESTABLISHED；只有 SYN_SENT = 卡死，杀 Dashboard 重启。
4. **核心 API**：`http://127.0.0.1:8082/api/version` 带 header `X-ALVR: true` 请求，200 即核心活着。
5. **日志**（安装目录下）：见下「日志判据（两平台相同）」。
6. **网络**：PC 与头显同网段；ping 头显 IP；直接 TCP 测 `头显IP:9943`（OPEN=客户端在听，REFUSED=设备在线但 app 没开，timeout=设备不在线）。

### Linux（bash）
```bash
pgrep -af -i 'alvr|vrserver|steam'        # 1. 进程（Linux Dashboard 二进制名待验证，可能叫 alvr_dashboard）

# 2. 驱动注册（SteamVR on Linux 提供的是 shell 脚本；SteamVR 未装，路径待验证）
~/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh show
ls -d ~/.local/share/Steam/steamapps/common/SteamVR/bin/vrpathreg.sh   # 另一常见前缀

ss -tnp | grep -E ':8082'                 # 3. ESTABLISHED = 正常；只有 SYN-SENT = 卡死

curl -sS -o /dev/null -w '%{http_code}\n' -H 'X-ALVR: true' http://127.0.0.1:8082/api/version   # 4. 200 即核心活着
# 注意：bash 工具按内容拦截 HTTP 命令，curl 可能被拦；被拦时改用 ctx_execute 沙箱或 hub

ping -c 4 <头显IP>                         # 6.
nc -vz <头显IP> 9943                       # 直接 TCP 测；本机 nc 在 /usr/bin/nc
```

### Windows（PowerShell）

1. **进程**：ALVR Dashboard、steam（已登录）、vrserver 都在跑。
2. **驱动注册**：应有 `alvr_server → <安装目录>`：
   ```powershell
   SteamVR\bin\win64\vrpathreg.exe show
   ```
3. **Dashboard↔核心**：应有到 8082 的 ESTABLISHED；只有 SYN_SENT = 卡死，杀 Dashboard 重启。
   ```powershell
   Get-NetTCPConnection -OwningProcess <dashboard_pid>
   ```
4. **核心 API**：`fetch http://127.0.0.1:8082/api/version` 带 header `X-ALVR: true`，200 即核心活着。
5. **日志**（安装目录下）：见「日志判据（两平台相同）」。
6. **网络**：PC 与头显同网段；ping 头显 IP；直接 TCP 测 `头显IP:9943`（OPEN=客户端在听，REFUSED=设备在线但 app 没开，timeout=设备不在线）。

### 日志判据（两平台相同）
- `crash_log.txt`：握手错误。`os error 10053`（主机中止已建立连接）= **客户端/服务端版本不匹配**（nightly 服务端必须配同 tag nightly 客户端 APK；商店稳定版连不上 nightly）。
  —— `10053` 是 Windows 的 WSAECONNABORTED；Linux 上是 errno 103/104 一类的 ECONNABORTED/ECONNRESET，**Linux 侧的确切错误文本待验证**，判据（版本不匹配）相同。
- `session_log.txt`：需 session.json 设 `extra.logging.log_to_disk=true`。`Could not initiate connection for xxx.client.local: connection timed out` 每秒重复 = 发现正常但头显不在线（旧 mDNS 幽灵，无害）。

## 陷阱

- **adb 孤儿 socket**：强杀 vrserver 后，ALVR 拉起的 adb 子进程继承持有 27062/8082/5353 socket → 下次 SteamVR 启动报 `Failed to start server with error 146`（27062 bind 10048）。**重启 SteamVR 前必须先杀 adb**；还卡住就顺藤摸瓜杀持有 27062 的进程。
  - Linux（bash）：`pkill -x adb`；查谁占 27062：`ss -tlnp | grep 27062`。（`error 146` / 10048 是 Windows 侧文本，Linux 侧对应报错**待验证**。）
  - Windows（PowerShell）：`Stop-Process -Name adb -Force`，再按上面的错误码顺藤摸瓜。
  - adb 来源：Windows 在 scoop shim；Linux 装 `sudo pacman -S android-tools`（本机当前**未装** adb，实测验过 `command -v adb` 为空）。
- 改 session.json 前必须停 Dashboard + vrserver（运行时会被内存配置覆盖）；`openvr_config` 顶层段是驱动快照不要手改。
- `session.json` 不是 Dashboard 单独创建的——核心（vrserver 驱动）启动时才生成。

## 版本不匹配的修复

1. 从同 tag nightly release 下 `alvr_client_android.apk`（`https://api.github.com/repos/alvr-org/ALVR-nightly/releases/tags/<tag>` 取 browser_download_url，ghfast.top 前缀加速，核对 size）。两平台同一份 APK。
2. 装到头显：无线 adb（开发者模式开无线调试 → `adb connect <ip>:5555` → `adb install xxx.apk`）/ USB 线 adb / 头显文件管理器直装。
   - adb 来源：Windows 在 scoop shim；Linux `sudo pacman -S android-tools`（本机未装）。两平台 `adb connect` / `adb install` 命令相同。
3. session.json 开 `connection.client_discovery.content.auto_trust_clients=true` 可免点 Trust 自动连。
