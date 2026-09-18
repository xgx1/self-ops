# 阿里云盘 CLI（aliyunpan）安装与登录

> 装 tickstep/aliyunpan 并跑通扫码登录，避开「scoop 根本没有这个包」和「login 在非 TTY 下秒退、报登录失败」两个坑。

## 什么时候用

- 要在 Linux（Arch）或 Windows 上装阿里云盘 CLI `aliyunpan`（官方没出 CLI，这是社区最活跃客户端）。
- `aliyunpan login` 打印授权链接后约 5 秒报「登录失败，请稍后尝试重新登录」——这是 stdin EOF，不是网络/服务器问题。
- 要分清 `aliyundrive-webdav` / `alist` / `aliyun` 是不是同一个东西（都不是网盘 CLI）。

## 怎么用

AUR 有现成包，与本机 Windows 侧 pin 的 v0.4.0 同版：

```bash
yay -S aliyunpan-go-bin          # 首选：预编译，快
# 或 yay -S aliyunpan-go         # 源码构建，同版本
aliyunpan -v                     # 装完核对版本
```

手动装：先从 `https://api.github.com/repos/tickstep/aliyunpan/releases/latest` 查最新版，下载走 ghfast.top 镜像 + aria2（GitHub 直连慢）：

```bash
aria2c -x16 -s16 -d "$TMPDIR" -o aliyunpan.zip "https://ghfast.top/https://github.com/tickstep/aliyunpan/releases/download/vX.Y.Z/aliyunpan-vX.Y.Z-linux-amd64.zip"
```

解压到 `~/Apps/aliyunpan/`、把内层目录上移，再把 `export PATH="$HOME/Apps/aliyunpan:$PATH"` 写进 `~/.bashrc`。

Windows：scoop 无此包，同样手动装，但资产名是 `aliyunpan-vX.Y.Z-windows-x64.zip`（**不是 amd64**，写错 404）。

## 登录：必须给 pty，且要长驻

1. 用 `hub start` 起 `aliyunpan login`（pty=true），ready 匹配「请在浏览器打开以下链接」。Windows 程序名是 `aliyunpan.exe login`。
2. 从 logs 取授权链接打开：Linux `xdg-open "<授权链接>"`；Windows `Start-Process "<授权链接>"`。
3. 用户在浏览器里登录账号 → 授权 → 再扫码一次（**两遍登录**）。
4. 用户完成后 `hub send` 一个空格（等于按 Enter），logs 应出现 `阿里云盘登录成功: <昵称>`。
5. 停掉进程。凭据已写入 `aliyunpan_config.json`，之后直接 `aliyunpan ls`，不用再登录。

## 常用命令

```bash
aliyunpan ls                      # 列目录；upload / download 同理
aliyunpan                         # 无参数进交互 shell（aliyunpan > 提示符）
export ALIYUNPAN_CONFIG_DIR=~/Apps/aliyunpan/config     # 改配置目录
```

```powershell
$env:ALIYUNPAN_CONFIG_DIR = "$env:USERPROFILE\Apps\aliyunpan\config"   # Windows
```

## 注意事项

- **每次 login 都生成新设备码，必须打开本次链接**，授权旧链接无效。
- 单账户最多 10 台设备，超限要在手机端下线。
- Linux 资产名 `linux-amd64.zip` 在 SKILL.md 里标注为**待验证**（按上游命名推断），404 就照 release 页面实际文件名改。
- 别混淆：`aliyundrive-webdav` = WebDAV 挂载、`alist` = 网盘聚合服务、`aliyun` = 阿里云**云计算** CLI（AccessKey 登录）。三者在 Linux 侧的包名 SKILL.md 也都标注待验证，先 `yay -Ss <名字>` 查。
