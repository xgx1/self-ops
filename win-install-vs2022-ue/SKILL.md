---
name: win-install-vs2022-ue
description: 在 Windows 上静默安装 Visual Studio 2022 Community，带 UE 游戏开发 + .NET 桌面工作负载
---

# Windows 静默安装 Visual Studio 2022（UE 开发）

## 前提

- Windows 10 1709+ 或 Windows 11
- 管理员权限（安装过程会自动提权）

## 安装步骤

### 1. 下载引导程序

```powershell
Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vs_community.exe" -OutFile "$env:TEMP\vs_community.exe"
```

### 2. 通过 VS Installer 安装

引导程序安装完 Installer 后，使用 Installer 的 `install` 命令：

```powershell
Start-Process -FilePath "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" `
  -ArgumentList @(
    "install",
    "--productId", "Microsoft.VisualStudio.Product.Community",
    "--channelId", "VisualStudio.17.Release",
    "--add", "Microsoft.VisualStudio.Workload.NativeGame",
    "--add", "Microsoft.VisualStudio.Workload.ManagedDesktop",
    "--includeRecommended",
    "--quiet",
    "--norestart"
  ) -Wait -NoNewWindow
```

### 3. 验证

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property displayName
# 输出: Visual Studio Community 2022
```

## 踩坑备忘

- **`--wait` 参数**：VS Installer 的 `install` 子命令**不支持** `--wait`，那是 `vs_community.exe` 引导程序的参数。需用 `Start-Process -Wait` 等待。
- **路径空格**：bash shell 下 cmd 传参时路径包含空格会丢失引号，用 `powershell -Command "Start-Process ..."` 包装最可靠。
- **预期耗时**：30-60 分钟（取决于网速）。
