# 百度网盘分批下载 + 按规则处理流水线

> 用 BaiduPCS-Go 做多盘/多挂载点的大批量下载：先侦查真实体积、守卫磁盘空间、按规则处理，无规则的写进询问文档等用户裁决。

## 什么时候用

- 一次要下几十上百 GB，且分布在同一块盘的多个「盘符」/挂载点上。
- 要判断浅层「总：X GB」可不可信、下载限流怎么恢复、`.zst` 怎么解。
- 下载和后续处理（转码/归档/移动）需要按顺序编排时。

## 怎么用（SKILL.md 的 0~6 节）

### 0. 递归侦查（必做，浅层「总」行会撒谎）

`BaiduPCS-Go ls /目录` 的「总：X GB」只算浅层文件——实测 /传输 标 2.79GB 实际 ~80GB、客户项目 标 25.57GB 实际 310GB。**任何下载决策前逐子目录 ls 求和**（脚本循环解析 `总:` 行即可）。深目录树 download 会挂起枚举（实测 /New 挂 30 分钟无输出）：先看子目录数，深树拆开逐子目录下。

### 1. 空间预算：每盘留 10GB 底

```bash
# 守卫：可用空间 < 15GB 就退出（$TARGET = 目标挂载点或目录）
avail_gb=$(df -BG --output=avail "$TARGET" | tail -1 | tr -dc '0-9')
[ "$avail_gb" -lt 15 ] && { echo "空间不足: ${avail_gb}GB"; exit 1; }

# 应急腾空间：命令行 rm 即删（Linux 无"回收站"概念）；要清空桌面回收站：
gio trash --empty                     # 或：rm -rf ~/.local/share/Trash/{files,info}/*
```

下载脚本每个文件前都插同样的守卫；转码类管线也要守卫目标盘（产物 ≈ 源大小，ABR 转码不省空间）。

### 2. daemon 生命周期：重启必须三步

`hub stop` → **杀掉 BaiduPCS-Go 进程** → `hub start`。只 `hub restart` 无效——hub 只杀脚本宿主进程，baidupcs-go 子进程会孤儿续跑占着连接（停不下来的限流就是这么来的）。

```bash
pgrep -af BaiduPCS-Go                 # 看进程与命令行（含父子关系）
pkill -x BaiduPCS-Go                  # 杀掉；确认走完再 hub start
```

### 3. 文件格式与残留

- `.mp4.zst` / `.mkv.zst` 是纯 zstd 流 → 用 `7z x`（Linux 装 `sudo pacman -S 7zip`）；Win11 自带 `tar.exe` 会报 Unrecognized archive format。
- 只有 `.tar.zst` 才能 `tar -xf`。
- 下载失败的 0B 文件会被当成「已存在」跳过，重下前先清：

```bash
find <下载目录> -type f -size 0 -delete
find <下载目录> -type f -name '*.BaiduPCS-Go-downloading' -delete
```

### 4. 下载与处理必须串行

baidupcs-go 按本地文件是否存在判断完成。**下载中的目录树不要移动/归档任何文件**，否则触发整目录重下（实测快照目录被归档后整目录重下）。先下完整个目录，再处理。

### 5. 询问文档

有规则的立即处理；无规则/超预算的写「处理询问文档」（编号 C1/C2…，每项给方案选项）等用户逐条回复。Linux 路径 `~/处理询问.md`，Windows `D:\处理询问.md`（别放下载目标盘，避免被空间守卫波及）。每批结束更新尾部「处理进度」：完成项、各盘 free、卡点原因。

```bash
df -h <挂载点1> <挂载点2>          # Linux 看各盘 free
```

### 6. 脚本纪律

逻辑写文件跑（Linux `.sh` 用 `bash script.sh`），别长内联——引号/变量展开容易翻车。Linux 文件按 UTF-8 存即可，没有代码页问题。

## 前置条件

- 已安装并登录 BaiduPCS-Go（见技能 `baidupcs-cli`）。
- `7z`（Linux `extra/7zip`，本机已装）与 `hub` 工具。
- Windows 对应写法：`(Get-PSDrive E).Free/1GB -lt 15` 判空间、`Clear-RecycleBin -DriveLetter X -Force`、`Stop-Process BaiduPCS-Go -Force`。

## 注意事项

- 标题里的 D/E/I 是 **Windows 盘符**；Linux 把每个「盘」换成挂载点或独立目录，规则本身不变。
- 转码验证阈值别用绝对值：小文件产物 <100MB 合法，用 `>1MB` + exit 0 判。
- Windows 上看到两个 BaiduPCS-Go 进程先查 CommandLine：scoop shim + 真身的父子对 = **单**下载，勿误判。
- Windows 侧 PowerShell 逻辑一律写 `.ps1` 跑；PowerShell 5.1 用 `-File` 读无 BOM 的中文文件会炸引号，生成内容尽量 ASCII 或写 BOM。
