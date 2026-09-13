---
name: aliyunpan-cli-setup-login
description: 安装/登录 tickstep/aliyunpan（阿里云盘 CLI）：scoop 无包需手动装、资产名 windows-x64、ghfast 镜像 + aria2、login 必须 pty 长驻（stdin EOF 会秒退报登录失败）、授权后按 Enter
---

# aliyunpan (阿里云盘 CLI) 安装与登录

tickstep/aliyunpan —— 阿里云盘官方无 CLI，社区最活跃客户端。本机装于 `~\Apps\aliyunpan\`（v0.4.0，用户 PATH 已加）。

## 安装（scoop 无此包）

1. 查最新版：`read https://api.github.com/repos/tickstep/aliyunpan/releases/latest`
2. **资产名是 `aliyunpan-vX.Y.Z-windows-x64.zip`（不是 amd64！）**，写错 404
3. 下载走 ghfast.top 镜像 + aria2（GitHub 直连慢）：
   ```
   aria2c -x16 -s16 -d %TEMP% -o aliyunpan.zip "https://ghfast.top/https://github.com/tickstep/aliyunpan/releases/download/vX.Y.Z/aliyunpan-vX.Y.Z-windows-x64.zip"
   ```
4. 解压到 `~/Apps/aliyunpan/`，内层目录上移，加用户 PATH

## 登录（坑多）

**login 命令在非 TTY（管道 stdin）下会秒退：打印授权链接后 5 秒报"登录失败，请稍后尝试重新登录"** —— 实际是 stdin EOF 导致程序退出，不是网络/服务器问题（api.tickstep.com 可达性正常）。

正确流程：

1. **必须 pty 长驻**：`hub start` 起 `aliyunpan.exe login`（pty=true），ready 匹配"请在浏览器打开以下链接"
2. 从 logs 拿授权链接，`Start-Process` 打开浏览器给用户
3. **每次 login 生成新设备码，必须打开本次链接**（授权旧链接无效）
4. 用户在浏览器：登录账号 → 授权 → 再扫码一次（两次登录）
5. 用户完成后 `hub send` 一个空格（按 Enter），logs 应显示 `阿里云盘登录成功: <昵称>`
6. 停进程，之后直接 `aliyunpan ls`（凭据已存 aliyunpan_config.json，无需再登录）

## 常用命令

- `aliyunpan ls` / `upload` / `download`
- 无参数运行进交互 shell（`aliyunpan >` 提示符）
- 配置目录可用环境变量 `ALIYUNPAN_CONFIG_DIR` 改
- 单账户最多 10 台设备，超限需在手机端下线

## 其他候选（非 CLI，勿混淆）

- `aliyundrive-webdav`（scoop main/lemon）= WebDAV 挂载
- `alist`（scoop main）= 网盘聚合服务
- `aliyun`（scoop main）= 阿里云**云计算** CLI（AccessKey 登录），不是网盘
