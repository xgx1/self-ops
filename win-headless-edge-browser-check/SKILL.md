---
name: win-headless-edge-browser-check
description: Windows headless Edge 验证网页：CDP browser 工具端到端验证、msedge.exe --headless --screenshot 截图、msedge 全路径定位、IPv6 探活、npm.cmd、.ps1 包装
---

# Windows 本机 headless Edge + CDP 浏览器验证

在 Windows（无 Chrome、只有 Edge）环境用 browser 工具（xd://browser）驱动网页验证的标准流程。已在本机（Admin Windows 11，Vite 项目）实测两轮。

## 陷阱清单（全部实测踩过）

1. **默认 headless 浏览器不可用**：browser open 不带 app 参数会超时（本机无 Chrome，内置通道失效）。
2. **msedge.exe 不在 PATH**：`hub start` / spawn 用 `msedge.exe` 报 ENOENT。必须全路径：
   `C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe`
   （64 位系统 Edge 装在 x86 目录下）
3. **Vite 监听 IPv6 `[::1]`**：hub start 的 `ready.port` 探活 127.0.0.1 会超时报 NOT ready——进程其实已就绪（log 匹配到 Local: http 即可），直接继续用。
4. **npm.cmd 包装**：hub start 跑 npm 脚本必须 `application: "cmd.exe"`, `args: ["/c", "npm.cmd", "run", "dev"]`，直接 npm.cmd 不行。
5. **端口可能被占用**：vite 会自动切端口（如 5173→5174），以日志输出为准。
6. **临时 profile 别放项目目录**：会触发 Vite watcher 锁文件崩溃。放 `$TEMP`，用完删。

## 标准流程

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

- 页面标题/内容文本（evaluate textContent）
- 键盘翻页 + 边界钳制（末页按键不跳、按钮 disabled）
- 点击跳页 + active 高亮
- 响应式：`page.setViewport` 宽/窄各查一次 `getComputedStyle(...).gridTemplateColumns` + 元素坐标
- 动画：`getAnimations()` playState/currentTime，或 animation-name

## 纯命令行截图模式（不走 CDP）

场景：只需渲染截图验证（生成/修改 HTML 后），无需交互。`where msedge` 和 scoop list 找不到 Edge（PATH 无），可靠定位用注册表：

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

## MSYS bash 三坑（本机实测）

1. **$ 被吞**：bash 内联 `powershell -Command "... $img.Width ..."` 中 `$img` 被 bash 吃掉 → ParserError。解法：把 PowerShell 写 .ps1 文件再 `-File` 执行。
2. **xargs 失效**：`find ... | xargs wc -l` 返回 0/空（Git Bash 环境）。解法：`find "$dir" -name '*.rs' -exec cat {} + | wc -l`。
3. **bash 内联 node -e 引号地狱**：正则含 `'` `"` 混合时写 .js 文件执行（write 工具写文件最稳）。

## HTML 结构校验（无头截图外的快速检查）

node 脚本数开闭标签配对（self-closing + void 元素豁免）。视觉模型不可用时（纯文本工作流）这是主要验证手段。

## 图像处理补充

- PowerShell `-f` 格式符在 bash 内联也会炸（`'{0}x{1}' -f $img.Width` 的 $ 被吃），同样走 .ps1 文件
- `$h-2` 无空格会被 PS 解析成变量名，做算术先 `$h2=[int]($h/2)` 再 `($h - $h2)`（带空格）
