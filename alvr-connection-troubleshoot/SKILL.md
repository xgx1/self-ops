---
name: alvr-connection-troubleshoot
description: ALVR 无法发现/连接 VR 头显（PICO/Quest）时的完整排查与修复流程：mDNS 发现架构、日志定位、版本匹配、adb 孤儿 socket 处理
---

# ALVR 连接故障排查（Windows 服务端 + PICO/Quest 客户端）

适用：ALVR 无法发现/连接头显、握手失败、SteamVR 起不来。本机安装路径 `~\Apps\alvr_launcher_windows\installations\<版本>\`。

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
