---
name: fcitx-voice-input
description: fcitx5 语音输入（fcitx5-vinput + sherpa-onnx 本地 ASR + LLM 后处理）的运维与排障：按快捷键没反应/不出字、出字但没经 AI 整理、改模型与思考等级、链路体检与实测验证（灌音法）。触发词：语音不能用、语音又坏了、fcitx 语音、vinput、语音输入法、语音不出字、语音没反应、AI 整理、语音识别。
---

# fcitx5 语音输入（vinput）运维与排障

> **平台约定**：本机主力环境是 Linux（Arch）——命令以 bash 为先、可直接执行。

## 架构（2026-09-18 实测核定）

```
快捷键 Shift+Alt_L
  → fcitx5 插件 /usr/lib/fcitx5/fcitx5-vinput.so（薄客户端，快捷键配在 ~/.config/fcitx5/conf/vinput.conf）
  → DBus org.fcitx.Vinput
  → vinput-daemon（systemd 用户服务，dbus 激活，不常驻开机）
  → 本地 sherpa-onnx 流式 ASR（模型 x-asr-1920ms-...zh-en-punct，模型在 ~/.local/share/vinput/models）
  → 可选 LLM 后处理（场景 scene）→ 回填到焦点窗口
```

- 配置唯一来源：`~/.config/vinput/config.json`（用官方 CLI `vinput` 改，别手改 JSON）。
- LLM 现状：provider `deepseek` → `http://127.0.0.1:8787/v1`（本机 headroom-deepseek 代理，
  systemd 用户服务、开机自启）→ `https://api.deepseek.com`；密钥用 `~/.dsh/.credentials.yaml`
  里的 `DEEPSEEK_API_KEY`（**客户端带 key，headroom 只转发**，所以 provider 里必须填 key）。
  **只有一个 provider，不要留第二份**：旧的 SCNet 链路（`scnet` → 127.0.0.1:8789 的
  headroom-scnet 实例、模型 `DeepSeek-V4-Flash-0731`）2026-09-18 已彻底删除——套餐额度耗尽
  （429）、systemd 单元、provider 条目、含旧密钥的 config 备份全部清掉，不留死配置。
- 场景：`__raw__`（纯 ASR，不走 LLM）/ `polish`=**Markdown 整理**（当前激活：分条 + `##` 归类 +
  行内代码高亮 + 名词更正）/ `__command__`（口令改写选中文本，**无选中时实测原样输出**，
  可安全当听写用）。切换：`vinput scene use <id>`，或按场景菜单键（默认 `Shift_R`）。
  当前激活场景看 `vinput scene list` 的 `[*]`。
  （2026-09-18 曾另建 `doc`=结构化文档场景，用户确认"要 Markdown 分条"后已删除——两者重复。）
- **提示词**：定稿原文 + 设计依据 + A/B 实测见 `references/prompts.md`。改提示词前务必读它——
  语音后处理有三个反复踩过的坑：①把"要说的话"当成"对自己的指令"去执行（口述"帮我列个表"，LLM 直接回了一张表）；
  ②输出格式不符合用户预期（用户 2026-09-18 明确要 **Markdown + 分条**，不要一整段）；
  ③名词识别错却不更正（`head room`→`headroom`、`EXAMHOD`→`EXAMHUD`）。
  另：提示词长度直接决定延迟——11 条规则版实测 18.6s，精简 6 条版 10.0s（同为 flash+low），
  所以现在是精简版；"关思考"能压到 1.3s，但会丢掉 `##` 归类。
- 证据/历史：`~/.cache/vinput/context.jsonl`，每行 `{"source":..., "text":..., "timestamp":...}`。
  写入点全在插件侧（源码 `src/addon/core/vinput.cpp:273` + `dbus/vinput_dbus.cpp:874,901` +
  `menu/vinput_menu.cpp:1065`），**三种来源的含义**：
  **`llm`** = 提交/选中时写下的 LLM 文本（成功走通 LLM 段的主要证据）；**`asr`** = 原始识别文本
  （只有原文进了候选列表时才写，即 `raw_cand=true` 或回退分支）；**`user`** = 输入框上下文缓冲的
  成文文本（你手打的 + 已上屏的内容，落盘时统一标 user；2026-09-18 统计 user 3458 / asr 238 / llm 30）。
  本机已关 raw 候选/预览，所以听写一般只看到 `llm`（+ 稍后一条 `user`），不再出现 `asr`。

## 候选与"要不要手动挑"（raw_cand / raw_prev，2026-09-18 用户明确要求后改定）

语义（源码 `src/daemon/postprocess/post_processor.cpp` + `src/addon/dbus/vinput_dbus.cpp:892`
+ man `vinput-config.5` 三处一致）：

- 候选数组 = 原始识别文本 + LLM 改写结果，**保序去重**；
- `raw_cand=true`（默认）时原始文本**永远排第 1、也是默认焦点**；
- **去重后只剩 1 个候选 → 直接上屏，不弹菜单；>1 个 → 弹菜单让你挑**（判定就是
  `payload.candidates.size() > 1`）。

本机设置（`polish` 与 `__command__` 都是）：`count=1` + `--raw-cand false --raw-prev false`
→ 候选恒为 1（只有 LLM 结果）→ **说完直接上屏，全程零手动选择**；LLM 失败时 daemon 回退原始
文本，也仍是单候选、自动上屏（不会丢字，只是没整理）。
`raw_prev=false` 顺带消掉等待期的原句浮层，以及"回车提前上屏原文"这个会误提交未整理文本的口子。

```bash
vinput scene edit polish      --raw-cand false --raw-prev false
vinput scene edit __command__ --raw-cand false --raw-prev false
systemctl --user restart vinput-daemon
```

改回"想手动挑"就 `--raw-cand true`（原始文本会重新变成第 1 项默认焦点）。

## 为什么 LLM 端点必须是 127.0.0.1

`vinput-daemon` 由 systemd user 启动，会继承 `~/.config/environment.d/99-proxy.conf` 的
`all_proxy=socks5://127.0.0.1:7897`；`no_proxy` 只放行 localhost。远端地址会走 clash 的 socks
（客户端未必编了 socks 支持，可能直接失败）。→ **provider base_url 一律用本机回环**（8787 这类）。

## 故障速查

### A. 按快捷键完全没反应 / 不出字

```bash
vinput daemon status                                   # 守护进程状态：idle / postprocessing / 未运行
systemctl --user status vinput-daemon --no-pager | head -12
vinput daemon log | tail -20                           # 就是 journalctl --user -u vinput-daemon
```

若日志出现 `error while loading shared libraries: libXXX.so.N` + `status=127`：这是**升级换代
SONAME** 的老问题（不走 update-app 失败清单，升级本身是成功的）。2026-09-18 实例：

```bash
ldd /usr/bin/vinput-daemon | grep 'not found'          # → libprotobuf-lite.so.36.0.0 => not found
# 缺的往往不是直接依赖，而是传递依赖：找到「谁还在要旧 SONAME」
ldd /usr/bin/vinput-daemon | awk '/=>/ {print $3}' | while read -r p; do
  [ -f "$p" ] && readelf -d "$p" 2>/dev/null | grep -q 'libprotobuf-lite.so.36.0.0' && echo "要旧 SONAME: $p"
done                                                   # → /usr/lib/libonnxruntime.so.1
pacman -Qo /usr/lib/libonnxruntime.so.1                # → onnxruntime-cpu 1.29.0-2（要装 1.29.0-3）
```

修法（**只装重建版这一个包，不要 `pacman -Sy`**，详见技能 `update-all` 的「更新后缺库体检」）：

```bash
sudo pacman -U --noconfirm ~/下载/onnxruntime-cpu-<重建版>-x86_64.pkg.tar.zst
ldd /usr/bin/vinput-daemon | grep 'not found' || echo OK
systemctl --user restart vinput-daemon && vinput daemon status
```

其他可能卡住启动的原因：ASR 模型文件缺失（`vinput model list` 看「已安装/活跃」）、
`~/.config/vinput/config.json` 被写坏（有 `.bak.*` 备份可回滚）、麦克风设备名失效（见坑位清单）。

### B. 出字了，但没经过 AI 整理 / 命令模式没反应

**这是最容易误判的一条**：LLM 段失败时 vinput 会**退回原始 ASR 文本照常上屏**，历史里只留
`source:asr` 而无 `source:user`。表现为「语音能用但很蠢/错字全留着」，用户常描述成"语音不能用了"。

```bash
ss -ltnp | grep 8787                                   # provider 端点活着没有（headroom-deepseek）
KEY=$(grep -m1 'DEEPSEEK_API_KEY' ~/.dsh/.credentials.yaml | sed -E 's/^[^:]+:\s*//')
curl -sS --noproxy '*' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-flash","thinking":{"type":"enabled"},"reasoning_effort":"high","max_tokens":256,
       "messages":[{"role":"user","content":"你好"}]}' -w '\nHTTP:%{http_code}\n' \
  http://127.0.0.1:8787/v1/chat/completions | tail -3
```

- `HTTP:429` + `Token Plan quota has been exceeded` = **SCNet（国家超算）套餐额度用尽**。
  旧链路 `scnet → 127.0.0.1:8789`（headroom-scnet 实例，模型 `DeepSeek-V4-Flash-0731`）就是这么死的，
  该 systemd 服务随后被删；`~/.dsh/.credentials.yaml` 里也没有 `SCNET_API_KEY` 了。
  该类端点的 `/v1/models` 会返回 `{"object":"list","data":[]}`（别误判成 key 无效，直接打 chat 才准）。
- `curl` 通但 vinput 慢/卡：headroom 在 DSH 高负载时会把小请求拖很久（2026-09-18 实测
  `deepseek-v4-pro` 出现过 **76s**、`total_ms` 里 `opt_ms` 只占 17ms，其余全在上游）。语音场景用
  `deepseek-flash` 更稳。
- **别用 `vinput llm test` 当判据**：它约 10s 硬编码超时，链路正常也会误报 `连接失败：Timeout was reached`。

### C. 改链路 / 模型 / 思考等级（一律用 CLI）

```bash
cd ~/.config/vinput && cp -a config.json "config.json.bak.$(date +%Y%m%d-%H%M%S)"   # 先备份
KEY=$(grep -m1 'DEEPSEEK_API_KEY' ~/.dsh/.credentials.yaml | sed -E 's/^[^:]+:\s*//')
vinput llm add deepseek -u http://127.0.0.1:8787/v1 -k "$KEY" \
  -e '{"thinking":{"type":"enabled"},"reasoning_effort":"low"}'       # -e = 合并进每次请求体；low = 当前档位
vinput llm rm <旧provider>                                            # 旧的清掉，别留死配置
vinput scene edit polish     -p deepseek -m deepseek-flash --timeout 120000
vinput scene edit __command__ -p deepseek -m deepseek-flash --timeout 120000
vinput scene use polish          # 切激活场景：polish=听写+AI整理；__command__=口令改选中文本
systemctl --user restart vinput-daemon && vinput daemon status
```

**思考等级**：DeepSeek 官方是 `reasoning_effort: low|high|max`，配 `thinking.type=enabled|disabled`
（`disabling` 就是"最低思考等级"，2026-09-18 修的那次旧配置正是 `disabled`）。
实测（polish 提示词、经 headroom、同一台机）：

| 模型 + 档位 | 耗时 | 备注 |
|---|---|---|
| flash + thinking + `low` | 1.1 s（短句）/ 10.0 s（Markdown 整理，多要点） | **当前配置**（2026-09-18 用户选定：速度优先 + 要 Markdown 分条） |
| flash + thinking + `low`，但提示词 11 条规则 | 18.6 s（reasoning 4.1k tokens） | 规则越多越慢：同任务精简到 6 条后 10.0s（reasoning 2.2k） |
| flash + **关思考** + `low` | 1.3 s（reasoning 0） | 最快，但只出分条、不做 `##` 归类；判断名词更弱 |
| flash + thinking + `high` | 3.8 / 8.0 s（纯文本提示词时代测的） | 想更细致时改这档；重复内容命中 headroom 前缀缓存时 10ms 级 |
| flash + thinking + `max` | 5.6 / 22.8 s | 长尾明显（reasoning 4.6k tokens） |
| v4-pro + thinking + `high` | 23 / 23 / 25 s | 语音场景太慢，别用 |

### D. 实测验证（不靠人耳，2026-09-18 跑通）

vinput **只列真实硬件输入设备**（`vinput device list` 里没有 PipeWire 的 `.monitor`），
所以虚拟声卡那条路不通；可行的是**声学回路**：把中文测试音频从扬声器放出来让麦克风拾音。

```bash
D=~/.local/share/vinput/models/sherpa-onnx/x-asr-960ms-streaming-zipformer-transducer-zh-en-punct-int8/test_wavs
H=~/.cache/vinput/context.jsonl
before=$(wc -l < "$H")
vinput recording start; sleep 0.7; paplay "$D/1.wav"; sleep 1.5; vinput recording stop -s polish
tail -n +$((before+1)) "$H"            # 新条目出现即链路通
```

判定：出现 `{"source":"llm",...}` = ASR + LLM 整条通（本机已关 raw 候选/预览，所以不再出现 `asr`；
若哪天又看到 `asr` 条目，说明 `raw_cand`/`raw_prev` 被改回 true 了）；出现 `{"source":"user",...}`
= 已提交（需要有焦点窗口时才写）；daemon 日志 `streaming queued final result` = 流水线跑完。
房间回放的识别结果会有错字（`这是第第二种叫呃与 always always` 这种），**这是正常现象，不是故障**
——验证看的是链路不是准确率。
LLM 段可脱机复现：用 `jq` 把场景 prompt 里的 `{{asr}}` / `{{selected}}` 替换掉，直接 curl 8787。

## 坑位清单（实测）

- `vinput device list` **不含 monitor**；`vinput config set /global/capture_device` 填了它不认的名字
  会**静默回落到默认设备**（表现为"抓到的全是静音"）。设备名抄 `vinput device list` 里的原文。
- `vinput --help` 有 `recording start/stop`，可无 GUI 驱动整条链路（`stop -s <场景>` 可临时指定场景）。
- 历史文件的 `source` 是判断"LLM 段是否生效"的最快证据：`llm`=LLM 结果、`asr`=原文进过候选/预览、
  `user`=最终提交（详见上面「候选与要不要手动挑」节）。
- vinput 包来自 **archlinuxcn**（`fcitx5-vinput`、`sherpa-onnx`），protobuf/onnxruntime 来自
  **extra**；跨仓库升级最容易出 SONAME 断裂。
- 有 `.bak` 备份习惯：`~/.config/vinput/config.json.bak.<时间戳>`；出问题先回滚再定位。
- daemon 常驻不必要（1.4G 内存峰值是 ASR 模型）——dbus 激活即用即起，`systemctl --user is-enabled`
  显示 `disabled` 是正常的。
