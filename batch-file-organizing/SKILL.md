---
name: batch-file-organizing
description: 批量文件整理工作流：侦察→7z 批量解压→FileOrganizer index 全量索引→概要内容总览。用户要求整理 D/E/I 盘文件、解压压缩包、分析内容时使用。
---

# 批量文件整理工作流（解压 → 索引 → 概要分析）

用户要求"整理三盘文件/分析有什么内容"时使用。目标盘：D/E/I（用户约束只用这三盘）。

## 标准流程

1. **侦察**（先摸规模再动手）：
   - `pwsh -File scan_drives.ps1 -Root X:/`（模板在 C:\Users\Admin\Project\Other\scan_drives.ps1：文件数/总大小/压缩包数/类型 Top40）
   - 压缩包分布：scan_archives.ps1 模式（按目录分组）
   - 磁盘空间检查（解压前必须确认空间足够）

2. **解压**：7z 批量，解到包同目录
   ```powershell
   $packs = Get-ChildItem -Path X:/ -File -Recurse | Where-Object { $_.Name -match '\.(zip|7z|rar|tar|gz|tgz|xz|bz2|tbz2|zst|tzst|lz4|lz)$' -and $_.Name -notmatch '\.part\d+\.rar$' }
   foreach ($p in $packs) { & 7z x -y "-o$($p.DirectoryName)" $p.FullName }
   ```
   **坑**：`& 7z ... "`"$path`""`（带字面引号）会让所有包报"文件名、目录名或卷标语法不正确"——直接传变量。tar 二次解压：解出 .tar 后再解一层。
   失败类型预期：微信 ResUpdateV2 空 zip（Compressed: 0）、__MACOSX AppleDouble（._ 前缀，魔数 00051607，1KB 内）、损坏包——属正常，记录即可。

3. **索引**：FileOrganizer `index` 命令
   ```
   dotnet run --project C:\Users\Admin\Project\Other\FileOrganizer -- index <盘> --out <索引根>
   ```
   生成 `<文件名>-<分类>.md`（镜像目录）+ manifest.csv。63 万文件约 3 分钟。
   索引根**不能**在源树内（自递归 bug，已修复但换盘注意）。分类含魔数探测（无扩展名微信媒体→图片/视频）。

4. **概要分析**：overview.ps1 模式（C:\Users\Admin\Project\Other\overview.ps1）从 manifest.csv 按 顶层/二级/三级/msg 子树 聚合，输出 内容总览.md（目录|文件数|大小|主要分类）。

5. **交付**：报告各区域内容构成（微信 msg\file=收发文件、msg\attach=附件、msg\video=视频、Backup=加密备份等）。

## 用户偏好
- 逐文件 LLM 深读**默认跳过**（用户 2026-08-04 明确：解压出来 + 概要分析即可）。若要做深读：manifest 分片（每片 200）→ 32 agent 并行批次，每 agent 读内容→更新对应 md 描述（替换"（待分析）"占位），文档类 200 文件约 3-5 分钟/agent。
- 软件安装一律 dotnet 生态（NuGet），不 scoop 新装。
- md 文件名保留源扩展防同名冲突（a.png/a.jpg 都输出 a.png.jxl 式）。

## 既有产物（2026-08-04）
- I:\_索引\：634,365 个 md + manifest.csv + 内容总览.md
- D:\_索引\、E:\_索引\：小规模同构
- 微信备份分卷 D:\Downloads\...\wechat\ 的 tar.zst 内容已在 I:\xwechat_files 解压，不要重复解压
