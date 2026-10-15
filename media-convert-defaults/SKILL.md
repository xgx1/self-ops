---
name: media-convert-defaults
description: 压缩/转换默认：tar.xz（7z LZMA2 level 7）、图片 JPEG XL（q95）、视频 AV1（AMD AMF 硬编）；Sx.Cli compress 与 .NET ffmpeg 集成（NuGet、libjxl/av1_amf、tar.xz）。用户已确认默认
---

# 媒体转换/压缩默认方案（用户偏好，2026-08-04 确立）

所有压缩、格式转换任务默认使用 FileOrganizer 工具（C:\Users\Admin\Project\Other\FileOrganizer）的方案。除非用户明确要求其他格式，否则不换。

## 三个默认

| 场景 | 方案 | 关键参数 |
|---|---|---|
| 压缩/归档 | tar.xz（7z 双管道） | LZMA2，`--level 7`（兼顾速度/比率） |
| 图片转换 | JPEG XL | quality 95（→ distance 0.55），effort 7 |
| 视频转换 | AV1（AMD AMF 硬件编码） | CQP qp 25，音轨/字幕 copy |

## 运行方式

```powershell
dotnet run --project C:\Users\Admin\Project\Other\FileOrganizer -- image   <路径> [--quality 95] [--effort 7]
dotnet run --project C:\Users\Admin\Project\Other\FileOrganizer -- video   <路径> [--qp 25] [--quality balanced]
dotnet run --project C:\Users\Admin\Project\Other\FileOrganizer -- archive <路径> [--level 7]
```

- 路径可为文件或目录（递归）；`--out` 指定输出目录（保留相对结构）；`--force` 覆盖；**从不删源文件**
- 图片输出 `<原名>.<原扩展>.jxl`（保留源扩展防 a.png/a.jpg 同名覆盖）；视频输出 `<原名>.av1.mkv`；目录归档输出到父目录 `<目录名>.tar.xz`
- 软件安装一律 dotnet 生态（NuGet），不 scoop 新装

## Sx.Cli 媒体压缩（Sx.Tool 仓库自带）

Sx.Tool 仓库自带压缩功能，入口 `Sx.Cli/Compress/CompressCommand.cs`，核心 `MediaCompressor.cs`。

### 单文件压缩

```bash
dotnet run --project Sx.Cli/Sx.Cli.csproj -- compress single <input> -o <output> [--quality 18]
```

- 视频（.mp4/.mkv/.webm/.mov/.avi/.wmv/.flv/.m4v）→ av1_amf 硬编（AMD AMF），输出 `.mkv`；QVBR quality 默认 18（越低画质越好）。
- 图片 → ImageMagick 转 `.avif`。
- 省略 `-o` 时输出自动放到 `D:\MediaArchive\...`（MediaOrganizer.BuildOutputPath）。
- 退出码：0 成功，1 输入错误/异常，2 超时或失败（源文件永不删除）。
- 视频超时自适应：clamp(大小MB/30, 5, 60) 分钟，约 1.2GB → 41min。

### 批量扫描

```bash
dotnet run --project Sx.Cli/Sx.Cli.csproj -- compress scan [--drives auto] [--out D:\MediaArchive] [--dry-run] [--max-video-mb 1024] [--quality 18]
```

并发：1 视频 + 5 图片，按大小升序处理。

### 前置条件

- `ffmpeg`（含 av1_amf 编码器）与 `ffprobe` 在 PATH；图片需 ImageMagick `magick.exe`。
- 验证：`ffmpeg -hide_banner -encoders | findstr av1_amf`
- 压缩后工具自动跑解码校验（`ffmpeg -v error -i out -f null -`，5min 上限）。

### 实测

1.15GB / 16min mp4 → 351MB mkv（30%），av1_amf quality=18 耗时 ~11.6min。

## 依赖来源

- **ffmpeg**：NuGet `Soenneker.Libraries.FFmpeg`（gyan.dev 静态构建，日更新），输出到 `bin/<config>/<tfm>/Resources/ffmpeg.exe`。含 libjxl、av1_amf、libsvtav1、libx264/265 全部编码器
- **xz**：复用已装 7z（scoop 7zip，NanaZip 覆盖 shim），双管道 `7z a -ttar -so name.tar entry | 7z a -txz -mx=N -si out.tar.xz`，工作目录=父目录、条目=文件名保证 tar 内路径干净

## .NET 项目集成（Console/CLI 调 ffmpeg）

ffmpeg 获取与编码器选择见上"依赖来源"，补充实测细节：

- Soenneker 包定位：`Path.Combine(AppContext.BaseDirectory, "Resources", "ffmpeg.exe")`。
- 视频 → AV1（AMD 硬编，本机 RX 7900 GRE）完整命令：

```
ffmpeg -i in.mp4 -map 0 -c:v av1_amf -usage transcoding -quality balanced -rc cqp -qp_i 25 -qp_p 25 -qp_b 25 -c:a copy -c:s copy -c:t copy -y out.av1.mkv
```

  - AMF 无 CRF，恒定质量用 `-rc cqp` + qp（0-51，25=高质量）；`-quality speed|balanced|quality` 控速度/画质（兼顾速度和时间 → balanced）；`-usage transcoding` 转码档；容器 mkv（AV1 兼容最稳）；音频/字幕 copy 不重压。用户偏好 AMD 硬编，勿默认 libsvtav1。
- 图片 JXL 的 distance 格式化必须 InvariantCulture（C# `ToString("F2", CultureInfo.InvariantCulture)`），否则区域设置会插逗号。
- 已压图片（jpg/webp）转 JXL 平均省 20-30%；无损源（png）转有损 JXL 可能变大。

### tar.xz 双管道 C# 实现要点

- p1 `RedirectStandardOutput`，p2 `RedirectStandardInput`；`p1.stdout.CopyToAsync(p2.stdin)`，等 p1 退出后 `p2.stdin.Close()`。
- 两进程 `WorkingDirectory` 都设为源文件父目录、条目用文件名 → tar 内路径干净（不嵌绝对路径）。
- `-mx=7` 对应 LZMA2:27 档（比率/速度平衡）。
- 目录输入：整体打包一个 tar.xz，不要逐文件拆。

### 通用 CLI 设计要点（FileOrganizer 遵循）

- 输出名保留源扩展（`test.png → test.png.jxl`）：同目录 a.png/a.jpg 同名时防互相覆盖。
- 目录递归：`Directory.EnumerateFiles(path, "*", AllDirectories)` + 扩展名白名单过滤。
- 默认不删源、输出跳过已存在（`--force` 才覆盖），结束打印统计（转换/跳过/失败/节省字节）。
- 外部进程：`ProcessStartInfo { UseShellExecute=false, CreateNoWindow=true }`，退出码非 0 记失败清单。
- 输出保留相对结构：`Path.GetRelativePath(srcRoot, file)` + `--out` 目录。

## 实测验证过的坑（勿重踩）

1. **ffmpeg 7.1 libjxl 编码器无 `-q:v` 和 `-effort_level`**——只有 `-distance`（Butteraugli 距离，默认 1.0，0=无损）和 `-effort`（1-9，默认 7）。q→distance 映射（libjxl 官方）：q≥30 → `0.1 + (100-q)*0.09`（q95≈0.55）；q<30 → `0.53 * (1-q/30)^1.4`
2. **SharpCompress 0.34~0.50 全部没有 xz 写支持**（XZStream 只读；TarWriter 仅 None/GZip/BZip2/LZip）——纯托管 C# 写 xz 是死路，不要尝试
3. **Sdcb.FFmpeg.runtime.windows-x64 只有 DLL 无 ffmpeg.exe**——需要 exe 用 Soenneker 包
4. **XZ.NET 需要外部 liblzma.dll**——非纯托管，弃
5. ffmpeg 静态构建 exe 被 dotnet Process 调用时负数退出码 = 进程崩溃（参数错误常表现为 "Unrecognized option" 而非崩溃）
6. 输出命名必须保留源扩展（同名不同扩展的源文件会互相覆盖输出）

## 验证方式

```powershell
# JXL 可解码
ffmpeg -i out.jxl -frames:v 1 -f null -
# MKV 确为 AV1
ffmpeg -i out.av1.mkv   # 看 "Video: av1"
# tar.xz 完整性
7z t out.tar.xz
7z x -so out.tar.xz | 7z l -si -ttar   # 看 tar 内部结构
```

## 测试素材生成（无现成文件时）

```powershell
ffmpeg -f lavfi -i testsrc=size=800x600:rate=1 -frames:v 1 -y test.png
ffmpeg -f lavfi -i "testsrc=duration=4:size=640x360:rate=30" -f lavfi -i "sine=frequency=440:duration=4" -c:v libx264 -preset ultrafast -c:a aac -shortest -y test.mp4
```
