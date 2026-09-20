---
name: fcitx-voice-input
description: fcitx5 语音输入（fcitx5-vinput + sherpa-onnx 本地 ASR + LLM 后处理）的运维与排障：按快捷键没反应/不出字、出字但没经 AI 整理、说一大段只回来几个字、改模型与思考等级、无 GUI 链路实测、提示词修改。触发词：语音不能用、语音又坏了、fcitx 语音、vinput、语音输入法、语音不出字、语音没反应、AI 整理、语音识别、语音整理。
---

# fcitx5 语音输入（vinput）

> 平台：Linux（Arch）。命令均为 bash，可直接执行。
> 版本基线：`fcitx5-vinput 2.3.26-1`（2026-09-20 核定）。

## 先判一句话：现在到底能用吗

vinput **唯一的活信号是 daemon journal**——`~/.cache/vinput/context.jsonl` 在本机从未出现过，
不要依赖它。把每次录音的起止配对，量字/秒：

```bash
journalctl --user -u vinput-daemon --no-pager | grep -E 'negotiated format|finish current' | tail -10
```

- 起点：`negotiated format: rate=16000 channels=1 fmt=259`
- 终点：`streaming finish current result bytes=N`（紧跟 `queued final result`）
- 汉字数 ≈ `N/3`，字/秒 = 汉字数 ÷ 起止秒差。**落在 2.7–5.6 = 正常口述语速**；明显低于 ~1.5 = 识别丢内容。

2026-09-20 当日 4 次录音实测：406s→3921B（3.2/s）、13s→94B（2.4/s）、40s→433B（3.6/s）、
36s→385B（3.6/s），全部正常。这条判据可直接用来确认「ASR 这段是不是好的」。

ASR 好 ≠ LLM 后处理好。非 debug 模式下 **LLM 段成功没有任何日志**（实测当日 4 次录音 0 条 LLM 行），
所以「出字但没整理」只能靠开 debug 或直接测 8787 端点来判，见下。

## 现状（2026-09-20 核定）

```
Shift+Alt_L（~/.config/fcitx5/conf/vinput.conf 的 [TriggerKey]）
  → /usr/lib/fcitx5/fcitx5-vinput.so（薄客户端）
  → DBus org.fcitx.Vinput
  → vinput-daemon（systemd 用户服务，dbus 激活，非 enabled 是正常的）
  → sherpa-onnx 流式 ASR：x-asr-1920ms-streaming-zipformer-transducer-zh-en-punct
      （~/.local/share/vinput/models/sherpa-onnx/<模型> → ~/.model/vinput/...，587.6 MB）
  → LLM 后处理（可选，按场景）
  → 回填焦点窗口
```

- 配置唯一来源 `~/.config/vinput/config.json`，**一律用 CLI 改，别手改 JSON**（改完 `systemctl --user restart vinput-daemon`）。
- 场景：`__raw__`（纯 ASR，不走 LLM）/ **`polish`=Markdown 整理（当前激活）** / `__command__`（口令改写选中文本）。
  切换：`vinput scene use <id>`；当前激活看 `vinput scene list` 的 `[*]`。
- LLM：provider `deepseek` → `http://127.0.0.1:8787/v1`（`headroom-deepseek.service`）→ api.deepseek.com，
  模型 `deepseek-flash`，`extra_body` 合并 `reasoning_effort:low` + `thinking.type:enabled`，timeout 120s。
- 客户端必须自己带 key（headroom 只转发）。key 与 `~/.dsh/.credentials.yaml` 的 `DEEPSEEK_API_KEY` 一致，
  但 **config.json 里是明文存储**——注意备份文件同样含明文。
- `polish` 与 `__command__` 均 `raw_cand=false` + `raw_prev=false`，`count` 默认 1
  → 候选恒为 1（只有 LLM 结果）→ **说完直接上屏，零手动选择**；LLM 失败时 daemon 回退原文，仍是单候选自动上屏。
  想手动挑就 `--raw-cand true`（原文变第 1 项默认焦点）。
- 其他本机 headroom：`8788` sensenova、`8789` stepfun。vinput 只配了 8787。

## daemon 日志：能看什么、看不见什么

非 debug 模式下 journal 里只有三种 streaming 噪声（每条录音几十到几千行）加失败行：

| 日志行 | 含义 |
|---|---|
| `negotiated format: rate=16000 channels=1 fmt=259` | 录音开始 |
| `streaming current result bytes=N tokens=N` | 噪声（周期性） |
| `streaming partial result bytes=N decode_iterations=N` | 噪声（周期性） |
| `streaming decode loop completed iterations=N` | 噪声（周期性） |
| `streaming finish current result bytes=N` | 本轮识别结束 |
| `streaming queued final result` | 已交给后处理 |
| `LLM request provider=X url=Y failed after Nms: <原因>` → `processing error: LLM request failed: <原因>` | **LLM 段失败** |
| `LLM response from URL returned no valid candidates` | HTTP 200 但 JSON 里没有可解析候选 |

**没有 LLM 成功日志。** 所以「这次有没有经过 AI 整理」在 journal 里无法直接证实；
只有开 debug（见下）才能看到请求与响应。

## 开 debug 日志（唯一能看到 LLM 段的办法）

```bash
mkdir -p ~/.config/systemd/user/vinput-daemon.service.d
printf '[Service]\nEnvironment=VINPUT_DEBUG=1\n' > ~/.config/systemd/user/vinput-daemon.service.d/debug.conf
systemctl --user daemon-reload && systemctl --user restart vinput-daemon
journalctl --user -u vinput-daemon --since "-3 min" --no-pager | grep vinput-debug
```

debug 行带 `[vinput-debug]` 前缀，包含：`LLM input`（原文）、`LLM request ... headers=[... Authorization: Bearer <key>]`、
`LLM request body`、`LLM request ... status=200 time=NNNN.0ms`、`LLM raw response`、
`stop rejected (phase: postprocessing)`、`phase -> idle`。

⚠️ **debug 会把 Bearer key 和全部识别原文写进 journal**——定位完立刻
`rm -rf ~/.config/systemd/user/vinput-daemon.service.d && systemctl --user daemon-reload && systemctl --user restart vinput-daemon`。

## LLM 请求的真实形态（改提示词前必读）

daemon **不是**把场景提示词原样发出去。它把提示词和识别文本拼进 user message，再追加一段 JSON 契约：

```
<场景 prompt 原文>
<ASR 识别文本>

## Constraints
- Return only the JSON object described below.
- Each candidate must contain only the final rewritten text.
- Do not include explanations, Markdown fences, or extra keys.

## Format
Return up to 1 distinct candidate(s) in a JSON object:
{"candidates": ["<string>"]}
```

请求体另有固定字段：`response_format:{"type":"json_object"}`、`stream:false`、`temperature:0.2`、
加上 provider 的 `extra_body`。

两条由此而来的结论：

1. 提示词里「只输出 Markdown 正文，不要代码围栏」是在**和 daemon 的 JSON 契约抢方向**——
   模型必须最终包成 `{"candidates":[...]}`，正文里的 Markdown 是被 JSON 转义后的字符串。
2. `returned no valid candidates` 就是模型没按 JSON 契约回答（或被 JSON 校验判掉）。
   提示词越啰嗦、越强调「只输出正文」，越容易触发这条。

## 症状 A：按快捷键完全没反应 / 不出字

```bash
vinput daemon status                                  # idle / postprocessing / 未运行
systemctl --user status vinput-daemon --no-pager | head -12
vinput daemon log | tail -20                          # 就是 journalctl --user -u vinput-daemon
```

日志出现 `error while loading shared libraries: libXXX.so.N` + `status=127` = **跨仓库升级的 SONAME 断裂**
（升级本身是成功的，不会出现在 update-app 的失败清单里）。本机实锤：`libprotobuf-lite.so.36.0.0`
在 9/13 与 9/18 反复挂过（journal 共 6 条）。缺的常是**传递依赖**——要找出「谁还在要旧 SONAME」：

```bash
ldd /usr/bin/vinput-daemon | grep 'not found'
ldd /usr/bin/vinput-daemon | awk '/=>/ {print $3}' | while read -r p; do
  [ -f "$p" ] && readelf -d "$p" 2>/dev/null | grep -q 'libprotobuf-lite.so.36.0.0' && echo "要旧 SONAME: $p"
done                                                   # → /usr/lib/libonnxruntime.so.1
pacman -Qo /usr/lib/libonnxruntime.so.1                # → 看哪个包拥有它、当前版本
```

修法：**只装重建版这一个包，不要 `pacman -Sy`**（详见技能 `update-all` 的「更新后缺库体检」）：

```bash
sudo pacman -U --noconfirm ~/下载/onnxruntime-cpu-<重建版>-x86_64.pkg.tar.zst
ldd /usr/bin/vinput-daemon | grep 'not found' || echo OK
systemctl --user restart vinput-daemon && vinput daemon status
```

其他卡启动原因：ASR 模型缺失（`vinput model list` 看「活跃」）、`config.json` 被写坏（有 `.bak.*` 可回滚）、
麦克风设备名失效（见「坑位」）。

## 症状 B：出字了，但没经 AI 整理

LLM 段失败时 vinput **退回原始 ASR 文本照常上屏**，表现为「语音能用但错字全留着、像没整理」，
常被误报成「语音不能用了」。

按顺序判：

```bash
journalctl --user -u vinput-daemon --no-pager | grep -iE 'processing error|no valid candidates|failed after' | tail -8
ss -ltnp | grep 8787                                        # headroom-deepseek 活着没有
KEY=$(grep -m1 'DEEPSEEK_API_KEY' ~/.dsh/.credentials.yaml | sed -E 's/^[^:]+:\s*//')
curl -sS --noproxy '*' -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"model":"deepseek-flash","thinking":{"type":"enabled"},"reasoning_effort":"low","max_tokens":256,
       "messages":[{"role":"user","content":"你好"}]}' -w '\nHTTP:%{http_code}\n' \
  http://127.0.0.1:8787/v1/chat/completions | tail -3
```

- `failed after 60002.8ms: Timeout was reached`：LLM 请求超时（实测值 60s，不是 CLI 的 10s）。
- `returned no valid candidates`：HTTP 200 但没解析出候选，看「LLM 请求的真实形态」。
- `Could not connect to server`：端点没起（历史上有过 `provider=local url=http://localhost:20128/v1` 这种错配）。
- `HTTP:429` + quota exceeded = 套餐额度用尽。旧 `scnet` 链路（127.0.0.1:8789）就是这么死的，
  该 provider、systemd 单元、含旧 key 的备份已全清。**注意 8789 现在被 `headroom-step` 占用了**，别再往那指。
- curl 通但 vinput 慢：headroom 在高负载时会把小请求拖很久（实测 v4-pro 出现过 76s）。语音场景用 `deepseek-flash`。
- **别用 `vinput llm test` 当判据**：它约 10s 硬编码超时，链路正常也会误报 `Timeout was reached`。

## 症状 C：说一大段只回来几个字 / 结果像半截

按这个顺序排除，**别一上来就改提示词**：

1. **先量识别量**（「先判一句话」那节）。字/秒 ≥2.7 就证明 ASR 没丢内容，问题在后两段。
2. **开 debug 查卡死**：若出现 `stop rejected (phase: postprocessing)`，说明 daemon 卡在上一轮后处理、
   **这次停录被拒**，这一轮结果就是坏的。**修法：直接重启 daemon**：
   ```bash
   systemctl --user restart vinput-daemon && vinput daemon status
   ```
   2026-09-18 的一次就是靠这个修好的（当时卡在 postprocessing、13:45:39 出现 stop rejected）。
3. **看提示词有没有「逐字保真」**：漏了它，30 秒口述会被压成模型自己的几条摘要（原文全丢）。
   精简提示词时最容易删的就是这条，见 `references/prompts.md` 的失败模式 5。
4. **看 JSON 契约**：`returned no valid candidates` = 模型没按 `{"candidates":[...]}` 回答，
   此时上屏的是回退原文——看起来「像半截」但不是半截。

## 改配置（一律用 CLI）

```bash
cd ~/.config/vinput && cp -a config.json "config.json.bak.$(date +%Y%m%d-%H%M%S)"   # 先备份（含明文 key）
KEY=$(grep -m1 'DEEPSEEK_API_KEY' ~/.dsh/.credentials.yaml | sed -E 's/^[^:]+:\s*//')

# 换链路 / provider
vinput llm rm <旧provider>                                              # 先清掉，别留死配置
vinput llm add deepseek -u http://127.0.0.1:8787/v1 -k "$KEY" \
  -e '{"thinking":{"type":"enabled"},"reasoning_effort":"low"}'         # -e 合并进每次请求体

# 场景指向新 provider / 模型
vinput scene edit polish      -p deepseek -m deepseek-flash --timeout 120000
vinput scene edit __command__ -p deepseek -m deepseek-flash --timeout 120000
vinput scene use polish

# 改提示词（-t 接正文，{{asr}} / {{selected}} 占位符必须保留）
vinput scene edit polish -t "$(cat polish.txt)"

systemctl --user restart vinput-daemon && vinput daemon status
```

`vinput scene edit <id>` 全部选项：`-l` 标签 / `-t` 提示词 / `-p` provider / `-m` 模型 / `-c` 候选数
（0 = 不走 LLM）/ `--timeout` / `--context-lines`（发给 LLM 的前文行数）/ `--raw-cand` / `--raw-prev`。
其他入口：`vinput config get|set <JSON Pointer>`、`vinput scene list|use`、`vinput model list`、
`vinput device list`、`vinput llm list|add|rm`。

### 为什么 base_url 一律用本机回环

daemon 由 systemd user 启动，继承 `~/.config/environment.d/99-proxy.conf` 的
`all_proxy=socks5://127.0.0.1:7897`，`no_proxy` 只放行 localhost。远端地址会走 clash 的 socks，
而 vinput 的 HTTP 客户端未必编了 socks 支持。→ provider 一律指 `127.0.0.1:<端口>`。

## 延迟实测（2026-09-20 修正）

旧表的短数据无法复核（journal 只保留了 debug 时期的两条硬记录），以硬记录为准：

| 提示词 / 输入 | 耗时 | 来源 |
|---|---|---|
| 7 条规则 + 13 字输入 | **4.82 s** | journal `time=4819.0ms`（9/18） |
| 8 条规则（含逐字保真）+ ~150 字 | **28.68 s** | journal `time=28680.6ms`（9/18），`reasoning_effort:low` + `thinking:enabled` |
| 旧 scnet 链路 | 60.0 s 超时 | journal `failed after 60002.8ms`（9/8） |
| v4-pro 任意输入 | 23–25 s | 9/18 记录，**无 journal 可复核**，勿作决策依据 |

结论：**延迟主要由输入长度和提示词长度决定，不是档位**。短输入 5s 级，长口述 20–30s 是常态，
`low` 也压不住。想提速优先缩短口述或精简提示词，其次才考虑关思考。

## 无 GUI 实测（灌音法）

vinput 只列真实硬件输入设备（`vinput device list` 没有 PipeWire 的 `.monitor`），
虚拟声卡那条路不通；可行的是**声学回路**：把测试音频从扬声器放出来让麦克风拾音。

```bash
# 先找一份 wav——模型目录里已无 test_wavs（960ms 模型 2026-09-20 已删），自备音频
WAV=~/下载/测试音频.wav
vinput recording start; sleep 0.7; paplay "$WAV"; sleep 1.5; vinput recording stop -s polish
journalctl --user -u vinput-daemon --since "-1 min" --no-pager | grep -E 'negotiated|finish current'
```

出现 `negotiated format` + `finish current result bytes=N` = ASR 链路通。
房间回放的识别结果会有错字（正常现象），验证看链路不看准确率。
要验证 LLM 段必须开 debug，或直接把替换好占位符的提示词 curl 8787。

## 提示词

定稿原文 + 恢复方式 + 五个失败模式的设计依据：`references/prompts.md`。**改提示词前必读**。

反复踩的坑（精简时最容易全踩）：

1. 把「要说的话」当「对自己的指令」执行——口述"帮我列个表"，LLM 直接回一张表。
2. 输出形态不符预期——用户要的是 **Markdown 分条**，不是纯文本净稿。
3. 名词识别错却不更正（`head room`→`headroom`）；但要加护栏「判断不出就保留，不许编造」。
4. 口述顺序本来就是乱的（先说第三点再补第一点）——必须要求按逻辑重排。
   注意别提"顺序照原文"，那与需求相反。
5. **漏了「逐字保真」= 口述被改写成简报**（2026-09-18 复发过），是「说一大段只回几个字」的头号嫌疑。

## 坑位

- `vinput device list` 不含 monitor；`vinput config set /global/capture_device` 填了它不认的名字会
  **静默回落到默认设备**（表现为「抓到的全是静音」）。设备名抄 `vinput device list` 里的原文。
- `vinput recording` 有 `start` / `stop` / `toggle`，`stop -s <场景>` 可临时指定场景，可无 GUI 驱动整条链路。
- `fcitx5-vinput` / `sherpa-onnx` 来自 **archlinuxcn**，protobuf / onnxruntime 来自 **extra**——
  跨仓库升级最容易出 SONAME 断裂。
- daemon `is-enabled` 显示 `disabled` 属正常（dbus 激活，内存峰值常态 ~900M、短时冲 1.4G，不值得常驻）。
- 备份习惯：`~/.config/vinput/config.json.bak.<时间戳>`；**备份含明文 key，不要外传**。
- 配置里没有 history/context 写入开关——`context.jsonl` 不要指望。
- `MenuKey`（默认 `Shift_R`）与 `CommandKeys` 在 `~/.config/fcitx5/conf/vinput.conf` 里目前是注释状态，
  生效的是内置默认值，不是显式配置。

## 不确定 / 待确认

以下事项本机证据不足以定论，别当作既定事实写进流程：

1. **`context.jsonl` 的来历不明。** 全盘无此文件、配置里也没有 history 开关，但旧版本文档曾引用它的
   统计（user 3458 / asr 238 / llm 30）并给出上游源码写入点。无法确认是上游默认不写、还是曾被清过。
   → 已按「不存在」处理，全文不再依赖它。
2. **今天 4 次录音全部 ASR 正常，却 0 条 LLM 日志。** 非 debug 模式没有 LLM 成功日志，
   无法区分「LLM 段静默成功」和「LLM 段被跳过」。用户实际使用体验无法从现有证据判定。
3. **旧延迟表里的数字无据可查。** 1.1s 短句 / 10.0s Markdown 整理 / 关思考 1.3s / high 3.8-8.0s /
   max 5.6-22.8s 均无 journal 佐证，只有 4.82s 与 28.68s 两条是硬记录。旧表已删除，未再回填。
4. **`thinking.type` 的合法取值。** DeepSeek 官方是 `enabled` / `disabled`，旧文档写「`disabling` 就是
   最低思考等级」，不确定是否存在第三个值，也未实测 `disabled` 在本链路上的实际行为。
5. **`--context-lines` 的效果未实测。** 选项存在，但它如何与提示词交互、是否值得开，没有数据。
6. **上游源码行号引用未核对。** 旧文档引用 `src/addon/core/vinput.cpp:273`、`dbus/vinput_dbus.cpp:874,901,892`、
   `menu/vinput_menu.cpp:1065`、`src/daemon/postprocess/post_processor.cpp`——本机无源码树，行号与语义均未验证。
   已不写入正文。
7. **8787 是否仍是最优端点。** 本机现有 `8788` sensenova（本会话即 sensenova 模型）与 `8789` stepfun，
   未对比过它们在语音场景的延迟与整理质量。
8. **声学回路的回声问题未验证。** `duck_output_while_recording` 当前为 `false`，录音时扬声器不衰减，
   扬声器播出的音频是否被麦克风拾回并进 ASR，没有实测证据。灌音法测出的错字里可能含这部分。
