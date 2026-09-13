---
name: aliyunpan-cli-setup-login
description: 安装/登录 tickstep/aliyunpan（阿里云盘 CLI）：scoop 无包需手动装、资产名 windows-x64、ghfast 镜像 + aria2、login 必须 pty 长驻（stdin EOF 会秒退报登录失败）、授权后按 Enter
---

# aliyunpan (阿里云盘 CLI) 安装与登录

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

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
