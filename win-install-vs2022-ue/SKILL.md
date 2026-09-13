---
name: win-install-vs2022-ue
description: 在 Windows 上静默安装 Visual Studio 2022 Community，带 UE 游戏开发 + .NET 桌面工作负载
---

# Windows 静默安装 Visual Studio 2022（UE 开发）

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

**平台：仅 Windows（PowerShell）**——本技能的全部安装步骤只在 Windows 上成立；本机 Linux 侧不需要也不会装 Visual Studio，对应做法见下面的「Linux（bash）」小节。

## 前提（Windows）

- Windows 10 1709+ 或 Windows 11
- 管理员权限（安装过程会自动提权）

## Linux（bash）：不需要 Visual Studio

Linux 上没有 VS，也不需要它：UE 的 Linux 原生编译走引擎自带脚本，.NET 侧用 dotnet SDK，IDE 用 Rider / VS Code + C# 扩展。

```bash
command -v dotnet                 # 本机 /usr/bin/dotnet
dotnet --list-sdks                # 本机已装 dotnet-sdk（extra/dotnet-sdk）
command -v rider                  # 本机已装：~/.local/bin/rider
sudo pacman -S dotnet-sdk         # 未装时再执行（Arch extra 仓库，本机当前已装，无需重复）
```

- UE 引擎编译用 Linux 原生脚本：源码引擎的 `Engine/Build/BatchFiles/Linux/Build.sh`（本机存在：`/home/sx/projects/unrealengine/ue6/Engine/Build/BatchFiles/Linux/Build.sh`）；交叉编译与部署细节见技能 `unreal-linux-cross-build-deploy`。
- IDE：本机 Rider 已就位，直接用它打开 UE 项目；未装时**按需安装 Rider/VS Code + C# 扩展**（本页不给具体包名，避免写出跑不通的安装命令）。
- 无对应方案的部分：VS Installer、`setup.exe install`、`vswhere.exe`、MSBuild 工作负载选择在 Linux 上**没有对应方案**（Visual Studio 是 Windows 专有产品）；可替代做法 = dotnet CLI + Rider，功能上覆盖本技能要装的 NativeGame / ManagedDesktop 工作负载所提供的能力。

## Windows（PowerShell）：安装步骤

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

## 踩坑备忘（Windows 侧）

- **`--wait` 参数**：VS Installer 的 `install` 子命令**不支持** `--wait`，那是 `vs_community.exe` 引导程序的参数。需用 `Start-Process -Wait` 等待。
- **路径空格**：bash shell 下 cmd 传参时路径包含空格会丢失引号，用 `powershell -Command "Start-Process ..."` 包装最可靠。
- **预期耗时**：30-60 分钟（取决于网速）。

> Linux 侧不涉及以上任何一条（没有 VS Installer、没有 `--wait` 之争）；Linux 的对应坑位见技能 `unreal-linux-cross-build-deploy`。
