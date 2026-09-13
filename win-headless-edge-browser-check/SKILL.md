---
name: win-headless-edge-browser-check
description: Windows headless Edge 验证网页：CDP browser 工具端到端验证、msedge.exe --headless --screenshot 截图、msedge 全路径定位、IPv6 探活、npm.cmd、.ps1 包装
---

# Windows 本机 headless Edge + CDP 浏览器验证

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行；Windows 专属步骤一律收进「Windows（PowerShell）」小节，不在 Linux 段落里混用。

本技能实测自 Windows（无 Chrome、只有 Edge）环境，Windows 侧内容原样保留；本机现为 Linux，每处都补了可直接执行的「Linux（bash）」小节：Linux 侧不需要 Edge，用 **Playwright 自带 chromium + Playwright MCP 工具** 覆盖同一套验证。

## 陷阱清单（全部实测踩过）

以下 6 条是 Windows 侧陷阱（本机 Admin Windows 11，Vite 项目实测两轮）；对应的 Linux 差异见其后的小节。

1. **默认 headless 浏览器不可用**：browser open 不带 app 参数会超时（本机无 Chrome，内置通道失效）。
2. **msedge.exe 不在 PATH**：`hub start` / spawn 用 `msedge.exe` 报 ENOENT。必须全路径：
   `C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`
   （64 位系统 Edge 装在 x86 目录下）
3. **Vite 监听 IPv6 `[::1]`**：hub start 的 `ready.port` 探活 127.0.0.1 会超时报 NOT ready——进程其实已就绪（log 匹配到 Local: http 即可），直接继续用。
4. **npm.cmd 包装**：hub start 跑 npm 脚本必须 `application: "cmd.exe"`, `args: ["/c", "npm.cmd", "run", "dev"]`，直接 npm.cmd 不行。
5. **端口可能被占用**：vite 会自动切端口（如 5173→5174），以日志输出为准。
6. **临时 profile 别放项目目录**：会触发 Vite watcher 锁文件崩溃。放 `$TEMP`，用完删。

### Linux 侧差异（逐条对应）

1. **浏览器通道**：本机 Linux **没有系统级 chromium/chrome**（`command -v chromium || command -v google-chrome-stable` 两个都为空），也没有 xd://browser hub（`command -v hub` 为空）→ 直接用 `mcp__playwright__*` 工具（本会话已挂载），浏览器二进制用 Playwright 自带的 chromium（`~/.cache/ms-playwright/`，零安装）。
2. **浏览器定位**：没有 msedge.exe 全路径问题；需要路径时用 `command -v chromium || command -v google-chrome-stable`，或用通配确认 Playwright 自带版本的路径（版本号会变）：`ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome`。
3. **IPv6 探活**：同样存在（vite 可能只绑 `[::1]`）。用 `curl -sS -o /dev/null -w '%{http_code}\n' --max-time 3 http://127.0.0.1:<port>`（有 HTTP 状态码即已就绪，连接被拒才是没起来），或用 `ss -ltnp | grep <port>` 看实际绑定地址。
4. **npm.cmd 包装**：Linux 不适用——直接 `npm run dev`，没有 `.cmd` 后缀，也不需要 cmd.exe 包装。
5. **端口占用**：同 Windows，vite 自动切端口，以日志为准。
6. **临时 profile**：用 `mktemp -d` 生成（落在 /tmp），用完 `rm -rf`；同样别放项目目录。

## 标准流程

### Linux（bash）

1. 起 dev server（bash 工具后台跑）：`npm run dev`。就绪判据**看日志里的 `Local: http://localhost:<port>/`**，不要只依赖端口探活（同 Windows 的 IPv6 陷阱）。
2. 探活（可选，用于确认端口）：`curl -sS -o /dev/null -w '%{http_code}\n' --max-time 3 http://127.0.0.1:<port>`；要看绑定的地址族用 `ss -ltnp | grep <port>`。
3. 打开页面：`mcp__playwright__browser_navigate`，`{"url": "http://localhost:<port>"}`。
4. 验证（对应 Windows 侧的 tab.* 操作）：
   - a11y 树：`mcp__playwright__browser_snapshot`（≈ `tab.observe()`）；也可以用 `browser_find` 只搜需要的文本，比整树便宜
   - 查 DOM / computed style：`mcp__playwright__browser_evaluate`
   - 模拟键盘：`mcp__playwright__browser_press_key`（如 `ArrowRight`）
   - 点击：`mcp__playwright__browser_click`（**按选择器点**——与 Windows 侧同一陷阱：evaluate 拿到的元素句柄是序列化副本，不可点击）
   - 视口：`mcp__playwright__browser_resize`（≈ `page.setViewport({width, height})`；`window.resizeTo` 同样无效）
   - 截图：`mcp__playwright__browser_take_screenshot`
5. 收尾：停掉后台 dev server（kill 该 job），`mcp__playwright__browser_close` 关页面。

CDP 在 Linux 上同样可用（不是 Windows 专有）：chromium 一样支持 `--remote-debugging-port=9222`，需要手动接管浏览器时可用 Playwright 的 `chromium.connectOverCDP('http://127.0.0.1:9222')`（标准 API，本机未实测，属可选路径）。

### Windows（PowerShell）

1. 启动 dev server（hub start，cmd.exe /c npm.cmd run dev，ready 用 log 匹配 Local:.*http，port 探活失败可忽略）
2. 启动 headless Edge（hub start，全路径 msedge.exe）：
   ```
   msedge.exe --headless=new --remote-debugging-port=9222 --user-data-dir=C:/Users/Admin/AppData/Local/Temp/edge-<name> --no-first-run --no-default-browser-check about:blank
   ```
   ready 用 port 9222 探活（这个能通）。
3. browser open attach：
   ```json
   {"action":"open","name":"ppt","app":{"cdp_url":"http://127.0.0.1:9222"},"url":"http://localhost:5174","viewport":{"width":1400,"height":900}}
   ```
4. 验证：`tab.observe()` 看 a11y 树；`tab.evaluate` 查 DOM/computed style；`tab.press('ArrowRight')` 模拟键盘；`tab.click('.nav-dot:nth-child(2)')` 点击。
   - **evaluate 里拿到的元素句柄不可点击**（序列化副本）——点击必须用 tab.click 选择器。
   - **window.resizeTo 无效**（headless 窗口限制）——用 `page.setViewport({width, height})`。
   - 截图：`tab.screenshot()` 存到浏览器临时目录，返回路径。
5. 收尾：hub stop 停 dev server 和 Edge；清临时 profile。

## 验证清单（Vite React 项目）

两平台同一套判据；Linux 侧把括号里的 API 换成对应的 Playwright MCP 工具即可。

- 页面标题/内容文本（evaluate textContent）
- 键盘翻页 + 边界钳制（末页按键不跳、按钮 disabled）
- 点击跳页 + active 高亮
- 响应式：视口宽/窄各查一次 `getComputedStyle(...).gridTemplateColumns` + 元素坐标（Linux 用 `browser_resize` 改视口）
- 动画：`getAnimations()` playState/currentTime，或 animation-name

## 纯命令行截图模式（不走 CDP）

场景：只需渲染截图验证（生成/修改 HTML 后），无需交互。

### Linux（bash）

本机无系统级 chromium；**优先用 Playwright 自带的 chromium（零安装，已实测出图）**：

```bash
# 定位（版本号随 Playwright 更新变化，用通配确认）
ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome
CHROME=$(ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome | tail -1)

# 截图。注意：--screenshot= 后面不认 ~，必须用 $HOME 或绝对路径
# （实测 --screenshot=~/out.png 会报 Failed to write file ~/out.png: 没有那个文件或目录）
"$CHROME" --headless --no-sandbox --disable-gpu \
  --screenshot="$HOME/out.png" --window-size=1600,900 \
  'file:///home/sx/projects/<项目>/page.html'
```

要系统级浏览器（可选）：`command -v chromium || command -v google-chrome-stable` —— 本机当前两者都没有，需要时 `sudo pacman -S chromium`（Arch extra 仓库现为 153.x）；装好后把上面命令的 `"$CHROME"` 换成 `chromium` 即可，其余参数相同。

Linux 注意：

- 成功标志与 Windows 一致：`NNN bytes written to file <绝对路径>`（实测 1600x900 出图约 8.3KB）；可用 `identify -format '%wx%h\n' "$HOME/out.png"` 复核尺寸（ImageMagick 本机已装）。
- `--window-size` 的高度只截首屏；长页需加大高度或分段。
- 首次运行有 Fontconfig / dbus portal 的 warning，无害（实测）。
- 纯命令行（无 X / 无 GUI）即可运行，本机实测即为该环境。

### Windows（PowerShell）

`where msedge` 和 scoop list 找不到 Edge（PATH 无），可靠定位用注册表：

```powershell
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe').'(default)'
# → C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
```

bash（MSYS）直接调 exe 会因路径带空格失败，用 PowerShell 包装：

```powershell
& 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' --headless --disable-gpu --screenshot='I:\...\out.png' --window-size=1280,1600 'file:///I:/.../page.html'
```

注意：
- `--screenshot` 后必须 `Start-Sleep 2` 等写盘
- 窗口高度只截首屏；长页需 --window-size 高值或分段
- 成功标志：`NNN bytes written to file`；首次运行有 QQBrowser importer 报错日志，无害

## MSYS bash 三坑（Windows 侧，本机实测）

> 以下为 Windows 上 Git Bash/MSYS 环境特有（第 3 条对 Linux 同样适用）。

1. **$ 被吞**：bash 内联 `powershell -Command "... $img.Width ..."` 中 `$img` 被 bash 吃掉 → ParserError。解法：把 PowerShell 写 .ps1 文件再 `-File` 执行。
2. **xargs 失效**：`find ... | xargs wc -l` 返回 0/空（Git Bash 环境）。解法：`find "$dir" -name '*.rs' -exec cat {} + | wc -l`。（Linux 原生 bash/GNU findutils 下 `xargs` 正常，此坑只在 MSYS。）
3. **bash 内联 node -e 引号地狱**：正则含 `'` `"` 混合时写 .js 文件执行（write 工具写文件最稳）。——两平台通用。

## HTML 结构校验（无头截图外的快速检查）

node 脚本数开闭标签配对（self-closing + void 元素豁免）。视觉模型不可用时（纯文本工作流）这是主要验证手段。

## 图像处理补充

### Windows（PowerShell）

- PowerShell `-f` 格式符在 bash 内联也会炸（`'{0}x{1}' -f $img.Width` 的 $ 被吃），同样走 .ps1 文件
- `$h-2` 无空格会被 PS 解析成变量名，做算术先 `$h2=[int]($h/2)` 再 `($h - $h2)`（带空格）

### Linux（bash）

- 没有 PowerShell 的 `-f` / `$变量` 解析坑，直接在 bash 里取尺寸、裁剪：
  ```bash
  identify -format '%wx%h\n' out.png
  magick out.png -crop 1600x450+0+0 +repage out-part.png
  ```
