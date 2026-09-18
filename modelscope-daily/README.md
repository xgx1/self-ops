# ModelScope 每日自动收藏 + 点赞

> 用 `modelscope` 命令每天自动点赞 30 + 收藏 30，维护登录态与定时任务；页面改版导致「点了没反应」时按排障流程修。

## 什么时候用

- 要跑/管理魔搭的每日点赞 + 收藏任务：今天跑没跑、为什么没跑、要不要立刻跑一次。
- 前端改版（点赞图标改名、合集弹窗结构变了）导致点击无效。
- 登录态过期、定时任务失败。

## 怎么用

工具仓库 `~/projects/modelscope-cli`（命令 = `~/.local/bin/modelscope`，软链到 `bin/modelscope`）。

```bash
modelscope login                      # 一次性登录：开有头窗口，扫码/短信后自动检测并保存
modelscope login --phone <11位号码>    # 短信验证码登录（验证码写进 sms-code.txt 交接，不落日志）
modelscope login --timeout 30 --then-run   # 登录完接着跑首轮（首次验收用）
modelscope run                        # 跑一轮：默认点赞 30 + 收藏 30
modelscope run --dry-run              # 只探测不点击（未登录也能跑，用来预演点哪些条目）
modelscope run --headed               # 开窗口跑，肉眼看着它点
modelscope scan <url> --dump          # 诊断：列页面交互控件 + 导出 HTML
modelscope status                     # 状态与最近一次运行
modelscope service install --at 08:30 # 装/更新每日定时任务
modelscope service status | run-now | uninstall
```

其他参数：`--count N`（点赞目标）、`--collection-count N`（收藏目标）、`--no-collection`、`--sources models[,datasets,studios]`、`--max-pages N`。环境变量：`MODELSCOPE_CHROME`（chromium 可执行文件）、`MODELSCOPE_PROXY`、`MODELSCOPE_BASE`。

### 定时任务与日志

```bash
systemctl --user list-timers modelscope-daily.timer --no-pager
systemctl --user start modelscope-daily.service        # 立刻跑一次
journalctl --user -u modelscope-daily.service -n 50 --no-pager
tail -40 ~/.local/state/modelscope-cli/logs/$(date +%F).log
```

`OnCalendar=*-*-* 08:30:00` + `Persistent=true` + `RandomizedDelaySec=300`，`Type=oneshot` 无头运行，不需要 DISPLAY；服务失败（多半是登录态过期）会发桌面通知。退出码：`0` 正常 / `1` 运行异常 / `2` 登录等待超时 / `3` 未登录。

### 排障流程

1. 先看日志尾部，区分「未登录」还是「控件找不到 / 点了没反应」。
2. 控件类：`modelscope scan <出问题的模型详情页>` 看图标名与 `visible`；图标改名了就改 `lib/site.mjs` 顶部的 `LIKE_ICONS` 和 `COLLECTION_ATTR`。
3. 流程类：`modelscope run --dry-run --headed --max-pages 1` 开着窗口看它一步步走。
4. 登录态过期：`modelscope login`，完了 `modelscope run` 验证一轮。
5. **改完必须实测**：`modelscope run --count 2 --collection-count 2 --max-pages 1`，日志里出现「点赞成功 / 收藏成功」才算真跑通——只看「无异常」不算。

## 前置条件

- 工具仓库 `~/projects/modelscope-cli`；运行产物：登录态 `~/.local/share/modelscope-cli/profile`、状态 `~/.local/state/modelscope-cli/state.json`、日志 `~/.local/state/modelscope-cli/logs/YYYY-MM-DD.log`。
- 复用系统里已有的 chromium（`~/.cache/ms-playwright/chromium-*`，`playwright-core` 传 `executablePath`），不额外下载浏览器。
- 站点走直连（默认 `--no-proxy-server`），要代理才设 `MODELSCOPE_PROXY`。

## 注意事项 / 已知坑

- **状态判定一律走接口**：`GET /api/v1/models/{owner}/{name}` 的 `Data.AlreadyStar`（true = 我已点赞），DOM 图标只用于「点得到」和点击后的二次确认。详情页数据到位前 ♡ 会渲染成占位，早期只看 DOM 的版本误判过「已点赞」并写进状态库，那条模型就再也不会被点赞。
- 状态库只采信「已验证」的记录（`markDone(..., verified)`）；怀疑数据有问题就清空 `state.json` 的 `items`，下一轮会用接口逐条重新核对。
- 前端 i18n 把点赞按钮同时标成 `Collection`→「喜欢」和 `Favourite`→「已喜欢」，所以页面上「收藏」和「点赞」就是 **♡ + ＋合集**，不要去找「点赞」二字；`[data-autolog*="addCollection"]` 是收藏入口。
- **列表卡片上的 ♡ 不能点**（展示用，点了跳详情页），工具用 `closest('a')` 排掉，只在详情页操作。
- 收藏弹窗里**全是 `div`/`span`，没有 `button`、没有 checkbox**，按语义选择器写必挂；「添加」按钮靠 class 里的 `acss-1q5keg1` 区分（未选中时多一个 `acss-15zdjft` 禁用态），别用 `.antd5-btn` 抓；合集名是 React 受控组件，必须原生 setter + `dispatchEvent(new Event('input', {bubbles:true}))`。
- 弹窗会挡住下一次点击：必须 `dismissOverlays()`（Esc + 关按钮 + 残留遮罩 `display:none`），处理合集弹窗时要打 `data-mscli-keep="1"` 保护它不被误关。
- **不要用固定 sleep 赌 SPA 渲染**（实测固定 3.5s 在连续二十多页后大面积失败，看着像「控件消失」），改成轮询等元素/接口就绪；条目间隔 3–7s 随机；收藏连败 3 次熔断（硬跑会把当天候选全刷废，实测 21 条）。
- 登录走阿里 passport iframe（`passport.modelscope.cn/mini_login.htm`），**必须用 frame 操作**，不能在主页面直接找输入框。
- 验收：`modelscope status` 的 liked/collected 达目标值；当天日志每条都是「❤️ 点赞成功」「⭐ 收藏成功」或「⏭ 已经点过，跳过」，没有成片 `⚠️`；抽一个模型人工看一眼 ♡ 是实心、合集里有它。
