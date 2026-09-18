---
name: modelscope-daily
description: ModelScope（魔搭）每日自动收藏+点赞的运维与排障：modelscope 命令、每天定时任务的登录态维护、按钮点不动/图标改名/合集弹窗没反应时的诊断与修复。触发词：modelscope、魔搭、魔粒、自动点赞、自动收藏、每日任务没跑、收藏点赞、modelscope 命令。
author: Sx
---

# ModelScope 每日自动收藏 / 点赞

工具仓库：`~/projects/modelscope-cli`（命令 = `~/.local/bin/modelscope`，软链到 `bin/modelscope`）
运行产物：登录态 `~/.local/share/modelscope-cli/profile`；状态 `~/.local/state/modelscope-cli/state.json`；日志 `~/.local/state/modelscope-cli/logs/YYYY-MM-DD.log`

## 命令速查

```bash
modelscope login                      # 一次性登录：开有头窗口，扫码/短信后自动检测并保存
modelscope login --timeout 30 --then-run   # 登录完接着跑首轮（首次验收用）
modelscope run                        # 跑一轮：默认点赞 30 + 收藏 30
modelscope run --dry-run              # 只探测不点击（未登录也能跑，用来预演点哪些条目）
modelscope run --headed               # 开窗口跑，肉眼看着它点
modelscope scan <url> --dump          # 诊断：列页面交互控件 + 导出 HTML
modelscope status                     # 状态与最近一次运行
modelscope service install --at 08:30 # 装/更新每日定时任务
modelscope service status | run-now | uninstall
```

参数：`--count N`（点赞目标）、`--collection-count N`（收藏目标）、`--no-collection`、`--sources models[,datasets,studios]`、`--max-pages N`。
环境：`MODELSCOPE_CHROME`（chromium 可执行文件）、`MODELSCOPE_PROXY`（需要代理时）、`MODELSCOPE_BASE`。

## 交互语义（前端产物实测，别凭字面猜）

模型详情页顶部只有两个真按钮：

| 按钮 | 识别方式 | 未做 → 已做 |
| --- | --- | --- |
| 点赞 / 喜欢 | `<use xlink:href="#icon-maasa-shoucangzhuangtai216x16">` | 变实心 `#icon-maasa-zhuangtai3-fill20x20` |
| 收藏（加入合集） | `[data-autolog*="addCollection"]`，文案「＋合集」 | 弹窗里勾选合集并确认 |

前端 i18n 把点赞按钮同时标成 `Collection`→「喜欢」和 `Favourite`→「已喜欢」，所以**「收藏」和「点赞」在页面上就是这个 ♡ 加一个 ＋合集**，不要去找「点赞」两个字。

## 坑（都踩过）

- **列表卡片上的 ♡ 不能点**：它是展示用的，点了会跳详情页。工具用 `closest('a')` 把它排掉，只在详情页操作。
- **数据集详情页未登录时不渲染交互控件**；工作室页只有收藏没有合集。所以默认来源只用 `models`（每页 30 个，6 页共 180 个候选，够了）。
- **弹窗会挡住下一次点击**：未登录点 ♡ 会弹登录引导层，Playwright 会一直重试到超时。必须调 `dismissOverlays()`（Esc + 关按钮 + 把残留遮罩 `display:none`），并在处理合集弹窗时给弹窗打 `data-mscli-keep="1"` 保护它不被误关。
- **点击必须验证**：点完要重新读图标，只有状态真的翻转才算成功；否则把页面提示原文（如「请登录后操作」）当失败原因记下来，别默默算成功。
- **站点走直连**：`modelscope.cn` 国内直连最稳，默认带 `--no-proxy-server`；要走代理才设 `MODELSCOPE_PROXY`。
- **浏览器复用现成的**：用 `~/.cache/ms-playwright/chromium-*` 里已有的 chromium，`playwright-core` 传 `executablePath`，不额外下载浏览器。

## 定时任务

`~/.config/systemd/user/modelscope-daily.{service,timer}`，`OnCalendar=*-*-* 08:30:00` + `Persistent=true` + `RandomizedDelaySec=300`，`Type=oneshot` 无头运行，不需要 DISPLAY。
服务失败（多半是登录态过期）会发桌面通知。

```bash
systemctl --user list-timers modelscope-daily.timer --no-pager
systemctl --user start modelscope-daily.service        # 立刻跑一次
journalctl --user -u modelscope-daily.service -n 50 --no-pager
tail -40 ~/.local/state/modelscope-cli/logs/$(date +%F).log
```

退出码：`0` 正常；`1` 运行异常；`2` 登录等待超时；`3` 未登录（收藏/点赞都做不了）。

## 排障流程

1. 先看日志尾部，区分「未登录」还是「控件找不到 / 点了没反应」。
2. 控件类问题：`modelscope scan <出问题的模型详情页>` 看图标名与 `visible`；图标改名了改 `lib/site.mjs` 顶部的 `LIKE_ICONS` 和 `COLLECTION_ATTR`。
3. 流程类问题：`modelscope run --dry-run --headed --max-pages 1` 开着窗口看它一步步走。
4. 登录态过期：`modelscope login`，完了 `modelscope run` 验证一轮。
5. **改完必须实测**：`modelscope run --count 2 --collection-count 2 --max-pages 1`，看日志里出现「点赞成功 / 收藏成功」才算真跑通——只看「无异常」不算。

## 验收清单（别人接手时按这个核）

- `modelscope status` 的「最近一次运行」里 `liked`/`collected` 达到目标值。
- 当天日志里每条都是「❤️ 点赞成功」「⭐ 收藏成功」或「⏭ 已经点过，跳过」，没有成片的 `⚠️`。
- 抽一个模型详情页人工看一眼：♡ 是实心、合集里有它。
