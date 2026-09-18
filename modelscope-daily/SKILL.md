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

参数：`--count N`（点赞目标）、`--collection-count N`（收藏目标）、`--no-collection`、`--sources models[,datasets,studios]`、`--max-pages N`。
环境：`MODELSCOPE_CHROME`（chromium 可执行文件）、`MODELSCOPE_PROXY`（需要代理时）、`MODELSCOPE_BASE`。

## 交互语义（前端产物实测，别凭字面猜）

模型详情页顶部只有两个真按钮：

| 按钮 | 识别方式 | 未做 → 已做 |
| --- | --- | --- |
| 点赞 / 喜欢 | `<use xlink:href="#icon-maasa-shoucangzhuangtai216x16">` | 变实心 `#icon-maasa-zhuangtai3-fill20x20` |
| 收藏（加入合集） | `[data-autolog*="addCollection"]`，文案「＋合集」 | 弹窗里勾选合集并确认 |

**状态判定一律走接口**（`Data.AlreadyStar`），DOM 图标只用于"点得到"和点击后的二次确认。

前端 i18n 把点赞按钮同时标成 `Collection`→「喜欢」和 `Favourite`→「已喜欢」，所以**「收藏」和「点赞」在页面上就是这个 ♡ 加一个 ＋合集**，不要去找「点赞」两个字。

### 收藏（＋合集）弹窗的真实结构

点「＋合集」后弹窗里**全是 `div`/`span`，没有 `<button>`、没有 checkbox**，按语义选择器写必挂。实测形态：

| 状态 | 弹窗文案 | 要做的事 |
| --- | --- | --- |
| 还没有任何合集 | `请选择合集 \| 您还没有合集 \| 新合集 \| 取消 \| 添加` | 点 `新合集` → 填「合集名称」→ 选 `非公开` → 点 `创建` |
| 已有合集 | `请选择合集 \| 最近使用 \| 我的合集 \| 组织合集 \| <合集名> \| 更新 \| N \| 取消 \| 添加` | 点合集名那一行（纯文本 div，点中即选中）→ 点 `添加` |

要点：

- 「添加」按钮靠 class 里的 `acss-1q5keg1` 区分，未选中时多一个 `acss-15zdjft`（禁用态）；**不要**用 `.antd5-btn` 之类去抓。
- 填「合集名称」是 React 受控组件，必须用原生 setter + `dispatchEvent(new Event('input', {bubbles:true}))`，直接赋 `value` 不生效。
- 首次运行会自动建一个**非公开**的合集，默认名 `我的收藏`（可用 `MODELSCOPE_COLLECTION_NAME` 覆盖）。这是站点自己的空状态引导，不是我们造的私有格式。

## 技能中心：把自己写的技能发布上去

```bash
modelscope skill list                      # 列可上传技能与排除原因
modelscope skill publish --dry-run         # 预演，不产生副作用
modelscope skill publish                   # 发布/更新（内容哈希没变就跳过）
        --only a,b   只发布指定技能
        --force      内容没变也重传
        --limit N    本次最多处理 N 个
modelscope skill whitelist [list|init|add|remove|clear]   # 权威名单
modelscope skill blacklist [list|add|remove|clear]
modelscope skill service install --at 09:30               # 每日定时发布
```

发布链路（官方两步，实测）：

1. `POST /openapi/v1/files/upload`，multipart 带 `file=@<技能>.zip` 与 `type=skill` → 拿 `data.id` 当 `skill_file`
2. 技能不存在 → `POST /openapi/v1/skills`（`owner`/`skill_name`/`display_name`/`description`/`skill_file`/`category`/`license`/`tags`/`source_url`）；已存在 → `PATCH /openapi/v1/skills/{owner}/{skill_name}/settings`

**认证直接用已登录浏览器 profile 的 cookie，不需要 API token**（`modelscope login` 之后就能发）。

坑：

- **SKILL.md 的行尾必须是 LF**：CRLF 会让服务端 YAML 解析器读不到 frontmatter 的 `name`，报 `UploadedFileInvalid: SKILL.md YAML frontmatter must contain 'name' field`——**报错说的是缺 name，其实是行尾问题**，别去改 frontmatter。`buildZip()` 打包时会先拷到暂存目录、把 `.md`/`.yml` 归一化成 LF 再压，源文件不动。实测 7 个 CRLF 技能 = 7 个失败，归一化后全部通过。
- `category` 的**实际取值比官方文档短**：只有 `skill-management`、`developer-tools`、`marketing-seo`、`frontend-development`、`ai-media`、`code-quality-testing`、`mobile-development`、`cloud-devops`、`other`（`ai-automation`/`analytics`/`doc-processing` 会报 `InputParameterError`）。
- **上传、创建、更新三个接口都会限流**，都要按 15/30/45s 退避重试（早期只给上传加了重试，结果 7 个技能卡在创建那步）。发布 75 个技能实测触发 40+ 次限流，整轮约 40 分钟。
- 默认「内容哈希没变就不重传」：整轮 75 个里真正上传的只有变更过的那些（补发时 7 新建 + 68 跳过，几分钟跑完）。
- zip 根目录放**一个技能目录**（内部含 `SKILL.md`，可带 `references/`、`scripts/`）；单技能 zip ≤ 5MB。
- `skill_name` 只允许小写字母/数字/连字符，且创建后和 `owner` 一样**不可改**。
- 来源判据（本机 ADR-0006）：自研 = 在自建分组内且没有 `agents/openai.yaml` / `license:` / `compatibility:` 残留；白名单文件一旦非空即为权威名单。

## 坑（都踩过）

- **列表卡片上的 ♡ 不能点**：它是展示用的，点了会跳详情页。工具用 `closest('a')` 把它排掉，只在详情页操作。
- **数据集详情页未登录时不渲染交互控件**；工作室页只有收藏没有合集。所以默认来源只用 `models`（每页 30 个，6 页共 180 个候选，够了）。
- **弹窗会挡住下一次点击**：未登录点 ♡ 会弹登录引导层，Playwright 会一直重试到超时。必须调 `dismissOverlays()`（Esc + 关按钮 + 把残留遮罩 `display:none`），并在处理合集弹窗时给弹窗打 `data-mscli-keep="1"` 保护它不被误关。
- **登录走阿里 passport iframe**：`passport.modelscope.cn/mini_login.htm`。短信登录的字段是 `#fm-sms-login-id`、`#fm-smscode`、协议勾选 `#fm-agreement-checkbox`、发码 `a.send-btn-link`、提交 `button.sms-login`；tab 是 `.login-tabs-tab` 里文案含「短信」的那个。**点「登录/注册」会开弹窗，必须用 frame 操作，不能在主页面直接找输入框。**
- **别信没加载完的 ♡**：详情页数据到位前，♡ 会渲染成占位（图标是未做态、文案显示「喜欢」而不是数字）。早期只看 DOM 的版本因此误判过「已点赞」并把误判写进状态库，那条模型就再也不会被点赞。**权威判据是接口**：`GET /api/v1/models/{owner}/{name}` 的 `Data.AlreadyStar`（true = 我已点赞），`Data.Stars` 是点赞数。页面 DOM 只用来点。
- **状态库只采信「已验证」的记录**：`markDone(..., verified)`，未验证的（纯 DOM 猜的）不会让后续运行整条跳过。发现可疑数据时把 `state.json` 的 `items` 清空即可，下一轮会用接口逐条重新核对。
- **加了接口判据后会提前返回**：接口比 DOM 快，容易在「＋合集」还没渲染时就去点。`clickCollection` 必须先 `waitForCollectionControl()` 等控件出现，别直接 querySelector。
- **不要用固定 sleep 赌 SPA 渲染**：改成轮询等元素/接口就绪（列表页等条目、详情页等 `AlreadyStar`）。实测固定 3.5s 在连续访问二十多页后会大面积失败，看上去像「控件消失」，其实是没渲染完。
- **节奏要慢**：条目间隔 3–7s 随机。连续快速访问会明显变慢甚至拿不到内容。
- **收藏连续失败要熔断**：没有合集、弹窗改版时如果硬跑，会把当天所有候选条目全刷一遍（实测 21 条全废）。代码里连败 3 次就停掉收藏、只保留点赞。
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
