---
name: headroom-provider-onboard
description: 把一个 OpenAI 兼容的推理模型接进 headroom + DSH（含思考强度档位核实）。触发词：接入 headroom、配置到 headroom、新增 headroom provider、headroom 代理、reasoning_effort、思考强度、推理强度、reasoningEfforts、新模型接 DSH、stepfun/阶跃星辰 接入。
author: Sx
---

# 把推理模型接进 headroom + DSH

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行，无 Windows 对应方案。
> **基线日期**：2026-09-20 实测通过（StepFun Step Plan / step-3.7-flash 走 :8789）。

## 一、请求链（先记住这个拓扑）

```
DSH (llm-pi-ai)  ──►  headroom proxy (:87xx, 本机)  ──►  上游推理 API
   Authorization            OPENAI_TARGET_API_URL            + /v1/chat/completions
   Bearer $XXX_API_KEY      原样转发，不在单元里配 key
```

headroom 是**透传式压缩代理**：它不持有上游密钥，把客户端送来的 `Authorization` 原样转给上游。所以密钥只配在 DSH 侧（`apiKeyEnv`），headroom 单元里**不要**写任何 key。

端口分配（本机既有）：`:8787` DeepSeek、`:8788` SenseNova、`:8789` StepFun Step Plan。新增就往上排。

## 二、三件事

### 1. systemd 用户单元

照抄最接近的既有单元，只改三处：`HEADROOM_PORT`、`OPENAI_TARGET_API_URL`、`Description`。

```ini
[Unit]
Description=Headroom proxy - <名字> on :<端口>
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HEADROOM_PORT=<端口>
Environment=HEADROOM_HOST=127.0.0.1
Environment=HEADROOM_MODE=cache
Environment=HEADROOM_SAVINGS_PROFILE=coding
Environment=HEADROOM_LOSSLESS=1
Environment=HEADROOM_PROTECT_RECENT=3
Environment=HEADROOM_OUTPUT_SHAPER=1
# 必须 0：effort router 会在机械轮把 reasoning_effort 降档，思考强度
# 就不再由 DSH 配置说了算。
Environment=HEADROOM_EFFORT_ROUTER=0
Environment=ALL_PROXY=
Environment=all_proxy=
Environment=HTTP_PROXY=
Environment=http_proxy=
Environment=HTTPS_PROXY=
Environment=https_proxy=
Environment=OPENAI_TARGET_API_URL=<上游 base，见下方规则>
WorkingDirectory=%h
ExecStart=%h/.local/bin/headroom proxy
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

代理变量全清空是**故意的**：本机有 clash 代理，headroom 走它会把上游请求绕远并偶发 TLS 串流；直连才稳。

```bash
systemctl --user daemon-reload
systemctl --user enable --now <name>.service
systemctl --user is-active <name>.service     # active
journalctl --user -u <name>.service -n 20     # 看 Endpoints 段确认上游
```

### 2. headroom 上游 URL 规则（最容易踩错的一步）

headroom 在 `OPENAI_TARGET_API_URL` 后面**自己追加** `/v1/chat/completions`（`proxy/handlers/openai.py`：`upstream_base_url + "/v1" + handler_path`）。所以单元里给的是**去掉 `/v1` 之后的前缀**：

| 上游完整地址 | `OPENAI_TARGET_API_URL` 填 |
|---|---|
| `https://api.deepseek.com/v1/chat/completions` | `https://api.deepseek.com` |
| `https://token.sensenova.cn/v1/chat/completions` | `https://token.sensenova.cn` |
| `https://api.stepfun.com/step_plan/v1/chat/completions` | `https://api.stepfun.com/step_plan` |

**启动日志会直接打印映射**，这是最可靠的核对方式：

```
/v1/chat/completions            → https://api.stepfun.com/step_plan
```

注意日志只印 base，印不出最终拼接结果。用下面的 401 探测确认拼接是否正确。

### 3. DSH 侧 provider（`~/.dsh/settings.yaml` → `llm-pi-ai.providers`）

```yaml
      <route-key>:
        {
          displayName: "<名字> (headroom :<端口>)",
          apiKeyEnv: <XXX_API_KEY>,          # 必须已存在于 ~/.dsh/.credentials.yaml
          api: openai-completions,
          baseURL: "http://127.0.0.1:<端口>/v1",
          reasoning: medium,                 # 会话没选档位时的默认档，务必显式给
          compat:
            {
              supportsReasoningEffort: true,
              supportsDeveloperRole: false,
              maxTokensField: max_tokens
            },
          models:
            [
              {
                  id: <model-id>,
                  name: <model-id>,
                  contextWindow: 262144,
                  maxTokens: 65536,
                  input: [ text ],
                  reasoningEfforts: { low: low, medium: medium, high: high }
                }
            ]
        }
```

改完 `settings.yaml` **不用重启 DSH**（适配器按请求解析）。凭据写入 `~/.dsh/.credentials.yaml` 的 `refs:` 下，`~/.dsh/dsh-env.sh` 会自动导出所有 `*_API_KEY`。

## 三、思考强度配置（本技能的核心：动手前必须查）

**不要照抄别家的档位**。每家只认自己支持的集合，传了不认的值要么被忽略、要么直接 500。动手前查两件事：

1. **上游文档**里该模型的推理强度取值集合与字段名。
2. **本仓 `reasoningEfforts` 的键域**是 DSH 固定的七档：`off / minimal / low / medium / high / xhigh / max`（`packages/llm/llm-pi-ai/src/catalog.ts` 的 `THINKING_LEVEL_GATE`，pi-ai 升级会触发编译期漂移门禁）。

映射规则：`reasoningEfforts` 的**键**是 DSH 菜单档位，**值**是发到线上的 `reasoning_effort`。未声明的档位 `thinkingLevelMap` 为 `null`，选择器自动隐藏。所以**只声明上游真支持的档位**，多余的不要凑。

| 上游支持 | 声明方式 | 效果 |
|---|---|---|
| `low / medium / high` | `{ low: low, medium: medium, high: high }` | 菜单只出这三档 |
| 另有 `xhigh` | 追加 `xhigh: xhigh` | 菜单多出 xhigh |
| 可关闭思考 | 追加 `"off": none`（**键必须加引号**） | 菜单多出 off |
| 完全不思考 | `reasoningEfforts: false` | 整模型关闭推理 |

三个坑：

- **`off` 的键必须加引号**。不加引号在 YAML 1.1 解析器下会变成布尔 `false`，档位静默消失。本机 `yaml` 包是 1.2 不会误判，但保持引号习惯，别依赖解析器版本。
- **上游不支持 `off` 时，`reasoningEffort` 未选会发 `null`**。pi-ai 的 `openai-completions.js`：没选档位且 `thinkingLevelMap.off` 是字符串时才发，`null` 就**不传该字段** → 走服务端默认。这不是错，但要确认服务端默认档符合预期（Step Plan 默认 `medium`）。
- **路由级 `reasoning` 一定要显式给**。pi-ai 的适配器读 `options.reasoningEffort ?? profile.reasoning`；不给的话「会话没选档」就落到上一条的不传行为。

## 四、pi-ai compat 自动检测陷阱

`openai-completions.js` 的 `detectCompat` 按 **baseURL 字符串**猜协议。我们的 baseURL 是 `http://127.0.0.1:87xx/v1`，全部落到「未识别」分支，默认值是：

| 字段 | 未识别时的默认 | Step Plan 需要 | 结论 |
|---|---|---|---|
| `maxTokensField` | `max_completion_tokens` | `max_tokens` | ❌ **必须覆盖**，否则 400 |
| `supportsReasoningEffort` | `true` | `true` | ✅ 默认就对，写明只为显式 |
| `supportsDeveloperRole` | `true`（→ 发 `developer` role） | 文档只见 `system` | ❌ **设 `false`**，退回 `system` |
| `thinkingFormat` | `"openai"` | — | ✅ 默认就走标准 `reasoning_effort` 分支 |
| `requiresStore` | `false` | — | ✅ 默认发 `store: false` |

`maxTokensField` 那条是**静默错**：请求能发出，400 才暴露，所以必须在上线前用第五节的实测钉死。

## 五、实测验证三件套（每次接入必跑）

两个脚本都是 `.mts`（tsx 只有 ESM 输出支持 top-level await，`.ts` 会被当 CJS 报 `Transform failed`），且都以 `process.cwd()` 当 harness 根，所以**必须先在 `~/projects/MyAI/deepseek-harness` 下运行**。脚本自身放在技能目录里，路径用绝对或 `~/projects/...` 都行。

### 1. 401 探测：确认拼接出的上游路径真实存在

```bash
curl -sS -m 30 -w "\nHTTP %{http_code}\n" \
  http://127.0.0.1:<端口>/v1/chat/completions \
  -H "Authorization: Bearer sk-dummy-verify-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"<model-id>","messages":[{"role":"user","content":"hi"}],"max_tokens":32}'
```

**`401 Incorrect API key` = 路径对**（上游路由存在，只是 key 假）；**`404` = 路径错**（多半是 `/v1` 拼重了或缺了）。这是最便宜的端到端核对。

### 2. 配置解析：DSH 是否接受并物化出模型

```bash
cd ~/projects/MyAI/deepseek-harness
node --import tsx/esm <本技能目录>/verify-provider.mts <route-key>
```

期望输出：`resolveProfiles(strict)` 无 `catalogError` / `modelErrors`、`piProvider` 非空、`menu levels` 恰好是上游支持的档位集合。

### 3. 线上载荷：pi-ai 实际发什么

```bash
cd ~/projects/MyAI/deepseek-harness   # 必须：两个脚本都以 cwd 为 harness 根
node --import tsx/esm <本技能目录>/verify-wire.mts <route-key>
```

脚本 monkey-patch `globalThis.fetch` 截下真实请求体，打印每档对应的 `reasoning_effort`、`max_tokens`/`max_completion_tokens`、消息 role 序列。只把「选中的档位没dispatch到配置声明的值」判为失败，其余一律作为 `note:` 提示——不同 provider 合法地用 `max_completion_tokens` 或 `developer` role。期望（Step Plan）：

```
reasoning=undefined  reasoning_effort=undefined  maxTokens=max_tokens roles=["system","user"]
reasoning="low"      reasoning_effort="low"      maxTokens=max_tokens roles=["system","user"]
reasoning="medium"   reasoning_effort="medium"   maxTokens=max_tokens roles=["system","user"]
reasoning="high"     reasoning_effort="high"     maxTokens=max_tokens roles=["system","user"]
```

对 Step Plan 要盯的三条判据：**档位值恰好是 low/medium/high**、**是 `max_tokens`**、**没有 `developer` role**。出现这两条 note 就该回去查第四节：

- `note: 上游用 max_completion_tokens` → `maxTokensField` 没覆盖（见第四节，静默 400）
- `note: 发 developer role` → `supportsDeveloperRole` 没设 `false`

另外那条 note 值得单独知道：`note: 未选档位仍发 reasoning_effort="none"（因为声明了 "off" 映射，思考会被静默关掉）`——声明了 `"off": none` 的 provider，会话不选档位等于**静默关闭思考**。这也是为什么路由级 `reasoning` 必须显式给。

## 六、Step Plan（阶跃星辰）已核实事实 · 2026-09-20

| 项 | 值 |
|---|---|
| Chat Completions 完整地址 | `https://api.stepfun.com/step_plan/v1/chat/completions` |
| `OPENAI_TARGET_API_URL` | `https://api.stepfun.com/step_plan` |
| headroom 端口 | `:8789`（单元 `headroom-step.service`） |
| DSH route key | `step` |
| 密钥 | `STEP_API_KEY`（Step Plan 控制台「接口密钥」，64 位无前缀） |
| 模型 | `step-5-preview`（新一代旗舰基模，**1M tokens 上下文**，最大输出 1M，文本/图片/视频输入） |
| 推理强度 | **仅 `low / medium / high`**；OpenAI 协议字段 `reasoning_effort`，Anthropic 协议 `output_config.effort` |
| 服务端默认档 | `medium`（不传字段时） |
| 思考内容 | 响应的 `reasoning` 字段；要 DeepSeek 风格就传 `reasoning_format="deepseek-style"` → `reasoning_content` |
| `max_tokens` 字段 | **必须** `max_tokens`（不是 `max_completion_tokens`）；该模型默认 `INF` 不限制 |
| 无 | 不支持 `off`/`none`、不支持 `xhigh`/`max` |

### `max_tokens` 上界怎么定

`step-5-preview` 文档写明 `max_tokens` 默认 `INF`、由模型自决。但 DSH 的 `llm-pi-ai` 会把模型条目的 `maxTokens` 当请求上界发出去（`buildBaseOptions` → `options.maxTokens ?? model.maxTokens`），而该字段 schema 要求 `min(1)`，**无法省略**。所以必须给一个数：给太小会截断长回复，给 1M 等于没上界、失控输出会吃掉套餐 Credit。本机取 `131072`（128K）——单条 agent 回复用不到，纯做兜底。

顺带一个限制：模型支持视频输入，但 DSH 的 modality gate 只有 `text` / `image`（`packages/llm/llm-pi-ai/src/catalog.ts` 的 `MODALITY_GATE`），视频在 DSH 里走不通，`input` 只能写 `[ text, image ]`。

文档来源：<https://platform.stepfun.com/docs/zh/step-plan/integrations/reasoning-api>、<https://platform.stepfun.com/docs/zh/guides/models/step-5-preview>、<https://platform.stepfun.com/docs/zh/guides/models/step-3.7-flash>

### 不挂的型号

- `step-router-v1`：按请求特征在 `deepseek-v4-pro` 与 flash 系列之间切换的智能路由，行为不透明，不挂。
- `step-3.7-flash`（198B 稀疏 MoE / 11B 激活，256K 上下文）：旧代，2026-09-20 已被 `step-5-preview` 取代。保留记录以便回滚。
- `step-3.5-flash` / `step-3.5-flash-2603`：更旧的纯文本代际，不挂。

## 七、排障速查

| 症状 | 先查 |
|---|---|
| DSH 报「API 密钥无效」但 key 正确 | baseURL 是不是 headroom 端口；协议是不是 `chat-completions`（headroom 只放行它，走 `/v1/messages` 会被 403 "Request not allowed" 并被 DSH 归类成 AUTH） |
| 404 Not Found | `OPENAI_TARGET_API_URL` 拼错 `/v1`；跑 401 探测 |
| 400 参数错误 | `maxTokensField` 没覆盖（发了 `max_completion_tokens`）；跑第三套 wire 验证 |
| 401 | 上游路径对，密钥没进 `~/.dsh/.credentials.yaml` 或名字和 `apiKeyEnv` 对不上 |
| `reasoning_effort` 没生效 | 档位不在上游支持集合；或 `supportsReasoningEffort` 被误设 `false` |
| 菜单档位消失了 | `reasoningEfforts` 里没声明该键；或 `off` 键没加引号被解析成布尔 |
| 模型不思考了 | 声明了 `off` 但路由级 `reasoning` 没给默认档 |
| 上游请求走了代理超时 | 单元里 `ALL_PROXY/HTTP_PROXY/HTTPS_PROXY` 没清空 |
| 改了配置没反应 | `settings.yaml` 不用重启；**但 systemd 单元改了必须** `systemctl --user restart <name>` |

## 八、回滚

```bash
systemctl --user disable --now <name>.service
rm ~/.config/systemd/user/<name>.service && systemctl --user daemon-reload
# settings.yaml：删掉对应 provider 块（改前留 .bak）
```
